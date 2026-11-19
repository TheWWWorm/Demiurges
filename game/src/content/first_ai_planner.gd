## Modified for the EL1 Naval Worlds release, 18 November 2026.
class_name ELFirstAIPlanner
extends RefCounted
## Remake option "smarter computer players" (first game, single player): how
## computer heroes are matched to objectives. The original gives each hero in
## turn the cheapest task of its role (ELFirstAI.cost). Here every objective
## is weighed for every free hero in one unit, points of value:
##
##   expected gain - risk - TURN for each day of real walking (route cost
##   over the hero's daily movement)
##
## Roles shift the weights instead of forbidding tasks: the leading hero still
## besieges and hunts, but may take an unguarded site on its way; a strong
## supporter may clear a weak creature or join a siege. The free heroes are
## then matched to objectives together (the assignment with the most value
## in total, not first come first served). Enemy heroes within reach of a
## castle raise the worth of meeting them, and a new threat lets every hero
## reconsider its errand.
##
## Battle risk follows the rule that will decide the battle: the original
## level rule (a player's hero always beats a neutral creature), or the
## estimate below when that switch is on or the enemy is a human player's
## hero (a real duel).

## Points one day of a hero's time is worth.
const TURN := 10.0
## Bonus for an objective the hero already pursues, so plans do not flicker.
const STICK := 15.0
## Exact routes are searched for each hero until this many of its most
## promising objectives are known (at most SEARCHES searches).
const SHORTLIST := 4
const SEARCHES := 14
## Matching costs: an objective a hero cannot take, and staying idle. Waiting
## is worth -IDLE: an errand that costs only walking beats it up to ten days
## away, while one whose expected losses outweigh its worth by more is left.
## A battle the hero is expected to lose (its chance times the prize below
## its chance of losing times the hero's worth) is not taken at all, unless
## it is the last chance to save the castle (see utility).
const BARRED := 1.0e7
const IDLE := 100.0
## Runes a portal visit is worth at most (3 points each) in utility().
const RUNE_COUNT := 10
## Rounds of widening the shortlists of heroes the matching left idle, and
## how many more exact searches each round may make for each of them.
const WIDEN_ROUNDS := 3
## Nights a siege is followed for its worth (siege_nights).
const SIEGE_NIGHTS := 20
## An enemy hero this many days from a castle threatens it.
const THREAT_DAYS := 2.0
## Where an enemy hero was seen is worth a look for this many days.
const SCOUT_DAYS := 3
## Exploration: frontier tiles are grouped in squares of this size; the best
## few groups are offered, each scored by the unexplored tiles around it.
const CLUSTER := 6
const EXPLORE_TILES := 12
const REVEAL_RADIUS := 5
## Two scouts' exploration targets keep at least this many tiles apart (their
## revealed squares would overlap).
const FRONTIER_GAP := 2 * REVEAL_RADIUS
## Share of a siege's worth that finding the way to an unexplored enemy
## castle has for a hero ready to besiege it.
const SCOUT_SHARE := 0.6
## Weight of a siege of a human player's castle against one of a computer's.
const HUMAN_SIEGE := 1.5
## Buildings whose visit has no effect.
const NO_EFFECT := ["GnomeTinkerer"]
## Points of map pickups: a battle artifact, a full global-spell scroll, and
## a part of one (more for each part of the same spell the hero holds).
const ARTIFACT_GAIN := 25.0
const SCROLL_GAIN := 35.0
const PART_GAIN := 12.0

## Castle defence: the damage the threatening heroes would deal is followed
## night by night for this many days; a castle whose expected loss reaches
## SAFETY of its energy left would fall, and only then is a defender pulled
## off its task.
const HOLD_DAYS := 4
const SAFETY := 0.8
## Short lookahead over strategic actions (see _look): sequences of up to
## LOOK_DEPTH actions within LOOK_DAYS days, LOOK_BEAM sequences kept for each
## first action, the LOOK_BRANCH most promising actions tried from each, the
## LOOK_SITES nearest guarded sites examined for each hero. At most LOOK_LEGS
## route searches per planning pass (the rest are estimated), so the pass
## time stays bounded and the result depends only on the world, not on the
## clock. A later step is worth LOOK_DISCOUNT of an earlier one; a sequence
## must beat the best single objective (with its own sequence) by LOOK_MARGIN.
const LOOK_DEPTH := 3
const LOOK_DAYS := 6.0
const LOOK_BEAM := 2
const LOOK_BRANCH := 5
const LOOK_SITES := 3
const LOOK_LEGS := 40
const LOOK_DISCOUNT := 0.85
const LOOK_MARGIN := 10.0
## Living world (an opt-in remake switch): points of a raid on a weakly held
## enemy site, of escorting a weak besieger, the rune share below which a hero
## turns back to a portal and what that turn is worth, and the level below
## which a besieger is weak.
const RAID := 30.0
const ESCORT := 40.0
const RETREAT_SHARE := 0.35
const RETREAT := 50.0
const ESCORT_LEVEL := 8
## Faction doctrines: weights of the gains by objective kind ("defend" the
## worth of meeting a castle's threat, "raid" an enemy site, "hold" extra days
## of castle defence lookahead).
const DOCTRINES := {
	"aggressive": {"hero": 1.3, "tower": 1.25, "monster": 1.1, "mine": 0.9, "node": 0.9, "raid": 1.5, "defend": 0.8, "escort": 0.8},
	"defensive": {"tower": 0.8, "defend": 1.5, "raid": 0.6, "escort": 1.3, "hold": 2},
	"economic": {"mine": 1.25, "node": 1.25, "cut": 1.25, "shop": 1.15, "building": 1.1, "tower": 0.9, "hero": 0.85},
}
const DOCTRINE_NAMES := ["aggressive", "defensive", "economic"]

## Remake switch for the simulator and the checks: the short lookahead
## (on with smarter computer players).
static var lookahead := true

## Each hero's ELFirstAIEconomy.urgent for the current matching.
static var _urgent := {}
## Route cost of the last utility() (movement points) and the cell its route
## ends on (-1, -1 when only estimated); the route of the last _walk().
static var _walked := -1.0
static var _walked_end := Vector2i(-1, -1)
static var _path: Array[Vector2i] = []
## Lookahead route searches made in this pass and their results.
static var _legs := 0
static var _leg_cache := {}
## Living-world answers of the current matching (story actors, doctrine
## tables, defended sites); null outside it, so nothing stale is kept.
static var _living_cache: Variant = null
static var _matchup_shops := {}

# --- Matching ------------------------------------------------------------------

## Gives the free heroes (and, after a new threat, every hero) their objectives.
## Fills `assigned` (hero id -> task) and `reserved` (ELFirstAI._key -> hero id).
static func assign(director: ELAdventureDirector, player: int, heroes: Array[Dictionary], roles: Dictionary, pool: Array, assigned: Dictionary, reserved: Dictionary, free: Array[Dictionary]) -> void:
	_urgent = {}
	_legs = 0
	_leg_cache = {}
	_living_cache = {}
	var seen := threats(director, player)
	_assign(director, player, heroes, roles, pool, assigned, reserved, free, seen)
	# The castle's safety with the heroes now sent to meet its threats: the
	# next pass reconsiders every errand when it has become worse.
	var ai := ELFirstAI.data(director.state, player)
	var after := defence(director, player, seen, interceptors(director.state, player, seen, assigned))
	if after.is_empty(): ai.erase("alarm")
	else: ai.alarm = _deadline(after)
	_living_cache = null

static func _assign(director: ELAdventureDirector, player: int, heroes: Array[Dictionary], roles: Dictionary, pool: Array, assigned: Dictionary, reserved: Dictionary, free: Array[Dictionary], seen: Dictionary) -> void:
	var state := director.state
	var ai := ELFirstAI.data(state, player)
	# The threats to a castle that would fall if no hero met them; meeting
	# one in time is worth more (utility).
	var danger := defence(director, player, seen)
	# Every hero reconsiders its errand when a new enemy threatens the castle,
	# or when the castle would fall despite the heroes the last pass sent to
	# meet its threats, and sooner than that pass found (an enemy closer, the
	# castle weaker, a defender fallen). The bonus for a held errand (STICK)
	# keeps small changes from moving heroes about.
	var previous: Array = ai.get("threats", [])
	var fresh := false
	for id: int in danger:
		if not previous.has(id): fresh = true
	var last := {}
	for pair: Array in ai.get("assigned", []): last[int(pair[0])] = pair[1]
	var covered := defence(director, player, seen, interceptors(state, player, seen, last))
	if not covered.is_empty() and (not ai.has("alarm") or _deadline(covered) < int(ai.alarm)): fresh = true
	if danger.is_empty(): ai.erase("threats")
	else: ai.threats = danger.keys()
	var rows: Array[Dictionary] = free.duplicate()
	var current := {}
	if fresh:
		for hero: Dictionary in heroes:
			if rows.has(hero) or ELGlobalSpells.held(hero) or not assigned.has(int(hero.uid)): continue
			rows.append(hero)
			current[int(hero.uid)] = assigned[int(hero.uid)]
	if rows.is_empty(): return
	var others := {}
	for key: String in reserved:
		if not current.has(int(reserved[key])): others[key] = reserved[key]
	var retry: Dictionary = ai.get("retry", {})
	# Frontier other heroes already walk to.
	var scouted: Array[Vector2i] = []
	for key: String in others:
		if key.begins_with("explore:"): scouted.append(Vector2i(int(key.get_slice(":", 1)), int(key.get_slice(":", 2))))
	# Columns: objective key -> task; utilities[row][key] = points.
	var columns := {}
	_matchup_shops.clear()
	var utilities: Array[Dictionary] = []
	# Each row's options not priced yet, best bound first.
	var rest: Array = []
	var looked := 0
	var free_movement := ELStrategy.free_mode(director)
	for hero: Dictionary in rows:
		var role := int(roles.get(int(hero.uid), 1))
		var night_only := free_movement and int(hero.ap) <= 0
		var options: Array = []
		for task: Dictionary in pool:
			# A spent hero cannot move or use an object today. An adjacent
			# siege can still run at night, without a movement order.
			if night_only and (task.kind != "tower" or not ELStrategy.adjacent(director, hero, state.object(task.target))): continue
			if not ELFirstAI._available(task, hero, others, retry): continue
			if task.kind == "explore" and _near_any(Vector2i(int(task.tile[0]), int(task.tile[1])), scouted): continue
			var bound := utility(director, hero, role, task, danger, false)
			if bound > -INF: options.append([bound, task])
		options.sort_custom(func(a: Array, b: Array): return a[0] > b[0])
		var row := {}
		# Exact values, best first; the search stops once no bound can beat
		# the SHORTLIST-th of them, or after SEARCHES route searches.
		var kept: Array[float] = []
		var walks := {}
		var ends := {}
		var next := 0
		var searched := 0
		var cached_only := {"remaining": 0, "allow_unknown": true}
		while next < options.size() and searched < SEARCHES:
			var option: Array = options[next]
			if kept.size() >= SHORTLIST and option[0] < kept[SHORTLIST - 1]: break
			next += 1
			if not ELFirstAI.forecast_objective(director, hero, option[1], cached_only): continue
			searched += 1
			if not _price(director, hero, role, option[1], danger, row, columns, walks, ends): continue
			kept.append(float(row[ELFirstAI._key(option[1], int(hero.uid))]))
			kept.sort()
			kept.reverse()
		rest.append(options.slice(next))
		if lookahead and not night_only:
			var started := Time.get_ticks_usec()
			_look(director, hero, role, pool, others, retry, danger, row, columns, walks, ends)
			looked += Time.get_ticks_usec() - started
		var held: Dictionary = current.get(int(hero.uid), {})
		if not held.is_empty():
			var points := utility(director, hero, role, held, danger, true)
			if points > -INF:
				var key := ELFirstAI._key(held, int(hero.uid))
				row[key] = points + STICK
				columns[key] = held
		utilities.append(row)
	if director.has_meta("first_ai_stats"):
		var stats: Dictionary = director.get_meta("first_ai_stats")
		stats.lookahead = int(stats.get("lookahead", 0)) + looked
	var keys: Array = columns.keys()
	var matrix := _matrix(rows.size(), keys, utilities)
	var choice := hungarian(matrix)
	# Check proposed duels before looking for a wider set of jobs. Heroes
	# who lost their shortlist to a forecast can still take safer work.
	var budgets: Array[Dictionary] = []
	var approved: Array[Dictionary] = []
	for hero: Dictionary in rows:
		budgets.append({"remaining": 4})
		approved.append({})
	for round in WIDEN_ROUNDS + 1:
		while true:
			var clash := _frontier_clash(rows, choice, keys, columns, utilities)
			if clash.is_empty():
				for index in rows.size():
					if not _matched(choice, index, keys, utilities): continue
					var column := choice[index]
					var key: String = keys[column]
					if approved[index].has(key): continue
					if not ELFirstAI.forecast_objective(director, rows[index], columns[key], budgets[index]):
						ELFirstAI.note_stat(director, player, "fight_assignment_rejected")
						clash = [index, column]
						break
					# Classic gets one movement phase. Free movement checks the
					# route when the order runs and can recover in a later pass.
					if not free_movement and not ELFirstAI.can_start_order(director, rows[index], columns[key], budgets[index]):
						ELFirstAI.note_stat(director, player, "unusable_order_rejected")
						retry[key + "@" + str(rows[index].uid)] = int(state.day) + 1
						clash = [index, column]
						break
					approved[index][key] = true
			if clash.is_empty(): break
			var line: PackedFloat64Array = matrix[clash[0]]
			line[clash[1]] = BARRED
			matrix[clash[0]] = line
			utilities[clash[0]].erase(keys[clash[1]])
			choice = hungarian(matrix)
		if round == WIDEN_ROUNDS: break
		var taken := {}
		for index in rows.size():
			if _matched(choice, index, keys, utilities): taken[keys[choice[index]]] = true
		var widened := false
		for index in rows.size():
			if _matched(choice, index, keys, utilities): continue
			var hero := rows[index]
			var role := int(roles.get(int(hero.uid), 1))
			var left: Array = rest[index]
			var found := 0
			var searched := 0
			var cached_only := {"remaining": 0, "allow_unknown": true}
			while not left.is_empty() and found < SHORTLIST and searched < SEARCHES:
				var task: Dictionary = left.pop_front()[1]
				if taken.has(ELFirstAI._key(task, int(hero.uid))) or not ELFirstAI.forecast_objective(director, hero, task, cached_only): continue
				searched += 1
				if _price(director, hero, role, task, danger, utilities[index], columns, {}, {}): found += 1
			if found > 0: widened = true
		if not widened: break
		keys = columns.keys()
		matrix = _matrix(rows.size(), keys, utilities)
		choice = hungarian(matrix)
	# The result is applied at once: each row's new objective first (a hero
	# left idle keeps its errand only when it was not priced at all, so that
	# nothing else fitted, and no other hero took it), then the reservations,
	# so every shared objective has one holder.
	var given := {}
	for index in rows.size():
		if _matched(choice, index, keys, utilities): given[keys[choice[index]]] = true
	var chosen := {}
	for index in rows.size():
		var uid := int(rows[index].uid)
		var held: Dictionary = current.get(uid, {})
		if _matched(choice, index, keys, utilities):
			var key: String = keys[choice[index]]
			chosen[uid] = _matchup_shops.get(uid, {}).get(key, columns[key])
		elif not held.is_empty() and not utilities[index].has(ELFirstAI._key(held, uid)) and not given.has(ELFirstAI._key(held, uid)) and ELFirstAI.forecast_objective(director, rows[index], held, budgets[index]) and (free_movement or ELFirstAI.can_start_order(director, rows[index], held, budgets[index])): chosen[uid] = held
		else: chosen[uid] = {}
	for uid: int in current:
		reserved.erase(ELFirstAI._key(current[uid], uid))
		assigned.erase(uid)
	for uid: int in chosen:
		var task: Dictionary = chosen[uid]
		if task.is_empty():
			ELFirstAI.note_stat(director, player, "unassigned")
			continue
		var key := ELFirstAI._key(task, uid)
		var held: Dictionary = current.get(uid, {})
		if held.is_empty() or ELFirstAI._key(held, uid) != key or task.get("guard", -1) != held.get("guard", -1):
			task = task.duplicate()
			task.erase("tries")
			task.erase("mark")
		else: task = held
		assigned[uid] = task
		reserved[key] = uid

## Prices `task` exactly into the row of `hero`; false when it does not suit the hero.
static func _price(director: ELAdventureDirector, hero: Dictionary, role: int, task: Dictionary, danger: Dictionary, row: Dictionary, columns: Dictionary, walks: Dictionary, ends: Dictionary) -> bool:
	var points := utility(director, hero, role, task, danger, true)
	if points == -INF: return false
	var key := ELFirstAI._key(task, int(hero.uid))
	row[key] = points
	walks[key] = _walked
	ends[key] = _walked_end
	columns[key] = task
	return true

## The matching's cost matrix: each row's objectives (negated points), then one
## idle column per row.
static func _matrix(count: int, keys: Array, utilities: Array[Dictionary]) -> Array:
	var matrix: Array = []
	for index in count:
		var line := PackedFloat64Array()
		for key: String in keys: line.append(-float(utilities[index][key]) if utilities[index].has(key) else BARRED)
		for other in count: line.append(IDLE if other == index else BARRED)
		matrix.append(line)
	return matrix

## Whether the matching gave row `index` an objective (not an idle column).
static func _matched(choice: Array[int], index: int, keys: Array, utilities: Array[Dictionary]) -> bool:
	var column: int = choice[index]
	return column >= 0 and column < keys.size() and utilities[index].has(keys[column])

## Two rows of the matching whose exploration targets lie within FRONTIER_GAP:
## [row, column] of the one worth less to its hero, or [] when none clash.
static func _frontier_clash(rows: Array[Dictionary], choice: Array[int], keys: Array, columns: Dictionary, utilities: Array[Dictionary]) -> Array:
	var picked: Array = []
	for index in rows.size():
		var column: int = choice[index]
		if column < 0 or column >= keys.size() or not utilities[index].has(keys[column]): continue
		var task: Dictionary = columns[keys[column]]
		if task.get("kind") == "explore": picked.append([index, column, Vector2i(int(task.tile[0]), int(task.tile[1]))])
	for a in picked.size():
		for b in range(a + 1, picked.size()):
			if not _near_any(picked[a][2], [picked[b][2]] as Array[Vector2i]): continue
			var first: Array = picked[a]
			var second: Array = picked[b]
			var worse := first if float(utilities[first[0]][keys[first[1]]]) < float(utilities[second[0]][keys[second[1]]]) else second
			return [worse[0], worse[1]]
	return []

static func _near_any(tile: Vector2i, tiles: Array[Vector2i]) -> bool:
	for other: Vector2i in tiles:
		if maxi(absi(other.x - tile.x), absi(other.y - tile.y)) < FRONTIER_GAP: return true
	return false

## Whether `task` still suits `hero` in `role`: the rules of utility()
## without its route searches (an upper bound of -INF means never).
static func legal(director: ELAdventureDirector, hero: Dictionary, role: int, task: Dictionary) -> bool:
	_urgent.erase(int(hero.get("uid", -1)))
	return utility(director, hero, role, task, {}, false) > -INF

## Nights the siege of `castle` takes to ruin it from the night `hero` is
## there, or -1 when it would not within SIEGE_NIGHTS. Each night the castle
## regains the energy its owner's unused ether gives (ELFirstScenario.regenerate,
## up to its maximum) and takes the damage of this hero and of the player's
## other heroes besieging it that have arrived by then: a partner further
## away joins only on the night its walk (a straight-line estimate, like this
## hero's) brings it there.
static func siege_nights(director: ELAdventureDirector, hero: Dictionary, castle: Dictionary) -> int:
	var state := director.state
	var owner := int(castle.get("owner", -1))
	var record: Dictionary = state.scenario.get("castles", {}).get(owner, {})
	var top := int(record.get("max", record.get("health", 1)))
	var energy := maxi(1, int(record.get("health", 1)) - int(record.get("pending", 0)))
	var damage := ELFirstScenario.hero_value(hero)
	var joins := {}
	if state.players.has(player_of(hero)):
		var own := _arrival(director, hero, castle)
		for pair: Array in ELFirstAI.data(state, player_of(hero)).assigned:
			if int(pair[0]) == int(hero.get("uid", -1)) or pair[1].get("kind") != "tower" or int(pair[1].get("target", -1)) != int(castle.get("uid", -2)): continue
			var other := state.object(pair[0])
			if not other.get("alive", false): continue
			var night := maxi(0, ceili(_arrival(director, other, castle) - own))
			joins[night] = int(joins.get(night, 0)) + ELFirstScenario.hero_value(other)
	var regen := ELFirstScenario.regeneration(ELGlobalSpells.free_ether(state, owner)) if state.players.has(owner) else 0
	for night in SIEGE_NIGHTS:
		damage += int(joins.get(night, 0))
		energy = mini(top, energy + regen) - damage
		if energy <= 0: return night + 1
	return -1

## Days of walking before `hero` stands beside `item` (straight-line estimate).
static func _arrival(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> float:
	return _lower_bound(hero, _area(director, item)) / maxf(1.0, float(hero.get("strategy_capacity", 1)))

## Worth of besieging `castle`: more the fewer nights the siege needs to ruin
## it (siege_nights); one that cannot out-damage the castle's regeneration is
## barely worth holding. A supporter's second attack counts less.
static func siege_gain(director: ELAdventureDirector, hero: Dictionary, role: int, castle: Dictionary) -> float:
	var nights := siege_nights(director, hero, castle)
	var gain := 10.0 if nights < 0 else 100.0 + 400.0 / maxi(1, nights)
	# The human player's castle is the computers' main objective, ahead of
	# one another's.
	if director.is_strategy_human(int(castle.get("owner", -1))): gain *= HUMAN_SIEGE
	return gain * (0.6 if role == 1 else 1.0)

## Worth of taking a map pickup: a battle artifact, a full scroll of a global
## spell the player cannot cast yet, or a part of one. Parts complete a spell
## only on one hero (ELMapPickups.merge), so a part is worth most to the hero
## already holding the most parts of that spell. 0: nothing to gain.
static func pickup_gain(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> float:
	if not ELFirstAI.usable(item) or not ELMapPickups.take_problem(state, hero, item).is_empty(): return 0.0
	if item.get("group") == "artefacts": return ARTIFACT_GAIN
	var profile := state.map.profile
	var player := player_of(hero)
	var colour := str(state.players.get(player, {}).get("color", ""))
	var code := ELMapPickups.resolve(profile, ELMapPickups.scroll_spells(profile, item), colour)
	if code.is_empty() or ELMapPickups.available_codes(state, player).has(code): return 0.0
	# A spell the computer never casts (ELFirstAIEconomy.global_spells) is no
	# reason for a trip: a leader chasing such scrolls falls behind in levels
	# and reaches the enemy castles days later.
	if not ELFirstAIEconomy.castable(code): return 0.0
	if str(item.get("name", "")) == ELMapPickups.FULL: return SCROLL_GAIN
	var own := _parts(profile, hero, code, colour)
	for other: Dictionary in ELFirstAI.heroes_of(state, player):
		if other != hero and _parts(profile, other, code, colour) > own: return PART_GAIN * 0.5
	return PART_GAIN * (1.0 + own)

## Parts of `code` a hero carries.
static func _parts(profile: ELProfile, hero: Dictionary, code: String, colour: String) -> int:
	var count := 0
	for scroll: Variant in hero.get("gs_items", []):
		if scroll is Dictionary and scroll.get("kind") == ELMapPickups.PART and ELMapPickups.resolve(profile, scroll.get("spells", []), colour) == code: count += 1
	return count

## The least-cost matching of rows to distinct columns (rows <= columns).
## Returns each row's column.
static func hungarian(cost: Array) -> Array[int]:
	var n := cost.size()
	var result: Array[int] = []
	result.resize(n)
	result.fill(-1)
	if n == 0: return result
	var m: int = cost[0].size()
	var u := PackedFloat64Array()
	u.resize(n + 1)
	var v := PackedFloat64Array()
	v.resize(m + 1)
	var p := PackedInt32Array()
	p.resize(m + 1)
	var way := PackedInt32Array()
	way.resize(m + 1)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		var minv := PackedFloat64Array()
		minv.resize(m + 1)
		minv.fill(INF)
		var used := PackedByteArray()
		used.resize(m + 1)
		while true:
			used[j0] = 1
			var i0 := p[j0]
			var delta := INF
			var j1 := 0
			var line: PackedFloat64Array = cost[i0 - 1]
			for j in range(1, m + 1):
				if used[j] != 0: continue
				var current := line[j - 1] - u[i0] - v[j]
				if current < minv[j]:
					minv[j] = current
					way[j] = j0
				if minv[j] < delta:
					delta = minv[j]
					j1 = j
			for j in range(0, m + 1):
				if used[j] != 0:
					u[p[j]] += delta
					v[j] -= delta
				else: minv[j] -= delta
			j0 = j1
			if p[j0] == 0: break
		while true:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
			if j0 == 0: break
	for j in range(1, m + 1):
		if p[j] != 0: result[p[j] - 1] = j - 1
	return result

# --- Worth -----------------------------------------------------------------------

## Points of `task` for `hero` (-INF: not for this hero). Without `exact` the
## walk is the straight-line lower bound, so the result is an upper bound
## used to choose which objectives get a real route search.
static func utility(director: ELAdventureDirector, hero: Dictionary, role: int, task: Dictionary, danger: Dictionary, exact: bool) -> float:
	var state := director.state
	var item := state.object(task.get("target", -1))
	var level := int(hero.get("level", 1))
	var day := maxf(1.0, float(hero.get("strategy_capacity", 1)))
	if not _urgent.has(int(hero.uid)): _urgent[int(hero.uid)] = ELFirstAIEconomy.urgent(director, hero)
	var urgent: bool = _urgent[int(hero.uid)]
	var gain := 0.0
	var walk := -1.0
	# Meeting a threat in time to save the castle (see "hero").
	var last := false
	_path = []
	match task.kind:
		"monster":
			if not item.get("alive", false): return -INF
			gain = monster_gain(director, hero, role, item)
			walk = _walk(director, hero, item, true, exact)
			if walk < 0.0: walk = _walk(director, hero, item, false, exact)
		"hero":
			if not item.get("alive", false) or int(item.get("level", 1)) - level >= 2 or not state.hostile(hero, item): return -INF
			walk = _walk(director, hero, item, false, exact)
			var chance := win_chance(director, hero, item)
			var prize := 20.0 + 8.0 * int(item.get("level", 1))
			# A castle that would fall: worth meeting its threat only for a
			# hero that arrives before it falls.
			last = danger.has(int(item.uid)) and walk >= 0.0 and walk / day <= float(danger[int(item.uid)])
			if last: prize += (80.0 + 20.0 * int(item.get("level", 1))) * weight(director, hero, "defend")
			elif role == 1: prize *= 0.7
			gain = chance * prize - (1.0 - chance) * worth(hero)
			# A fight expected to cost more than it brings is taken only as
			# the castle's last chance.
			if gain < 0.0 and not last: return -INF
		"tower":
			if not siege_ready(hero, role, state.map) or not ELFirstScenario.assault_problem(state, hero, item).is_empty(): return -INF
			if level < 6 and siege_nights(director, hero, item) < 0: return -INF
			if urgent and not ELStrategy.adjacent(director, hero, item): return -INF
			gain = siege_gain(director, hero, role, item)
			walk = _walk(director, hero, item, true, exact)
			if walk < 0.0:
				walk = _walk(director, hero, item, false, exact)
				if walk >= 0.0: gain -= 15.0
		"mine", "node", "cut":
			if task.kind == "cut" and not item.get("alive", false): return -INF
			gain = {"mine": 45.0, "node": 60.0, "cut": 15.0}[task.kind]
			# Living world: a raid on an enemy site no enemy hero stands by.
			if task.kind != "cut" and int(item.get("owner", -1)) >= 1 and living(director) and not story_actor(state, hero) and undefended(director, player_of(hero), item): gain += RAID * weight(director, hero, "raid")
			walk = _walk(director, hero, item, true, exact)
			if role == 0:
				# The leader takes only an unguarded site on its way.
				if walk < 0.0 or walk > day: return -INF
				gain *= 0.5
			elif walk < 0.0:
				walk = _walk(director, hero, item, false, exact)
				if walk >= 0.0: gain -= 20.0
		"building":
			if not ELAdditionalBuildings.visit_problem(state, hero, item).is_empty(): return -INF
			var name := str(item.get("name", ""))
			# The Gnome Tinkerer's visit changes nothing (ELAdditionalBuildings.visit).
			if NO_EFFECT.has(name): return -INF
			gain = 30.0 if name in ["Teacher", "Magister", "Master"] else (12.0 if name in ELAdditionalBuildings.WEEKLY_VISITED else 15.0)
			if role == 0: gain *= 0.7
			var dungeon := ELAdditionalBuildings.DUNGEONS.has(name)
			if dungeon:
				gain = monster_gain(director, hero, role, state.object(item.monster))
			walk = _walk(director, hero, item, not dungeon, exact)
			if walk < 0.0 and not dungeon: walk = _walk(director, hero, item, false, exact)
		"shop":
			if task.has("guard"):
				walk = _walk(director, hero, item, true, exact)
				gain = 35.0
			else:
				# The bound assumes a full visit (as many purchases as its worth
				# counts); only shortlisted shops are priced.
				var count := ELFirstAIEconomy.wants(director, hero, item) if exact else (ELFirstAIEconomy.SPELLS_PER_VISIT if item.get("type") == "el1_spell_shop" else RUNE_COUNT)
				if count == 0 or not ELFirstAIEconomy.is_shop(item): return -INF
				walk = _walk(director, hero, item, true, exact)
				if walk < 0.0 and role == 0 and exact:
					var fought := ELFirstAI._fought_cost(director, hero, item)
					walk = -1.0 if fought == ELFirstAI.NONE else float(fought)
					_path = ELFirstAI.last_path
				elif walk < 0.0 and not exact: walk = _walk(director, hero, item, false, false)
				if walk < 0.0: return -INF
				if exact and ELFirstAIEconomy.trip_cost(state, hero, item, int(walk), count) < 0: return -INF
				gain = 12.0 * count if item.get("type") == "el1_spell_shop" else 3.0 * mini(count, RUNE_COUNT)
				if item.get("type") == "rune_shop" and ELFirstAIEconomy.empty_copies(hero) > 0: gain += 60.0
		"explore":
			var tile := Vector2i(int(task.tile[0]), int(task.tile[1]))
			gain = reveal(state, player_of(hero), tile) / 4.0
			if role == 0: gain *= 0.3
			if not exact: walk = _lower_bound(hero, Rect2i(tile, Vector2i.ONE))
			else:
				var closed := ELFirstAI.close_guards(director, hero, -1)
				var path := director.grid.path(Vector2i(hero.x, hero.y), tile)
				for point: Vector2i in closed: director.grid._update_cell(point)
				walk = -1.0 if path.is_empty() else float(director.grid.path_cost(path))
				_path = path
			# A hero ready for a siege looks for the way to an enemy castle it
			# has not found: a share of that siege's worth, the rest of the
			# way (at least the straight line from the frontier) counted in.
			var castle := state.object(int(task.get("toward", -1)))
			if walk >= 0.0 and siege_ready(hero, role, state.map) and not castle.is_empty() and ELFirstScenario.assault_problem(state, hero, castle).is_empty():
				var size: Vector2i = director.grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE)
				var rest := _lower_bound({"x": tile.x, "y": tile.y}, Rect2i(int(castle.x), int(castle.y), size.x, size.y))
				var toward := SCOUT_SHARE * siege_gain(director, hero, role, castle) - TURN * rest / day
				if toward > gain: gain = toward
		"pickup":
			gain = pickup_gain(state, hero, item)
			if gain <= 0.0: return -INF
			walk = _walk(director, hero, item, false, exact)
			# The leader takes only a pickup on its way, as it does a site:
			# its levels and sieges come first (supporters fetch the rest).
			if role == 0 and (walk < 0.0 or walk > day): return -INF
		"escort":
			# Living world: a supporter walks beside a weak besieger.
			if role == 0 or not living(director) or story_actor(state, hero) or int(item.get("uid", -1)) == int(hero.uid) or not item.get("alive", false) or int(item.get("owner", -1)) != player_of(hero): return -INF
			gain = ESCORT
			walk = _walk(director, hero, item, false, exact)
		_:
			return -INF
	if walk < 0.0:
		if exact: ELFirstAI.note_stat(director, int(hero.owner), "objective_no_route")
		return -INF
	# Battles the route forces on the way: movement stops in each other
	# hostile guard area it enters, and its guard strikes first.
	if exact:
		var through := _route_survival(director, hero, _path, int(task.get("target", -1)))
		if through < 1.0:
			gain = through * gain - (1.0 - through) * worth(hero)
			if gain < 0.0 and not last:
				ELFirstAI.note_stat(director, int(hero.owner), "objective_route_risk")
				return -INF
	if living(director) and not story_actor(state, hero):
		# Low on runes: back to a portal, and no new fights meanwhile.
		if low_charges(state, hero):
			if task.kind == "shop" and item.get("type") == "rune_shop": gain += RETREAT
			elif task.kind in ["hero", "tower", "monster"] and gain > 0.0: gain *= 0.6
		if gain > 0.0: gain *= weight(director, hero, task.kind)
	# A hero whose new spells wait for runes goes to a portal first.
	if urgent and task.kind != "shop": gain -= 40.0
	_walked = walk
	_walked_end = _path[-1] if exact and not _path.is_empty() else Vector2i(-1, -1)
	return gain - TURN * walk / day

## Route cost beside `item` (-1: none), or its lower bound without `exact`.
static func _walk(director: ELAdventureDirector, hero: Dictionary, item: Dictionary, clean: bool, exact: bool) -> float:
	if not exact:
		var size: Vector2i = director.grid.footprints.get(int(item.uid), {}).get("size", Vector2i.ONE)
		return _lower_bound(hero, Rect2i(int(item.x), int(item.y), size.x, size.y))
	var cost := ELFirstAI._route_cost(director, hero, item, clean, true)
	_path = ELFirstAI.last_path
	return -1.0 if cost == ELFirstAI.NONE else float(cost)

## The chance `hero` comes through the battles that `path` forces on it: in
## each hostile guard area it enters (other than its target's), movement
## stops and every guard there fights it, guard first (ELStrategy.entered).
## Only creatures and the enemy heroes the player sees count.
static func _route_survival(director: ELAdventureDirector, hero: Dictionary, path: Array[Vector2i], target: int) -> float:
	var state := director.state
	var chance := 1.0
	var met := {}
	for index in range(1, path.size()):
		if not director.interception.cells.has(path[index]): continue
		for guard: int in director.interception.enemies(state, hero, path[index]):
			if guard == target or met.has(guard): continue
			met[guard] = true
			var item := state.object(guard)
			if item.get("type") == "hero" and not ELFirstAI.observed(state, player_of(hero), item): continue
			chance *= win_chance(director, hero, item)
	return chance

## The fewest movement points that can reach beside `area` (a point a tile).
static func _lower_bound(hero: Dictionary, area: Rect2i) -> float:
	var dx := maxi(0, maxi(area.position.x - int(hero.x), int(hero.x) - (area.end.x - 1)))
	var dy := maxi(0, maxi(area.position.y - int(hero.y), int(hero.y) - (area.end.y - 1)))
	return float(maxi(0, maxi(dx, dy) - 1))

static func player_of(hero: Dictionary) -> int:
	return int(hero.get("owner", -1))

## Expected gain from fighting a neutral monster, including a lair's occupant.
static func monster_gain(director: ELAdventureDirector, hero: Dictionary, role: int, monster: Dictionary) -> float:
	# This cheap score ranks candidates. The actual trials decide which fights to take.
	var chance := win_chance(director, hero, monster)
	var prize := 16.0 + 7.0 * int(monster.get("level", 1))
	if ELFirstAI.plays_monster_duel(director, hero, monster):
		var profile := director.state.map.profile
		var level := int(hero.level)
		if level < ELHeroProgression.MAX_LEVEL:
			var needed := ELHeroProgression.threshold(profile, level + 1) - ELHeroProgression.effective(hero)
			var reward := ELHeroProgression.battle_reward(profile, int(monster.level))
			prize += 30.0 * clampf(float(reward) / maxi(1, needed), 0.0, 1.0)
		# A known guard on the frontier is also a scouting opportunity.
		if director.interception.zones.has(int(monster.uid)):
			prize += reveal(director.state, player_of(hero), Vector2i(monster.x, monster.y)) / 4.0
	if role == 1: prize *= 0.8
	return chance * prize - (1.0 - chance) * worth(hero)

## What losing the hero costs.
static func worth(hero: Dictionary) -> float:
	return 30.0 + 12.0 * int(hero.get("level", 1))

# --- Threats -------------------------------------------------------------------

## Enemy heroes the player sees within THREAT_DAYS of one of its castles:
## enemy id -> days to the castle.
static func threats(director: ELAdventureDirector, player: int) -> Dictionary:
	var state := director.state
	var result := {}
	var castle := ELFirstScenario.castle_object(state, player)
	if castle.is_empty() or not ELFirstScenario.alive(state, player): return result
	var size: Vector2i = director.grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE)
	var area := Rect2i(int(castle.x), int(castle.y), size.x, size.y)
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or not item.get("alive", false) or int(item.get("owner", -1)) < 1 or int(item.owner) == player: continue
		if not ELFirstAI.observed(state, player, item) or not state.hostile(item, castle): continue
		var day := maxf(1.0, float(item.get("strategy_capacity", 1)))
		if _lower_bound(item, area) > THREAT_DAYS * day: continue
		var route := ELFirstAI._route_cost(director, item, castle, false)
		if route == ELFirstAI.NONE or route > THREAT_DAYS * day: continue
		result[int(item.uid)] = route / day
	return result

## Whether the player's castle holds against `seen` (threats(): enemy id ->
## days to the castle). Each threat strikes every night from its arrival with
## its castle damage (ELFirstScenario.hero_value); the castle regains its
## daily regeneration. Heroes standing by the castle do not protect it (in
## the first game a hero has no guard area, so an enemy walks past it): only
## the heroes of `guards` (enemy id -> heroes sent to attack it, see
## interceptors) do, each from the night it can reach the enemy, by the
## chance it wins that battle (win_chance). A castle whose expected loss
## within HOLD_DAYS (more under a defensive doctrine) reaches SAFETY of its
## energy left would fall. Returns, for a castle that would fall, its
## threats: enemy id -> days until the fall (a defender must meet the enemy
## within them); empty when the castle holds.
static func defence(director: ELAdventureDirector, player: int, seen: Dictionary, guards := {}) -> Dictionary:
	var result := {}
	if seen.is_empty(): return result
	var state := director.state
	var castle := ELFirstScenario.castle_object(state, player)
	var record: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if castle.is_empty() or record.is_empty(): return result
	var left := float(int(record.get("health", 0)) - int(record.get("pending", 0)))
	var regen := float(ELFirstScenario.regeneration(maxi(0, ELFirstAIEconomy._daily_ether(state, player))))
	var horizon := HOLD_DAYS + int(_doctrine_table(director, player).get("hold", 0))
	var nights := PackedFloat64Array()
	nights.resize(horizon)
	for id: int in seen:
		var enemy := state.object(id)
		# The chance the enemy still stands on each night: a defender's battle
		# comes before the night's assaults.
		var through := PackedFloat64Array()
		through.resize(horizon)
		through.fill(1.0)
		for guard: Dictionary in guards.get(id, []):
			var route := ELFirstAI._route_cost(director, guard, enemy, false, true)
			if route == ELFirstAI.NONE: continue
			var met := maxi(0, ceili(float(route) / maxf(1.0, float(guard.get("strategy_capacity", 1)))) - 1)
			var lost := 1.0 - win_chance(director, guard, enemy)
			for night in range(met, horizon): through[night] *= lost
		for night in range(maxi(0, ceili(float(seen[id])) - 1), horizon): nights[night] += through[night] * ELFirstScenario.hero_value(enemy)
	var loss := 0.0
	for night in horizon:
		loss = maxf(0.0, loss + nights[night] - (regen if night > 0 else 0.0))
		if loss >= left * SAFETY:
			for id: int in seen: result[id] = float(night + 1)
			return result
	return result

## The heroes of `tasks` (hero id -> objective) sent to attack one of the
## threats `seen`: enemy id -> those heroes.
static func interceptors(state: ELAdventureSession, player: int, seen: Dictionary, tasks: Dictionary) -> Dictionary:
	var result := {}
	for uid: int in tasks:
		var task: Dictionary = tasks[uid]
		var target := int(task.get("target", -1))
		if task.get("kind") != "hero" or not seen.has(target): continue
		var hero := state.object(uid)
		if not hero.get("alive", false) or int(hero.get("owner", -1)) != player: continue
		if not result.has(target): result[target] = []
		result[target].append(hero)
	return result

## The soonest fall of a defence() result, in days.
static func _deadline(falls: Dictionary) -> int:
	var soonest := 1 << 20
	for id: int in falls: soonest = mini(soonest, int(falls[id]))
	return soonest

static func _area(director: ELAdventureDirector, item: Dictionary) -> Rect2i:
	var size: Vector2i = director.grid.footprints.get(int(item.get("uid", -1)), {}).get("size", Vector2i.ONE)
	return Rect2i(int(item.get("x", 0)), int(item.get("y", 0)), size.x, size.y)

# --- Lookahead -------------------------------------------------------------------

## A short beam search over strategic actions for one hero, on a light
## abstract state (where the hero stands, days spent, the objectives done,
## the guards cleared, the chance it is still alive), never a copy of the
## world. Actions are the hero's shortlisted objectives (capture or raid a
## site, clear a creature, shop and resupply, meet an enemy or a castle's
## threat, a siege), each with its travel time (route cost over the daily
## movement), worth and risk as utility() prices them, and the guarded sites
## near the hero, which open once the creatures on their way are cleared.
## When a sequence beginning with another objective beats the best single
## objective (followed by its own best sequence) by LOOK_MARGIN, that first
## objective's worth in `row` is raised so the matching prefers it. Only the
## world the player sees or remembers is used (the objectives, explored
## ground, guards on explored routes).
static func _look(director: ELAdventureDirector, hero: Dictionary, role: int, pool: Array, others: Dictionary, retry: Dictionary, danger: Dictionary, row: Dictionary, columns: Dictionary, walks: Dictionary, ends: Dictionary) -> void:
	var state := director.state
	var player := player_of(hero)
	var uid := int(hero.uid)
	var day := maxf(1.0, float(hero.get("strategy_capacity", 1)))
	var here := Vector2i(int(hero.x), int(hero.y))
	var acts: Array[Dictionary] = []
	var by_key := {}
	var ratio := 0.0
	var samples := 0
	for key: String in row:
		var act := _act(director, hero, columns[key], key, float(row[key]), float(walks.get(key, -1.0)), ends.get(key, Vector2i(-1, -1)))
		if act.is_empty(): continue
		acts.append(act)
		by_key[key] = act
		var bound := _lower_bound(hero, act.area)
		if bound > 0.0 and act.walk > 0.0:
			ratio += act.walk / bound
			samples += 1
	# Movement points per tile, from the routes searched, for estimated legs.
	var per_tile := 2.0 if samples == 0 else ratio / samples
	# Look for a route a guard can open to resources or useful supplies.
	var sites: Array = []
	for task: Dictionary in pool:
		if task.kind not in ["mine", "node", "shop"]: continue
		if not ELFirstAI._available(task, hero, others, retry): continue
		var item := state.object(task.target)
		if not item.get("alive", false) or not ELFog.explored(state, player, Vector2i(int(item.x), int(item.y))): continue
		var bound := _lower_bound(hero, _area(director, item))
		if bound * per_tile > LOOK_DAYS * day: continue
		sites.append([bound, int(task.target), task])
	sites.sort_custom(func(a: Array, b: Array): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	# The way to a site may lead over a guard's own cell (a creature standing
	# in a passage): it is open once the creature is beaten.
	var bodies: Array = []
	for id: int in director.interception.zones:
		var guard := state.object(id)
		if guard.get("type") == "monster" and state.hostile(guard, hero) and ELFog.explored(state, player, Vector2i(int(guard.x), int(guard.y))): bodies.append(id)
	var blocked_guard := {}
	var blocked_value := 0.0
	for entry: Array in sites.slice(0, LOOK_SITES):
		if _legs >= LOOK_LEGS: break
		var task: Dictionary = entry[2]
		var item := state.object(task.target)
		var supplies := ELFirstAIEconomy.wants(director, hero, item) if task.kind == "shop" else 0
		if task.kind == "shop" and supplies == 0: continue
		_legs += 1
		if ELFirstAI._route_cost(director, hero, item, true, true) != ELFirstAI.NONE: continue
		var opened := _open_bodies(director, bodies)
		var path := director.grid.approach(here, item)
		_close_bodies(director, opened)
		if path.is_empty(): continue
		var guards := {}
		for cell: Vector2i in path:
			if not director.interception.cells.has(cell): continue
			for guard: int in director.interception.enemies(state, hero, cell): guards[guard] = true
		if guards.is_empty(): continue
		var fights: Array[int] = []
		for guard: int in guards:
			var fight := {"kind": "monster", "target": guard}
			var key := ELFirstAI._key(fight, uid)
			var creature := state.object(guard)
			if not by_key.has(key):
				var listed := false
				for other: Dictionary in pool: if other.kind == "monster" and int(other.target) == guard: listed = true
				if not listed or not ELFirstAI._available(fight, hero, others, retry) or not ELFog.explored(state, player, Vector2i(int(creature.x), int(creature.y))): break
				var points := utility(director, hero, role, fight, danger, true)
				if points == -INF: break
				var act := _act(director, hero, fight, key, points, _walked, _walked_end)
				if act.is_empty(): break
				acts.append(act)
				by_key[key] = act
				columns[key] = fight
			fights.append(guard)
		if fights.size() != guards.size(): continue
		var base := 45.0 if task.kind == "mine" else 60.0 if task.kind == "node" else minf(60.0, 15.0 + 5.0 * supplies)
		if living(director) and not story_actor(state, hero): base *= weight(director, hero, task.kind)
		# This guard alone opens the route, even when the guarded errand takes
		# more than one day to reach. Use the best opportunity it opens.
		if fights.size() == 1:
			var key := ELFirstAI._key({"kind": "monster", "target": fights[0]}, uid)
			var act: Dictionary = by_key[key]
			var unlocked := float(act.gain) - TURN * float(act.walk) / day + 0.65 * base
			row[key] = maxf(unlocked, float(row.get(key, -INF)))
			var fight: Dictionary = columns[key]
			if base > blocked_value and not ELFirstAI.forecast_objective(director, hero, fight, {"remaining": 0, "allow_unknown": true}):
				blocked_guard = state.object(fights[0])
				blocked_value = base
		var key := ELFirstAI._key(task, uid)
		if by_key.has(key): continue
		if role == 0 and task.kind != "shop": base *= 0.5
		var site := {"key": key, "kind": task.kind, "area": _area(director, item), "gain": base, "chance": 1.0, "blockers": fights, "walk": -1.0, "end": false, "site": task.kind != "shop", "stand": Vector2i(-1, -1)}
		acts.append(site)
		by_key[key] = site
	if not blocked_guard.is_empty():
		_add_matchup_shop(director, hero, blocked_guard, blocked_value, pool, others, retry, row, columns)
	# Beam search: LOOK_BEAM sequences per first action and depth.
	var best := {}
	var beam: Array = [{"stand": here, "days": 0.0, "value": 0.0, "alive": 1.0, "done": {}, "cleared": {}, "first": "", "end": false}]
	for depth in LOOK_DEPTH:
		var children: Array = []
		for node: Dictionary in beam:
			if node.end: continue
			var options: Array = []
			for act: Dictionary in acts:
				# An enemy hero moves on: it is met now or not planned for.
				if node.done.has(act.key) or (depth > 0 and act.kind == "hero"): continue
				var open := true
				for guard: int in act.blockers: if not node.cleared.has(guard): open = false
				if not open: continue
				var bound := _bound_from(node.stand, act.area) * per_tile / day
				options.append([act.gain - TURN * bound, act.key, act])
			options.sort_custom(func(a: Array, b: Array): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
			if depth > 0: options = options.slice(0, LOOK_BRANCH)
			for option: Array in options:
				var act: Dictionary = option[2]
				var leg: Array = [act.walk, act.stand] if depth == 0 else _leg(director, node.stand, act.area, per_tile, node.cleared)
				var walk: float = leg[0]
				if walk < 0.0: continue
				var days := walk / day
				if depth > 0 and (node.days + days > LOOK_DAYS or (act.site and role == 0 and walk > day)): continue
				var step: float = pow(LOOK_DISCOUNT, depth) * float(node.alive) * (float(act.gain) - TURN * days)
				# A sequence stops rather than take a step that loses worth.
				if depth > 0 and step <= 0.0: continue
				var done: Dictionary = node.done.duplicate()
				done[act.key] = true
				var cleared: Dictionary = node.cleared
				if act.kind == "monster":
					cleared = cleared.duplicate()
					cleared[int(act.target)] = true
				# The hero stands where the route ended, or (for an estimated
				# leg) on the open cell beside the target nearest where it was.
				var stand: Vector2i = leg[1] if leg[1].x >= 0 else _stand(director, act.area, node.stand)
				var child := {"stand": stand, "days": float(node.days) + days, "value": float(node.value) + step, "alive": float(node.alive) * float(act.chance),
					"done": done, "cleared": cleared, "first": act.key if depth == 0 else node.first, "end": act.end}
				children.append(child)
				if child.value > float(best.get(child.first, -INF)): best[child.first] = child.value
		children.sort_custom(func(a: Dictionary, b: Dictionary): return a.value > b.value if a.value != b.value else a.first < b.first)
		var counts := {}
		beam = []
		for child: Dictionary in children:
			var count := int(counts.get(child.first, 0))
			if count >= LOOK_BEAM: continue
			counts[child.first] = count + 1
			beam.append(child)
		if beam.is_empty(): break
	var single := ""
	for key: String in row:
		if single.is_empty() or float(row[key]) > float(row[single]): single = key
	var first := ""
	for key: String in best:
		if first.is_empty() or float(best[key]) > float(best[first]): first = key
	if first.is_empty() or first == single or not best.has(single) or float(best[first]) <= float(best[single]) + LOOK_MARGIN: return
	row[first] = float(row[single]) + float(best[first]) - float(best[single])

## A reachable shop gets credit for opening the route after its purchase.
## Limit speculative shopping to two safe shops for the strongest blockage.
static func _add_matchup_shop(director: ELAdventureDirector, hero: Dictionary, guard: Dictionary, value: float, pool: Array, others: Dictionary, retry: Dictionary, row: Dictionary, columns: Dictionary) -> void:
	var state := director.state
	var player := int(hero.owner)
	var day := maxf(1.0, float(hero.strategy_capacity))
	var uid := int(hero.uid)
	var nearby: Array = []
	for task: Dictionary in pool:
		if task.kind != "shop" or not ELFirstAI._available(task, hero, others, retry): continue
		var item := state.object(task.target)
		var bound := _lower_bound(hero, _area(director, item))
		if bound <= LOOK_DAYS * day: nearby.append([bound, int(item.uid), item])
	nearby.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var reachable := 0
	for entry: Array in nearby.slice(0, 6):
		var shop: Dictionary = entry[2]
		var walk := ELFirstAI._route_cost(director, hero, shop, true, true)
		if walk == ELFirstAI.NONE or float(walk) > LOOK_DAYS * day: continue
		reachable += 1
		ELFirstAI.note_stat(director, player, "reachable_matchup_shop")
		var purchase := ELFirstAIEconomy.matchup_purchase(director, hero, shop, guard)
		if not purchase.is_empty():
			var task := {"kind": "shop", "target": int(shop.uid), "guard": int(guard.uid)}
			var key := ELFirstAI._key(task, uid)
			# The columns are shared between heroes. Keep the selected guard on
			# this hero's choice when the matching awards the ordinary shop.
			var plans: Dictionary = _matchup_shops.get_or_add(uid, {})
			plans[key] = task
			row[key] = maxf(float(row.get(key, -INF)), 16.0 + 0.8 * value - TURN * float(walk) / day)
			columns[key] = {"kind": "shop", "target": int(shop.uid)}
		if reachable >= 2: break
	if reachable == 0: ELFirstAI.note_stat(director, player, "no_reachable_matchup_shop")

## One action of the lookahead from a shortlisted objective: its worth before
## walking (utility() plus the walk it subtracted), its risk, where it is and
## where its route ends (`stand`).
static func _act(director: ELAdventureDirector, hero: Dictionary, task: Dictionary, key: String, points: float, walk: float, stand: Vector2i) -> Dictionary:
	if walk < 0.0 or points == -INF: return {}
	var state := director.state
	var day := maxf(1.0, float(hero.get("strategy_capacity", 1)))
	var item := state.object(task.get("target", -1))
	var area := Rect2i(Vector2i(int(task.tile[0]), int(task.tile[1])), Vector2i.ONE) if task.kind == "explore" else _area(director, item)
	var chance := 1.0
	if task.kind in ["monster", "hero"]: chance = win_chance(director, hero, item)
	elif task.kind == "building" and ELAdditionalBuildings.DUNGEONS.has(item.get("name")):
		chance = win_chance(director, hero, state.object(item.monster))
	# Sieges, enemy heroes, exploration and escorts end a sequence: what
	# follows them cannot be foreseen.
	return {"key": key, "kind": task.kind, "target": int(task.get("target", -1)), "area": area, "gain": points + TURN * walk / day, "chance": chance, "blockers": [] as Array[int], "walk": walk,
		"end": task.kind in ["tower", "hero", "explore", "escort"], "site": task.kind in ["mine", "node", "cut"], "stand": stand}

## The open cell beside `area` nearest `toward`: where a hero stands after an action there.
static func _stand(director: ELAdventureDirector, area: Rect2i, toward: Vector2i) -> Vector2i:
	var grid := director.grid
	var best := Vector2i(-1, -1)
	for y in range(area.position.y - 1, area.end.y + 1):
		for x in range(area.position.x - 1, area.end.x + 1):
			var point := Vector2i(x, y)
			if area.has_point(point) or not grid.contains(point) or grid.land.is_point_solid(point): continue
			if grid.naval and ELFirstNaval.is_water(grid.map, point) != ELFirstNaval.is_water(grid.map, area.position): continue
			if best.x < 0 or point.distance_squared_to(toward) < best.distance_squared_to(toward): best = point
	return best if best.x >= 0 else area.position

## Opens the cells the creatures `ids` stand on (as if they were beaten) in
## the land graph; returns what _close_bodies needs to restore them. The
## creatures must stand on explored ground (the pass keeps the rest closed).
static func _open_bodies(director: ELAdventureDirector, ids: Array) -> Array:
	var grid := director.grid
	var opened: Array = []
	for id: Variant in ids:
		var body := director.state.object(int(id))
		var at := Vector2i(int(body.get("x", -1)), int(body.get("y", -1)))
		if not grid.contains(at): continue
		var index := at.y * grid.map.width + at.x
		if grid.actor_blockers[index] <= 0: continue
		opened.append([at, grid.actor_blockers[index]])
		grid.actor_blockers[index] = 0
		grid._update_cell(at)
	return opened

static func _close_bodies(director: ELAdventureDirector, opened: Array) -> void:
	var grid := director.grid
	for entry: Array in opened:
		grid.actor_blockers[entry[0].y * grid.map.width + entry[0].x] = entry[1]
		grid._update_cell(entry[0])

## Lower bound of the walk from a tile to beside `area`, in tiles.
static func _bound_from(from: Vector2i, area: Rect2i) -> float:
	var dx := maxi(0, maxi(area.position.x - from.x, from.x - (area.end.x - 1)))
	var dy := maxi(0, maxi(area.position.y - from.y, from.y - (area.end.y - 1)))
	return float(maxi(0, maxi(dx, dy) - 1))

## Movement cost from `from` to beside `area` and the cell the route ends on:
## [cost (-1: no way), cell (-1, -1 when estimated)]. A route search while the
## pass's LOOK_LEGS last (toward the two nearest open cells, then the others
## in order), an estimate after. The creatures of `cleared` are gone, so the
## cells they stood on are open.
static func _leg(director: ELAdventureDirector, from: Vector2i, area: Rect2i, per_tile: float, cleared: Dictionary = {}) -> Array:
	var gone: Array = cleared.keys()
	gone.sort()
	var key := "%d,%d>%d,%d|%s" % [from.x, from.y, area.position.x, area.position.y, str(gone)]
	if _leg_cache.has(key): return _leg_cache[key]
	var bound := _bound_from(from, area)
	var result: Array = [bound * per_tile, Vector2i(-1, -1)]
	if bound <= 0.0: result = [0.0, from]
	elif _legs < LOOK_LEGS:
		_legs += 1
		var grid := director.grid
		var opened := _open_bodies(director, gone)
		var cells: Array[Vector2i] = []
		for y in range(area.position.y - 1, area.end.y + 1):
			for x in range(area.position.x - 1, area.end.x + 1):
				var point := Vector2i(x, y)
				if not area.has_point(point) and grid.contains(point) and not grid.land.is_point_solid(point):
					if not grid.naval or ELFirstNaval.is_water(grid.map, point) == ELFirstNaval.is_water(grid.map, area.position): cells.append(point)
		cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(from) < b.distance_squared_to(from) if a.distance_squared_to(from) != b.distance_squared_to(from) else (a.y < b.y if a.y != b.y else a.x < b.x))
		result = [-1.0, Vector2i(-1, -1)]
		for point: Vector2i in cells:
			var path := grid.path(from, point)
			if not path.is_empty():
				result = [float(grid.path_cost(path)), point]
				break
		_close_bodies(director, opened)
	_leg_cache[key] = result
	return result

# --- Living world ----------------------------------------------------------------

## The remake switch (off by default) for living-world behaviour of computer
## players: patrols, raids, escorts, retreats to resupply and faction
## doctrines. Neutral creatures keep their places: their guard areas are
## fixed by the map in the first game, so they never drift.
static func living(director: ELAdventureDirector) -> bool:
	return director.living_world and ELFirstAIEconomy.applies(director)

## A player whose castle the chapter names as one that must fall or stand.
static func story_player(state: ELAdventureSession, player: int) -> bool:
	for id: String in ELFirstScenario.CASTLE_GOALS:
		if state.map.id.contains(id):
			var goals: Dictionary = ELFirstScenario.CASTLE_GOALS[id]
			return goals.win.has(player) or goals.lose.has(player)
	return false

## Story-critical actors keep the plain planning: heroes of a player the
## chapter names, the chapters' scripted heroes and goals, quest heroes, the
## map's own heroes in campaign chapters, and any hero a queued script command
## names.
static func story_actor(state: ELAdventureSession, hero: Dictionary) -> bool:
	var key := "story:%d" % int(hero.get("uid", -1))
	if _living_cache is Dictionary and _living_cache.has(key): return _living_cache[key]
	var result := _story_actor(state, hero)
	if _living_cache is Dictionary: _living_cache[key] = result
	return result

static func _story_actor(state: ELAdventureSession, hero: Dictionary) -> bool:
	if story_player(state, player_of(hero)): return true
	var name := str(hero.get("name", ""))
	if ELFirstAI.MISSION23_TARGETS.has(name) or ELFirstAI.MISSION23_HUNTERS.has(name) or name == "Gunnilda" or name.contains("Beta-700") or name.contains("Gamma-400") or name.contains("Delta-500"): return true
	if ELFirstScenario.BATTLE_GOALS.values().has(name): return true
	if str(state.map.profile.table("HeroTemplates").get(name, {}).get("Quest", "")) == "Yes": return true
	if bool(state.scenario.get("campaign", false)) and int(hero.get("source_index", -1)) >= 0: return true
	for command: Dictionary in state.commands:
		for value: Variant in command.get("arguments", []):
			if (value is int or value is float) and int(value) == int(hero.get("uid", -1)): return true
	return false

## The player's doctrine: a map's "doctrine" player attribute when it names
## one, otherwise chosen once, on first need, from the session's random
## numbers then, the player and its colour, and kept with the player's plans
## (ELFirstAI.data), so later random events never change it (none for story
## players). A save from before has none kept and chooses on load.
static func doctrine(state: ELAdventureSession, player: int) -> String:
	if story_player(state, player): return ""
	for entry: Dictionary in state.map.players:
		if int(entry.get("attrs", {}).get("id", -1)) == player and DOCTRINES.has(str(entry.attrs.get("doctrine", ""))): return str(entry.attrs.doctrine)
	if not state.players.has(player): return ""
	var ai := ELFirstAI.data(state, player)
	if not DOCTRINES.has(str(ai.get("doctrine", ""))):
		ai.doctrine = DOCTRINE_NAMES[hash([int(state.seed_value), player, str(state.players[player].get("color", "")), state.map.id]) % DOCTRINE_NAMES.size()]
	return str(ai.doctrine)

static func _doctrine_table(director: ELAdventureDirector, player: int) -> Dictionary:
	if not living(director): return {}
	var key := "doctrine:%d" % player
	if _living_cache is Dictionary and _living_cache.has(key): return _living_cache[key]
	var table: Dictionary = DOCTRINES.get(doctrine(director.state, player), {})
	if _living_cache is Dictionary: _living_cache[key] = table
	return table

## The doctrine's weight of `kind` for this hero's player (1 without the switch).
static func weight(director: ELAdventureDirector, hero: Dictionary, kind: String) -> float:
	if not living(director) or story_actor(director.state, hero): return 1.0
	return float(_doctrine_table(director, player_of(hero)).get(kind, 1.0))

## An enemy site no hero of its owner that the player sees stands within a day of.
static func undefended(director: ELAdventureDirector, player: int, site: Dictionary) -> bool:
	var key := "site:%d:%d" % [player, int(site.get("uid", -1))]
	if _living_cache is Dictionary and _living_cache.has(key): return _living_cache[key]
	var result := _undefended(director, player, site)
	if _living_cache is Dictionary: _living_cache[key] = result
	return result

static func _undefended(director: ELAdventureDirector, player: int, site: Dictionary) -> bool:
	var state := director.state
	var area := _area(director, site)
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or not item.get("alive", false) or int(item.get("owner", -1)) != int(site.get("owner", -1)): continue
		if ELFirstAI.observed(state, player, item) and _lower_bound(item, area) <= maxf(1.0, float(item.get("strategy_capacity", 1))): return false
	return true

## Runes running low: the share of runes left is under RETREAT_SHARE.
static func low_charges(state: ELAdventureSession, hero: Dictionary) -> bool:
	return not ELFirstAIEconomy.starting_book(hero) and ELFirstAIEconomy.rune_health(state, hero) < RETREAT_SHARE

## Escort objectives: the player's besiegers that are weak (below
## ESCORT_LEVEL, or facing a seen hero of the castle's owner near it that is
## likely to beat them).
static func escorts(director: ELAdventureDirector, player: int) -> Array:
	var state := director.state
	var result: Array = []
	for pair: Array in ELFirstAI.data(state, player).assigned:
		if pair[1].get("kind") != "tower": continue
		var hero := state.object(pair[0])
		var castle := state.object(pair[1].get("target", -1))
		if not hero.get("alive", false) or castle.is_empty() or story_actor(state, hero): continue
		var weak := int(hero.get("level", 1)) < ESCORT_LEVEL
		var area := _area(director, castle)
		for item: Dictionary in state.objects.values():
			if weak: break
			if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == int(castle.get("owner", -1)) and ELFirstAI.observed(state, player, item) and _lower_bound(item, area) <= THREAT_DAYS * maxf(1.0, float(item.get("strategy_capacity", 1))) and win_chance(director, hero, item) < 0.5: weak = true
		if weak: result.append({"kind": "escort", "target": int(hero.uid)})
	return result

## Patrols: a hero left without an objective walks a loop between its
## player's sites and castle, in order around the castle (the next stop
## after the one it stands beside, else the nearest).
static func patrols(director: ELAdventureDirector, player: int, heroes: Array[Dictionary], assigned: Dictionary) -> void:
	if not living(director): return
	var state := director.state
	var castle := ELFirstScenario.castle_object(state, player)
	var stops: Array[Dictionary] = []
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if item.get("group") in ["mines", "mana_nodes"] and item.get("alive", false) and int(item.get("owner", -1)) == player: stops.append(item)
	if not castle.is_empty(): stops.append(castle)
	if stops.size() < 2: return
	var middle := Vector2(int(castle.get("x", stops[0].x)), int(castle.get("y", stops[0].y)))
	stops.sort_custom(func(a: Dictionary, b: Dictionary):
		var first := (Vector2(int(a.x), int(a.y)) - middle).angle()
		var second := (Vector2(int(b.x), int(b.y)) - middle).angle()
		return first < second if first != second else int(a.uid) < int(b.uid))
	for hero: Dictionary in heroes:
		if assigned.has(int(hero.uid)) or ELGlobalSpells.held(hero) or story_actor(state, hero): continue
		var near := 0
		for index in stops.size():
			if _lower_bound(hero, _area(director, stops[index])) < _lower_bound(hero, _area(director, stops[near])): near = index
		var stop := stops[near]
		if ELStrategy.adjacent(director, hero, stop): stop = stops[(near + 1) % stops.size()]
		assigned[int(hero.uid)] = {"kind": "patrol", "target": int(stop.uid)}

# --- Knowledge -------------------------------------------------------------------

## Notes where the player sees enemy heroes now; old sightings fade. A
## sighting stays until it fades or the place is seen again (scouting), even
## when the hero has fallen out of sight: the player learns only what it sees.
static func observe(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var ai := ELFirstAI.data(state, player)
	var seen: Dictionary = ai.get("seen", {})
	for key: String in seen.keys():
		if int(state.day) - int(seen[key][2]) > SCOUT_DAYS: seen.erase(key)
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) >= 1 and int(item.owner) != player and ELFirstAI.observed(state, player, item):
			seen[str(item.uid)] = [int(item.x), int(item.y), int(state.day)]
	if seen.is_empty(): ai.erase("seen")
	else: ai.seen = seen

## A look at the place an enemy hero was last seen, while it is out of sight.
static func scouting(director: ELAdventureDirector, player: int) -> Array:
	var state := director.state
	var result: Array = []
	for key: String in ELFirstAI.data(state, player).get("seen", {}):
		var entry: Array = ELFirstAI.data(state, player).seen[key]
		var item := state.object(int(key))
		var tile := Vector2i(int(entry[0]), int(entry[1]))
		if ELFirstAI.observed(state, player, item) or ELFog.visible(state, player, tile) or director.grid.passability(tile) < 0: continue
		result.append({"kind": "explore", "target": -1, "tile": [tile.x, tile.y]})
	return result

## Exploration targets: the frontier tiles grouped in CLUSTER squares, one tile
## per group (the one nearest its group's middle), the groups with the most
## unexplored ground around them first; tiles inside a hostile guard area are
## left out.
static func exploration(director: ELAdventureDirector, player: int) -> Array:
	var state := director.state
	var groups := {}
	var tiles := ELFirstAI.frontier_tiles(director, player)
	for tile: Vector2i in tiles:
		var cell := Vector2i(tile.x / CLUSTER, tile.y / CLUSTER)
		if not groups.has(cell): groups[cell] = []
		groups[cell].append(tile)
	var picks: Array = []
	var guard := {"owner": player, "type": "hero", "alive": true}
	for cell: Vector2i in groups:
		var middle := Vector2(cell * CLUSTER) + Vector2.ONE * (CLUSTER / 2.0)
		var best := Vector2i(-1, -1)
		for tile: Vector2i in groups[cell]:
			if not director.interception.enemies(state, guard, tile).is_empty(): continue
			if best.x < 0 or Vector2(tile).distance_squared_to(middle) < Vector2(best).distance_squared_to(middle): best = tile
		if best.x >= 0: picks.append([reveal(state, player, best), best])
	picks.sort_custom(func(a: Array, b: Array): return a[0] > b[0] if a[0] != b[0] else (a[1].y < b[1].y if a[1].y != b[1].y else a[1].x < b[1].x))
	var result: Array = []
	var listed := {}
	for pick: Array in picks.slice(0, EXPLORE_TILES):
		listed[pick[1]] = result.size()
		result.append({"kind": "explore", "target": -1, "tile": [pick[1].x, pick[1].y]})
	# The way to an enemy castle the player has not found yet: the frontier
	# tile nearest it (castles are known places; the route to one is not).
	for castle: Dictionary in _unfound_castles(state, player):
		var size: Vector2i = director.grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE)
		var middle := Vector2(int(castle.x), int(castle.y)) + Vector2(size) / 2.0
		var best := Vector2i(-1, -1)
		for tile: Vector2i in tiles:
			if best.x >= 0 and Vector2(tile).distance_squared_to(middle) >= Vector2(best).distance_squared_to(middle): continue
			if not director.interception.enemies(state, guard, tile).is_empty(): continue
			best = tile
		if best.x < 0: continue
		if listed.has(best): result[listed[best]].toward = int(castle.uid)
		else:
			listed[best] = result.size()
			result.append({"kind": "explore", "target": -1, "tile": [best.x, best.y], "toward": int(castle.uid)})
	return result

## Enemy castles (siege targets) whose place the player has not explored.
static func _unfound_castles(state: ELAdventureSession, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not ELFog.active(state, player) or state.explored.size() != state.map.width * state.map.height: return result
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if not ELFirstScenario.is_castle(item) or int(item.get("owner", -1)) < 1 or int(item.owner) == player or not item.get("placed", true): continue
		if not ELFirstScenario.alive(state, int(item.owner)) or not state.hostile({"owner": player}, item): continue
		if not ELFog.explored(state, player, Vector2i(int(item.x), int(item.y))): result.append(item)
	return result

## Whether `hero` in `role` would besiege a castle (the level rules of a siege).
static func siege_ready(hero: Dictionary, role: int, map: ELAdventureMap = null) -> bool:
	var level := int(hero.get("level", 1))
	if role != 0: return level >= 8
	if level >= 6: return true
	# Generated worlds offer a level-five recruit. It can lead the attack
	# when its damage can overcome the target's restoration.
	return level == 5 and map != null and int(map.get_meta("random_map", {}).get("version", 0)) >= ELFirstRandomMapV2.WILDERNESS_VERSION

## Unexplored tiles within REVEAL_RADIUS of `tile`.
static func reveal(state: ELAdventureSession, player: int, tile: Vector2i) -> float:
	if not ELFog.active(state, player) or state.explored.size() != state.map.width * state.map.height: return 0.0
	var mask := ELFog.bit(player)
	var count := 0
	for y in range(maxi(0, tile.y - REVEAL_RADIUS), mini(state.map.height, tile.y + REVEAL_RADIUS + 1)):
		for x in range(maxi(0, tile.x - REVEAL_RADIUS), mini(state.map.width, tile.x + REVEAL_RADIUS + 1)):
			if state.explored[y * state.map.width + x] & mask == 0: count += 1
	return float(count)

# --- Battles -------------------------------------------------------------------

## The chance that `hero`, setting out to fight `enemy`, beats it, by the rule
## that will decide the battle and in the order the battle is queued: an
## enemy that guards an area (a creature, a fort's garrison, a hero under a
## fortification spell) stops the hero as it enters and is the first side
## (ELStrategy.entered); any other enemy is attacked, the hero first
## (ELStrategy.after_movement).
static func win_chance(director: ELAdventureDirector, hero: Dictionary, enemy: Dictionary) -> float:
	if director.interception.zones.has(int(enemy.get("uid", -1))): return 1.0 - first_wins(director, enemy, hero)
	return first_wins(director, hero, enemy)

## The chance that `first`, the first side of a queued battle, beats `second`
## The strength estimate prices actual duels and the optional estimated
## resolver. The original rule prices other off-screen encounters.
static func first_wins(director: ELAdventureDirector, first: Dictionary, second: Dictionary) -> float:
	var state := director.state
	for side: Dictionary in [first, second]:
		if int(side.get("owner", 0)) >= 1 and director.is_strategy_human(int(side.owner)): return estimate(state, first, second)
	if director.battle_estimate or ELFirstAI.plays_monster_duel(director, first, second): return estimate(state, first, second)
	# A player's hero always beats a neutral side.
	if int(second.get("owner", 0)) <= 0: return 1.0
	if int(first.get("owner", 0)) <= 0: return 0.0
	var level := int(first.get("level", 1))
	return float(level + 1) / float(level + int(second.get("level", 1)) + 1)

static var _strengths := {}

## The chance that `first` (the side that moves first) beats `second`, from
## both sides' health, level, usable spells (rated as in ELFirstSpellRatings),
## skills, specialization and battle artifacts. The first move is worth a
## little, as in the original rule.
static func estimate(state: ELAdventureSession, first: Dictionary, second: Dictionary) -> float:
	var difference := strength(state, first) - strength(state, second)
	return 1.0 / (1.0 + exp(-(difference / 10.0 + 0.4)))

static func strength(state: ELAdventureSession, unit: Dictionary) -> float:
	var cards: Array = unit.get("cards", [])
	var uses: Array = unit.get("rune_uses", [])
	var key := "%d|%d|%d|%d|%d|%d|%d|%s" % [int(unit.get("uid", -1)), state.combat_level(unit), state.combat_health(unit), hash(cards), hash(uses), hash(unit.get("skills", {})), unit.get("artifacts", []).size(), str(unit.get("specialization", "NONE"))]
	if _strengths.has(key): return _strengths[key]
	var profile := state.map.profile
	var book := 0.0
	for slot in cards.size():
		var live := slot >= uses.size() or int(uses[slot]) != 0
		if live: book += maxf(0.0, ELFirstAIEconomy.spell_value(profile, str(cards[slot])))
	var skills := 0
	for code: Variant in unit.get("skills", {}): skills += int(unit.skills[code]) + 1
	var value: float = float(state.combat_health(unit)) + 2.0 * state.combat_level(unit) + 0.8 * book + 2.0 * skills + 3.0 * unit.get("artifacts", []).size()
	if str(unit.get("specialization", "NONE")) not in ["NONE", ""]: value += 3.0
	if _strengths.size() > 4096: _strengths.clear()
	_strengths[key] = value
	return value
