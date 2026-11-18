extends SceneTree
## Headless check of the strategic computer players: small situations built
## on a cleared first-game map (open grass, the authored castles, objects
## copied from the map's own) and, for movement and fog, a second-game map.
## Each case names the planning or movement rule it guards.
##
##   godot --headless --path game --script ../tools/first_ai_check.gd -- [--smart=both|true|false] [--only=<case>]
##
## It needs the games' files (user://profiles.json, as set up by the game);
## without them the cases are skipped. Nothing is saved.

const MAP := "mmission01"
## Open ground: terrain kind 4 costs two points a tile, kind 17 is impassable.
const GRASS := 4
const WALL := 17

var failures: Array[String] = []
var profile: ELProfile
var protos := {}
var smart := false
var only := ""

## Checks run and parts skipped (no game files), for the totals: a run that
## skipped everything still exits 0, so CI without the games passes, but
## says so instead of passing quietly.
var checks := 0
var skipped := 0

func check(ok: bool, what: String) -> void:
	var label := "[smart=%s] %s" % [smart, what]
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures.append(label)

func _skip(reason: String) -> void:
	skipped += 1
	print("SKIP: " + reason)

func _finish() -> void:
	print("FIRST AI: %d check(s) run, %d part(s) skipped" % [checks, skipped])
	if checks == 0: print("FIRST AI: SKIPPED (no case ran)")
	print("FIRST AI: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.trim_prefix("--%s=" % name)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		_skip("no first-game files configured (user://profiles.json)")
		_finish()
		return
	profile = ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		_skip("the first game's files could not be mounted")
		_finish()
		return
	only = _arg("only", "")
	var modes: Array[bool] = [false, true]
	match _arg("smart", "both"):
		"true": modes = [true]
		"false": modes = [false]
	for mode: bool in modes:
		smart = mode
		for case: String in CASES:
			if not only.is_empty() and not case.begins_with(only): continue
			call("_case_" + case)
	if paths.has("el2") and (only.is_empty() or only.begins_with("g") or only.begins_with("i")):
		var second := ELProfile.new()
		if second.mount("el2", str(paths.el2)):
			smart = false
			_second_cases(second)
		else: _skip("the second game's files could not be mounted")
	elif not paths.has("el2"): _skip("no second-game files configured: its cases are not run")
	_finish()

const CASES := ["a_castle", "a_mine", "b_teacher", "b_gnome", "b_spawn", "c_blocked", "c_alternative", "c_spent", "d_unexplored", "d_guarded",
	"e_unseen", "e_unreachable", "f_upgrade", "f_refill", "f_portal", "h_meteor", "j_free", "k_holds", "k_defend", "m_roles", "n_joint", "p_resolver", "p_monsters", "p_committed_duel", "p_approach", "p_matchup_shop", "q_lookahead",
	"s_saved", "t_patrol", "t_raid", "t_escort", "t_retreat", "t_doctrine", "t_story", "t_off",
	"v_cast", "v_income", "v_runes", "v_portal", "v_upkeep", "v_mine",
	"w_pickup", "w_commander", "w_promotion", "w_hidden", "w_pile", "w_peace", "w_scouts", "w_tinkerer", "w_siege", "w_scrolls", "w_unfound", "w_human",
	"x_arrival", "x_placed", "x_chase", "x_sight", "x_rounds",
	"y_garrison", "y_reopen", "y_idle", "y_siege", "y_atomic", "y_order", "y_urgent", "y_turns", "y_stock", "y_restore", "y_strength", "y_sightings",
	"y_loop", "y_impending", "y_route", "y_bounds", "y_widen", "y_body", "y_leg", "y_resolver", "y_mark", "y_buffs", "y_summon", "y_combats", "y_hire"]

# --- World -------------------------------------------------------------------

## The map with open grass everywhere, its castles and one copy of each kind
## of object the cases use; every other object is removed.
func _world(free := false) -> ELAdventureDirector:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, MAP): return null
	map.terrain.fill(GRASS)
	map.roads.fill(0)
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false): return null
	protos = {}
	var kept := {}
	for id: int in state.objects.keys():
		var item := state.object(id)
		if ELFirstScenario.is_castle(item):
			kept[id] = item
			continue
		var kind := ""
		if item.type == "monster" and int(item.owner) <= 0: kind = "monster"
		elif item.get("group") == "mines": kind = "mine"
		elif item.get("group") == "mana_nodes": kind = "node"
		elif item.get("type") == "el1_spell_shop": kind = "shop"
		elif item.get("type") == "rune_shop": kind = "portal"
		elif item.get("group") == "additional_buildings" and item.name in ["Teacher", "GnomeMerchant"]: kind = item.name
		if not kind.is_empty() and not protos.has(kind): protos[kind] = item.duplicate(true)
		if kind == "shop": protos.get_or_add("shops", []).append(item.duplicate(true))
		if kind == "portal": protos.get_or_add("portals", []).append(item.duplicate(true))
	state.objects = kept
	var director := ELAdventureDirector.new()
	if not director.build(state): return null
	director.smart_ai = smart
	director.free_movement = free
	# Switches a case may turn on; every case starts from the defaults.
	if "living_world" in director: director.set("living_world", false)
	_planner_set("lookahead", true)
	director.fast_mode = true
	state.explored.fill(0xff)
	ELFog.refresh(state)
	return director

## A copy of a prototype object at (x, y).
func _place(director: ELAdventureDirector, kind: String, x: int, y: int, extra := {}) -> Dictionary:
	var state := director.state
	var item: Dictionary = protos[kind].duplicate(true) if protos.get(kind) is Dictionary else kind_item(kind)
	item.uid = state._next_object
	state._next_object += 1
	item.x = x
	item.y = y
	item.merge(extra, true)
	state.objects[int(item.uid)] = item
	state.event.emit({"kind": "object_created", "id": item.uid})
	return item

func kind_item(_kind: String) -> Dictionary:
	return {}

## A hero of `player` at (x, y) raised to `level`.
func _hero(director: ELAdventureDirector, player: int, x: int, y: int, level := 1) -> Dictionary:
	var state := director.state
	var colour := str(state.players[player].color)
	var rows: Dictionary = profile.table("HeroTemplates")
	var template := ""
	for key: String in rows:
		if str(rows[key].get("Quest", "")) != "Yes" and int(rows[key].get("Level", 1)) == 1 and str(rows[key].get("Color", "")) == colour:
			template = key
			break
	var id := ELAdditionalBuildings.spawn_hero(state, template, player, x, y)
	if level > 1: state.add_experience(id, ELHeroProgression.threshold(profile, level))
	var hero := state.object(id)
	hero.ap = int(hero.strategy_capacity)
	return hero

func _kill(director: ELAdventureDirector, item: Dictionary) -> void:
	item.alive = false
	director.state.event.emit({"kind": "object_killed", "id": item.uid})

## Impassable terrain on `cell` (its four terrain corners).
func _wall(director: ELAdventureDirector, cell: Vector2i, open := false) -> void:
	var map := director.state.map
	for corner: Vector2i in [cell, cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(1, 1)]:
		map.terrain[corner.y * (map.width + 1) + corner.x] = GRASS if open else WALL
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if director.grid.contains(cell + Vector2i(dx, dy)): director.grid._update_cell(cell + Vector2i(dx, dy))

## A square ring of walls `radius` cells around `item`'s footprint, leaving
## the cells of `gaps` (and their neighbours along the ring) open.
func _pen(director: ELAdventureDirector, item: Dictionary, radius: int, gaps: Array = []) -> void:
	var size: Vector2i = director.grid.footprints.get(int(item.uid), {}).get("size", Vector2i.ONE)
	var area := Rect2i(int(item.x) - radius, int(item.y) - radius, size.x + 2 * radius, size.y + 2 * radius)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if x != area.position.x and x != area.end.x - 1 and y != area.position.y and y != area.end.y - 1: continue
			var open := false
			for gap: Vector2i in gaps:
				if maxi(absi(gap.x - x), absi(gap.y - y)) <= 1: open = true
			if not open: _wall(director, Vector2i(x, y))

func _unexplore(director: ELAdventureDirector, player: int, area: Rect2i) -> void:
	var state := director.state
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			state.explored[y * state.map.width + x] &= ~ELFog.bit(player)

func _pass(director: ELAdventureDirector, player := 2) -> void:
	ELFirstAI.plan_player(director, player, false)

func _task_of(director: ELAdventureDirector, hero: Dictionary, player := 2) -> Dictionary:
	for pair: Array in ELFirstAI.data(director.state, player).assigned:
		if int(pair[0]) == int(hero.uid): return pair[1]
	return {}

## Whether an objective on `target` is still known: open or held by a hero.
func _known(director: ELAdventureDirector, target: Dictionary, player := 2) -> bool:
	var ai := ELFirstAI.data(director.state, player)
	for task: Dictionary in ai.tasks:
		if int(task.get("target", -1)) == int(target.uid): return true
	for pair: Array in ai.assigned:
		if int(pair[1].get("target", -1)) == int(target.uid) and director.state.object(pair[0]).get("alive", false): return true
	return false

func _castle(director: ELAdventureDirector, player: int) -> Dictionary:
	return ELFirstScenario.castle_object(director.state, player)

## The planner script, called by name so that this file also loads where a
## switch is missing (null then).
func _planner() -> Script:
	return load("res://src/content/first_ai_planner.gd") if ResourceLoader.exists("res://src/content/first_ai_planner.gd") else null

func _planner_set(name: String, value: Variant) -> void:
	var planner := _planner()
	if planner != null and name in planner: planner.set(name, value)

## The living-world switch; false where it is missing.
func _living(director: ELAdventureDirector, on: bool) -> bool:
	if not "living_world" in director: return false
	director.set("living_world", on)
	return true
# --- A: objectives survive their hero ----------------------------------------

func _case_a_castle() -> void:
	var director := _world()
	var home := _castle(director, 2)
	var first := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var second := _hero(director, 2, int(home.x) - 8, int(home.y) + 4, 6)
	_pass(director)
	var task := _task_of(director, first)
	check(task.get("kind") == "tower", "A: the leading hero sets out to besiege an enemy castle")
	var castle := director.state.object(int(task.get("target", -1)))
	_kill(director, first)
	_pass(director)
	_pass(director)
	check(_known(director, castle), "A: the castle its fallen hero was besieging is still an objective")
	check(_task_of(director, second).get("kind") == "tower", "A: the new leading hero takes up a siege")

func _case_a_mine() -> void:
	var director := _world()
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 40, 90, 2)
	var mine := _place(director, "mine", 46, 92, {"owner": -1})
	var far := _hero(director, 2, 20, 100, 2)
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "A: the nearest supporter is sent to the mine")
	_kill(director, side)
	_pass(director)
	check(_known(director, mine), "A: the mine its fallen hero was sent to is still an objective")
	check(int(_task_of(director, far).get("target", -1)) == int(mine.uid), "A: another supporter takes over the mine")
	check(not lead.is_empty(), "A: the leader stays")

# --- B: reusable buildings and new targets ----------------------------------

func _case_b_teacher() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var first := _hero(director, 2, 40, 90, 2)
	var teacher := _place(director, "Teacher", 44, 90)
	var second := _hero(director, 2, 20, 60, 2)
	_pass(director)
	check(int(_task_of(director, first).get("target", -1)) == int(teacher.uid), "B: the nearest hero goes to the Teacher")
	teacher.visited.append(int(first.uid))
	_pass(director)
	check(_known(director, teacher), "B: a Teacher another hero may still use stays an objective")
	check(int(_task_of(director, second).get("target", -1)) == int(teacher.uid), "B: the second hero goes to the Teacher")

func _case_b_gnome() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var first := _hero(director, 2, 40, 90, 2)
	var gnome := _place(director, "GnomeMerchant", 44, 90)
	_pass(director)
	check(int(_task_of(director, first).get("target", -1)) == int(gnome.uid), "B: a hero goes to the Gnome Merchant")
	gnome.used = true
	_pass(director)
	ELAdditionalBuildings.new_day(director.state, 7)
	_pass(director)
	check(_known(director, gnome), "B: the Gnome Merchant is an objective again after its weekly reset")

func _case_b_spawn() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	_hero(director, 2, 40, 90, 2)
	_pass(director)
	var monster := _place(director, "monster", 50, 96, {"owner": 0})
	_pass(director)
	check(_known(director, monster), "B: a creature that appears later becomes an objective")

# --- C: blocked assignments ---------------------------------------------------

func _case_c_blocked() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 2)
	var mine := _place(director, "mine", 50, 90, {"owner": -1})
	var gap := Vector2i(int(mine.x) - 4, int(mine.y))
	_pen(director, mine, 4, [gap])
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "C: the supporter is sent to the mine through the gap")
	_wall(director, gap)
	var stuck := 0
	for round in 4:
		_pass(director)
		var task := _task_of(director, side)
		if int(task.get("target", -1)) == int(mine.uid) and side.get("strategy_order", {}).is_empty(): stuck += 1
	check(stuck < 3, "C: an assignment that produces no order is given up after a few passes (stuck %d of 4)" % stuck)
	_wall(director, gap, true)
	_wall(director, gap + Vector2i(0, -1), true)
	_wall(director, gap + Vector2i(0, 1), true)
	for round in 4: _pass(director)
	check(_known(director, mine), "C: the mine is an objective again once the way opens")

func _case_c_alternative() -> void:
	if not smart: return
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var hero := _hero(director, 2, 30, 90, 2)
	var blocked := _place(director, "mine", 50, 90, {"owner": -1})
	var gap := Vector2i(int(blocked.x) - 4, int(blocked.y))
	_pen(director, blocked, 4, [gap])
	_pass(director)
	check(int(_task_of(director, hero).get("target", -1)) == int(blocked.uid), "C: the hero has an errand before the passage closes")
	for offset in range(-1, 2): _wall(director, gap + Vector2i(0, offset))
	var open := _place(director, "mine", 34, 90, {"owner": -1})
	_pass(director)
	check(int(_task_of(director, hero).get("target", -1)) == int(open.uid), "C: the hero takes the reachable mine on the first pass after the route closes")

func _case_c_spent() -> void:
	if not smart: return
	var director := _world(true)
	var spent := _hero(director, 2, 30, 90, 2)
	spent.ap = 0
	var ready := _hero(director, 2, 53, 90)
	var mine := _place(director, "mine", 31, 90, {"owner": -1})
	_pass(director)
	check(spent.strategy_order.is_empty(), "C: a hero with no movement does not reserve the adjacent mine")
	check(int(_task_of(director, ready).get("target", -1)) == int(mine.uid), "C: the hero with movement takes the mine assignment")

# --- D: the executed route keeps the planned route's rules ------------------

## A wall down column `x` from `top` to `bottom`, with a one-cell passage
## at each row of `gaps`.
func _wall_line(director: ELAdventureDirector, x: int, top: int, bottom: int, gaps: Array) -> void:
	for y in range(top, bottom + 1):
		var open := false
		for gap: int in gaps:
			if absi(gap - y) <= 1: open = true
		if not open: _wall(director, Vector2i(x, y))

func _case_d_unexplored() -> void:
	# The leader (below siege level) hunts a creature beyond a wall: the near
	# passage is unexplored, the far one explored.
	var director := _world()
	var lead := _hero(director, 2, 30, 60, 5)
	var prey := _place(director, "monster", 52, 60, {"owner": 0, "level": 1})
	_wall_line(director, 40, 30, 100, [60, 76])
	_unexplore(director, 2, Rect2i(38, 56, 5, 9))
	_pass(director)
	# The smarter planner may weigh a look at the unexplored passage higher;
	# whatever it chose, the walk must keep to explored ground.
	if smart: check(not _task_of(director, lead).is_empty(), "D: the leader has an objective (%s)" % str(_task_of(director, lead)))
	else: check(int(_task_of(director, lead).get("target", -1)) == int(prey.uid), "D: the leader is sent after the creature")
	var path := ELStrategy.order_path(director, lead)
	var unknown := 0
	for point: Vector2i in path:
		if not ELFog.explored(director.state, 2, point): unknown += 1
	check(not path.is_empty() and unknown == 0, "D: the route walked keeps to explored ground (%d unexplored cells)" % unknown)

func _case_d_guarded() -> void:
	# A supporter goes for a mine beyond a wall: the near passage leads into a
	# creature's guard area, the far one is clear.
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 60, 2)
	var mine := _place(director, "mine", 52, 60, {"owner": -1})
	var guard := _place(director, "monster", 43, 60, {"owner": 0, "level": 9})
	_wall_line(director, 40, 30, 100, [60, 76])
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "D: the supporter is sent to the mine")
	var path := ELStrategy.order_path(director, side)
	var guarded := 0
	for point: Vector2i in path:
		if not director.interception.enemies(director.state, side, point).is_empty(): guarded += 1
	check(not path.is_empty() and guarded == 0, "D: the route walked keeps out of the guard's area like the planned one (%d guarded cells)" % guarded)
	check(guard.alive, "D: the guard stays")

# --- E: enemies the player does not see -------------------------------------

func _case_e_unseen() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	_hero(director, 2, 40, 90, 2)
	var enemy := _hero(director, 3, 20, 20, 1)
	_pass(director)
	check(not ELFog.visible(director.state, 2, Vector2i(enemy.x, enemy.y)), "E: the enemy hero stands out of sight")
	check(not _known(director, enemy), "E: an enemy hero out of sight is not a target")
	var scout := _hero(director, 2, 24, 22, 2)
	_pass(director)
	check(_known(director, enemy), "E: the same hero becomes a target once seen")
	check(not scout.is_empty(), "E: the scout stays")

func _case_e_unreachable() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	var enemy := _hero(director, 3, 38, 90, 1)
	_pen(director, enemy, 3)
	ELFog.refresh(director.state)
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(enemy.uid), "E: a supporter is not sent after an enemy it cannot reach")

# --- F: shops and portals ---------------------------------------------------

func _case_f_upgrade() -> void:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	for kind: String in state.players[2].resources: state.players[2].resources[kind] = 5000
	_place(director, "portal", 20, 80)
	var found := {}
	for proto: Dictionary in protos.get("shops", []):
		var shop := _place(director, "shop", 36, 90, {"name": proto.name, "node": proto.node, "level": 0, "owner": 0})
		# A book of the shop's own stock: nothing here is worth buying.
		var stock := ELFirstSpellShop.authored_stock(profile, shop, ELFirstSpellShop.hero_color(profile, side))
		if stock.is_empty(): continue
		for slot in side.cards.size(): side.cards[slot] = stock[slot % stock.size()]
		ELRunes.initialize(profile, side)
		for slot in side.rune_uses.size():
			if int(side.rune_uses[slot]) >= 0: side.rune_uses[slot] = ELRunes.capacity(side)
		if ELFirstAIEconomy._shop(state, side, shop, false) == 0 and int(ELFirstAIEconomy._next_stock_helps(state, side, shop)) > 0:
			found = shop
			break
		_kill(director, shop)
		state.objects.erase(int(shop.uid))
	if not smart:
		check(ELFirstAI.cost(director, side, 1, {"kind": "shop", "target": int(found.get("uid", -1))}) == ELFirstAI.NONE, "F: without the option shops are never visited")
		return
	check(not found.is_empty(), "F: a spell shop whose next level helps while its stock does not")
	if found.is_empty(): return
	check(ELFirstAI.cost(director, side, 1, {"kind": "shop", "target": int(found.uid)}) != ELFirstAI.NONE, "F: a visit that upgrades the shop and buys is planned")

func _case_f_refill() -> void:
	var director := _world()
	var state := director.state
	var side := _hero(director, 2, 30, 90, 3)
	var portal := _place(director, "portal", 32, 90)
	var slot := _rune_slot(side)
	check(slot >= 0, "F: the hero has a spell that uses runes")
	if slot < 0: return
	side.rune_uses[slot] = 0
	check(ELFirstAIEconomy.trip_cost(state, side, portal, 0, 1) >= 0, "F: one rune for an empty spell at an adjacent portal is worth the stop")
	check(ELFirstAIEconomy.trip_cost(state, side, portal, 40, 1) < 0, "F: one rune is not worth a long trip")

## A book slot holding a spell that uses runes (one of the hero's colour is
## put in the first slot when the book has none); -1 if there is none.
func _rune_slot(hero: Dictionary) -> int:
	for index in hero.rune_uses.size():
		if int(hero.rune_uses[index]) >= 0: return index
	var colour := ELFirstSpellShop.hero_color(profile, hero)
	var spells: Dictionary = profile.table("CombatSpells")
	for code: String in spells:
		if spells[code].get("Color") == colour and spells[code].get("Rarity") in ["Common", "Rare"]:
			hero.cards[0] = code
			ELRunes.initialize(profile, hero)
			for index in hero.rune_uses.size():
				if int(hero.rune_uses[index]) >= 0: return index
	return -1

func _case_f_portal() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var side := _hero(director, 2, 30, 90, 3)
	for kind: String in state.players[2].resources: state.players[2].resources[kind] = 5000
	var portal := _place(director, "portal", 60, 60)
	# A spell that waits for runes: the hero is drawn to a portal it can reach,
	# and its purchases are priced with that portal's runes.
	var slot := _rune_slot(side)
	check(slot >= 0, "F: the hero has a spell that uses runes")
	if slot < 0: return
	side.rune_uses[slot] = 0
	check(ELFirstAIEconomy.urgent(director, side), "F: an empty spell sends the hero to the portal it can reach")
	_pen(director, portal, 3)
	check(not ELFirstAIEconomy.urgent(director, side), "F: a portal that cannot be reached does not")

# --- H: offensive global spells ---------------------------------------------

func _case_h_meteor() -> void:
	var director := _world()
	var state := director.state
	var castles: Dictionary = state.scenario.castles
	for id: int in castles:
		if id != 2: castles[id].alive = false
	var record := ELGlobalSpells.data(state, 2)
	record.production = {"code": "METR", "state": 2, "cost": 10}
	var before := int(castles[2].pending)
	ELFirstAIEconomy._cast(director, 2)
	state.error = ""
	check(int(castles[2].pending) <= before, "H: a meteor with no enemy castle left does not strike its own castle (%d -> %d)" % [before, int(castles[2].pending)])

# --- J: free movement plans again after an action ---------------------------

func _case_j_free() -> void:
	var director := _world(true)
	var state := director.state
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	lead.ap = 0
	var side := _hero(director, 2, 40, 90, 2)
	var first := _place(director, "mine", 41, 91, {"owner": -1})
	var second := _place(director, "mine", 52, 91, {"owner": -1})
	var start := Vector2i(side.x, side.y)
	if not ELStrategy.free_mode(director):
		check(false, "J: free movement applies on this map")
		return
	# Only player 2 moves.
	director.free_queue = [{"kind": "ai", "player": 2, "round": 0, "pending": [], "planned": false, "positions": {}}]
	ELStrategy.free_next(director)
	for step in 20000:
		if not director.error.is_empty(): break
		if director.strategy.is_empty() and director.movement.is_empty() and director.free_queue.is_empty(): break
		if not director.strategy.is_empty() and director.strategy.get("free", "") == "night": break
		director.advance(0.1)
	check(int(first.owner) == 2, "J: the adjacent mine is taken")
	check(Vector2i(side.x, side.y) != start or int(second.owner) == 2, "J: with movement left the hero goes on to the next mine the same day")

# --- K, M, N: smarter computer players ----------------------------------------

## A raider near the castle; the castle's energy decides whether it holds.
func _k_world(energy: int) -> Array:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	if energy > 0: state.scenario.castles[2].health = energy
	var lead := _hero(director, 2, 20, 100, 8)
	var side := _hero(director, 2, int(home.x) - 8, int(home.y) + 2, 4)
	var mine := _place(director, "mine", int(home.x) - 14, int(home.y) + 6, {"owner": -1})
	var raider := _hero(director, 3, int(home.x) - 6, int(home.y) - 8, 5)
	ELFog.refresh(state)
	return [director, lead, side, mine, raider]

func _case_k_holds() -> void:
	# A castle at full energy outlasts one level-five raider for days: its
	# heroes stay on their tasks.
	var world := _k_world(0)
	var director: ELAdventureDirector = world[0]
	var side: Dictionary = world[2]
	var raider: Dictionary = world[4]
	_pass(director)
	var task := _task_of(director, side)
	var lead_task := _task_of(director, world[1])
	if smart:
		var planner := _planner()
		var holds: Dictionary = planner.call("defence", director, 2, planner.call("threats", director, 2)) if planner != null else {"x": 1}
		check(holds.is_empty(), "K: the castle at full energy holds on its own (%s)" % str(holds))
		check(int(task.get("target", -1)) == int(world[3].uid) and lead_task.get("kind") == "tower", "K: a castle that holds keeps its heroes on task (%s / %s)" % [str(lead_task), str(task)])
	else: check(task.get("kind") != "defend", "K: without the option no defence task is made")
	check(raider.alive, "K: the raider stays")

func _case_k_defend() -> void:
	# The same raider before a castle with little energy left: the castle
	# would fall within a night or two, so a hero that can reach the raider
	# in time is sent; the far leader stays at its siege.
	var world := _k_world(9)
	var director: ELAdventureDirector = world[0]
	var lead: Dictionary = world[1]
	var side: Dictionary = world[2]
	var raider: Dictionary = world[4]
	_pass(director)
	if not smart:
		check(_task_of(director, side).get("kind") != "defend", "K: without the option no defence task is made")
		return
	var planner := _planner()
	var falls: Dictionary = planner.call("defence", director, 2, planner.call("threats", director, 2)) if planner != null else {}
	check(falls.has(int(raider.uid)), "K: the castle with little energy would fall (%s)" % str(falls))
	var deadline := float(falls.get(int(raider.uid), 0.0))
	var defender := {}
	for hero: Dictionary in [lead, side]:
		if int(_task_of(director, hero).get("target", -1)) == int(raider.uid): defender = hero
	check(not defender.is_empty(), "K: a hero turns back to meet the raider (%s / %s)" % [str(_task_of(director, lead)), str(_task_of(director, side))])
	if defender.is_empty(): return
	var days := float(ELFirstAI._route_cost(director, defender, raider, false)) / maxf(1.0, float(defender.strategy_capacity))
	check(days <= deadline, "K: the defender arrives in time (%.1f days, the castle falls in %.0f)" % [days, deadline])
	var far := float(ELFirstAI._route_cost(director, lead, raider, false)) / maxf(1.0, float(lead.strategy_capacity))
	if far > deadline: check(_task_of(director, lead).get("kind") == "tower", "K: the leader, too far to arrive in time (%.1f days), keeps its siege" % far)
func _case_m_roles() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 9)
	var side := _hero(director, 2, 30, 90, 7)
	var weak := _place(director, "monster", 34, 90, {"owner": 0, "level": 1})
	_pass(director)
	var task := _task_of(director, side)
	if smart: check(int(task.get("target", -1)) == int(weak.uid), "M: a strong supporter clears a weak creature beside it (%s)" % str(task))
	else: check(task.get("kind") != "monster", "M: without the option supporters leave creatures to the leader")

func _case_n_joint() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 8)
	# The first supporter is a little nearer the near mine; the second can
	# reach only that mine soon. Taking turns sends the second far away.
	var first := _hero(director, 2, 40, 90, 2)
	var second := _hero(director, 2, 40, 80, 2)
	var near := _place(director, "mine", 42, 86, {"owner": -1})
	var far := _place(director, "mine", 40, 108, {"owner": -1})
	_pass(director)
	var total := 0
	for hero: Dictionary in [first, second]:
		var target := director.state.object(int(_task_of(director, hero).get("target", -1)))
		if not target.is_empty(): total += ELFirstAI._route_cost(director, hero, target, false)
	var greedy := ELFirstAI._route_cost(director, first, near, false) + ELFirstAI._route_cost(director, second, far, false)
	var joint := ELFirstAI._route_cost(director, first, far, false) + ELFirstAI._route_cost(director, second, near, false)
	if smart: check(total <= mini(greedy, joint), "N: the two supporters split the mines for the least walking (%d, best %d)" % [total, mini(greedy, joint)])
	else: check(total == greedy, "N: without the option heroes choose in turn (%d)" % total)

# --- P: strategic battles -----------------------------------------------------

func _case_p_resolver() -> void:
	var director := _world()
	var state := director.state
	var strong := _hero(director, 2, 30, 90, 1)
	var weak := _hero(director, 3, 32, 90, 1)
	var wins := 0
	var trials := 600
	for trial in trials:
		if ELFirstAI.winner(state, strong, weak) == strong: wins += 1
	var share := float(wins) / trials
	check(absf(share - 2.0 / 3.0) < 0.06, "P: equal levels give the first side two chances in three (%.2f)" % share)
	var neutral := _place(director, "monster", 34, 90, {"owner": 0, "level": 9})
	check(ELFirstAI.winner(state, neutral, weak) == weak, "P: a player's hero always beats a neutral creature")
	# The estimate switch (off by default) weighs the sides instead.
	# (Called by name so that this file also loads where the switch is missing.)
	var planner: Script = load("res://src/content/first_ai_planner.gd") if ResourceLoader.exists("res://src/content/first_ai_planner.gd") else null
	check(planner != null, "P: the strength estimate exists")
	if planner == null: return
	weak.health = 1
	weak.cards = []
	var estimated := 0
	for trial in trials:
		if (ELFirstAI as Script).call("winner", state, strong, weak, true) == strong: estimated += 1
	check(estimated > trials * 0.8, "P: with the estimate a far stronger side wins nearly always (%d of %d)" % [estimated, trials])
	director.smart_ai = false
	check(float(planner.call("win_chance", director, strong, neutral)) == 1.0, "P: the planner's risk follows the original rule while the switch is off")
	director.set("battle_estimate", true)
	check(float(planner.call("win_chance", director, strong, neutral)) < 1.0, "P: and the estimate while it is on")

func _case_p_monsters() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 1)
	var mob := _place(director, "monster", 34, 90, {"owner": 0, "level": 14, "health": 400})
	hero.health = 1
	director.interception.rebuild(state, director.grid)
	var odds := ELFirstAIPlanner.win_chance(director, hero, mob)
	var task := {"kind": "monster", "target": int(mob.uid)}
	director.set_meta("first_ai_stats", {})
	var before_seed := state.seed_value
	var before_book: Array = hero.rune_uses.duplicate()
	check(not ELFirstAI.forecast_objective(director, hero, task), "P: trial duels reject an overwhelming monster")
	var forecast: Dictionary = director.get_meta("first_ai_stats")
	check(int(forecast.get("forecast_trials", 0)) >= 2, "P: the decision came from actual duels")
	check(hero.rune_uses == before_book and state.seed_value == before_seed and hero.alive and mob.alive, "P: forecasts leave runes, map RNG and fighters intact")
	var samples := int(forecast.forecast_trials)
	check(not ELFirstAI.forecast_objective(director, hero, task) and int(forecast.forecast_trials) == samples, "P: unchanged matchup reuses the forecast")
	var lair := _place(director, "Teacher", 30, 79, {"name": "Dungeon1", "monster": int(mob.uid)})
	check(ELAdditionalBuildings.visit_problem(state, hero, lair).is_empty(), "P: the lair is open for a visit")
	check(not ELFirstAI.forecast_objective(director, hero, {"kind": "building", "target": int(lair.uid)}), "P: trial duels also assess the lair's occupant")

	hero.strategy_order = {"destination": [33, 90], "use": -1, "route": ELFirstAI.route_rules(director, 2, false)}
	var guarded: Array = director.interception.zones[int(mob.uid)].cells
	director.smart_ai = false
	var original := ELStrategy.order_path(director, hero)
	director.smart_ai = true
	check(not original.is_empty() and guarded.has(original[-1]), "P: the original route can end inside the guard area")
	check(ELStrategy.order_path(director, hero).is_empty(), "P: the smarter route refuses to end in the dangerous guard area")
	hero.strategy_order.destination = [38, 90]
	var smarter := ELStrategy.order_path(director, hero)
	check(not smarter.is_empty() and not smarter.any(func(cell: Vector2i) -> bool: return guarded.has(cell)), "P: the smarter route goes around the guard")

	var results := []
	state.event.connect(func(event: Dictionary) -> void:
		if event.kind == "battle_finished": results.append(event.winner))
	director.strategy = {"phase": "combat", "combats": [[mob.uid, hero.uid]], "actors": [], "index": 0, "free": "night", "legacy_orders": false}
	ELStrategy.advance(director)
	check(results == [mob.uid] and mob.alive and not hero.alive, "P: a neutral monster can win an off-screen duel")
	check(director.encounter == null and director.error.is_empty(), "P: the duel neither opens an encounter screen nor stops the turn")

	var winner := _hero(director, 2, 36, 90, 10)
	mob.health = 1
	var before := int(winner.experience)
	var winning_odds := ELFirstAIPlanner.win_chance(director, winner, mob)
	check(winning_odds > odds, "P: a stronger hero has better odds (%.3f)" % winning_odds)
	check(ELFirstAI.forecast_objective(director, winner, task), "P: the trials approve a favorable matchup")
	check(int(forecast.get("forecast_extended", 0)) > 0, "P: the last active hero receives extra trials")
	director.strategy.combats.append([winner.uid, mob.uid])
	ELStrategy.advance(director)
	check(results == [mob.uid, winner.uid] and winner.alive and not mob.alive and int(winner.experience) > before, "P: a computer winner gets the actual duel reward")

func _case_p_committed_duel() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 1)
	var mob := _place(director, "monster", 34, 90, {"owner": 0, "level": 1, "health": 400})
	hero.health = 5
	# The hero has only fallback cantrips and cannot deal enough damage
	# before ether disturbance takes it down to two life and then kills it.
	var finite_spell := ""
	for code: String in profile.table("CombatSpells"):
		if not ELRunes.unlimited(profile, hero, code) and not ELCatalog.rule(profile, code).is_empty():
			finite_spell = code
			break
	check(not finite_spell.is_empty(), "P: a finite spell is available for the disturbance duel")
	if finite_spell.is_empty(): return
	for actor: Dictionary in [hero, mob]:
		actor.cards = [finite_spell]
		actor.specialization = "NONE"
		actor.skills = {}
		ELRunes.initialize(profile, actor, [0])
	var results := []
	state.event.connect(func(event: Dictionary) -> void:
		if event.kind == "battle_finished": results.append(event.winner))
	director.strategy = {"phase": "combat", "combats": [[hero.uid, mob.uid]], "actors": [], "index": 0, "free": "night", "legacy_orders": false}
	ELStrategy.advance(director)
	check(results == [mob.uid] and mob.alive and not hero.alive, "P: a committed hero fights to defeat even after surviving heavy damage")
	check(director.error.is_empty() and director.encounter == null, "P: ether disturbance ends the headless duel and the turn can continue")

func _case_p_approach() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 2)
	var mob := _place(director, "monster", 34, 90, {"owner": 0})
	director.interception.rebuild(state, director.grid)
	var here := Vector2i(hero.x, hero.y)
	var plain := director.grid.approach(here, mob)
	var original: Vector2i = director.interception.preview(state, hero, plain)[-1]
	var alternate := Vector2i(35, 91)
	var kind := 0
	while ELAdventureEncounter.terrain_arena(kind) == ELAdventureEncounter.terrain_arena(GRASS) or ELAdventureEncounter.terrain_arena(kind) == 4:
		kind += 1
	for delta: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var corner := alternate + delta
		state.map.terrain[corner.y * (state.map.width + 1) + corner.x] = kind
	check(ELAdventureEncounter.terrain_class(state.map, original) != ELAdventureEncounter.terrain_class(state.map, alternate), "P: a reachable guard tile on different terrain")
	director.monster_forecasts[ELFirstAI._forecast_key(state, hero, mob, true, original)] = {"base_approved": false, "samples": 3}
	director.monster_forecasts[ELFirstAI._forecast_key(state, hero, mob, true, alternate)] = {"base_approved": true, "narrow": false, "samples": 10, "extended": true}
	var closed: Array[Vector2i] = []
	var path := ELStrategy.screen_monster_route(director, hero, plain, mob, Vector2i(mob.x, mob.y), closed, {"remaining": 0})
	for point: Vector2i in closed: director.grid._update_cell(point)
	var stop: Array = director.interception.preview(state, hero, path)
	check(not stop.is_empty() and director.interception.enemies(state, hero, stop[-1]).has(int(mob.uid)) and ELAdventureEncounter.terrain_class(state.map, stop[-1]) == ELAdventureEncounter.terrain_class(state.map, alternate), "P: the rejected terrain leaves a reachable alternate approach")

func _case_p_matchup_shop() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	var mob := _place(director, "monster", 33, 90, {"owner": 0, "level": 4})
	var portal := _place(director, "portal", 29, 90)
	_rich(state, 2)
	var slot := _rune_slot(hero)
	check(slot >= 0, "P: the matchup shopper has a refillable spell")
	if slot < 0: return
	hero.rune_uses[slot] = 0
	director.interception.rebuild(state, director.grid)
	var tile := Vector2i(mob.x, mob.y)
	var upgraded := hero.duplicate(true)
	upgraded.rune_uses[slot] = ELRunes.capacity(hero)
	for guard_first in [false, true]:
		director.monster_forecasts[ELFirstAI._forecast_key(state, hero, mob, guard_first, tile)] = {"base_approved": false, "samples": 3}
		director.monster_forecasts[ELFirstAI._forecast_key(state, upgraded, mob, guard_first, tile)] = {"base_approved": true, "narrow": false, "samples": 10, "extended": true}
	var preview := ELAdventureEncounter.new()
	check(preview.prepare_map_ai_duel(state, int(hero.uid), int(mob.uid), 9026, tile, upgraded) and int(preview.battle.heroes[0].spell_uses[slot]) == ELRunes.capacity(hero), "P: trial preparation uses the hypothetical charges")
	var stock: Dictionary = state.players[2].resources.duplicate()
	var quote := ELFirstAIEconomy.matchup_purchase(director, hero, portal, mob)
	check(int(quote.get("slot", -1)) == slot and int(quote.get("amount", 0)) == ELRunes.capacity(hero), "P: a refill that changes the forecast is selected")
	check(int(hero.rune_uses[slot]) == 0 and state.players[2].resources == stock, "P: quoting the refill leaves runes and resources intact")
	var ai := ELFirstAI.data(state, 2)
	ai.assigned = [[int(hero.uid), {"kind": "shop", "target": int(portal.uid), "guard": int(mob.uid)}]]
	ELFirstAIEconomy.visit(director, hero, portal)
	check(int(hero.rune_uses[slot]) == ELRunes.capacity(hero) and state.players[2].resources != stock, "P: the targeted visit pays through the ordinary portal transaction")
	check(not ai.assigned.is_empty() and ai.assigned[0][1]["kind"] == "monster" and int(ai.assigned[0][1]["target"]) == int(mob.uid), "P: the hero resumes its guard objective after resupplying")

	# Price a new spell together with its runes and carry the quote through
	# both actual visits. The existing portal is reachable from the shop.
	var card := ""
	var colour := ELFirstSpellShop.hero_color(profile, hero)
	for code: String in profile.table("CombatSpells"):
		if profile.table("CombatSpells")[code].get("Color") != colour or hero.cards.has(code) or ELRunes.unlimited(profile, hero, code) or ELCatalog.rule(profile, code).is_empty(): continue
		if ELFirstAIEconomy._total(ELRuneShop.price(profile, hero, portal, code)) <= 0: continue
		card = code
		break
	check(not card.is_empty() and protos.has("shop"), "P: a compatible spell shop and finite spell")
	if card.is_empty() or not protos.has("shop"): return
	var node: Dictionary = protos.shop.node.duplicate(true)
	node.children = node.children.filter(func(child: Dictionary) -> bool: return child.tag != "spells")
	node.children.append({"tag": "spells", "attrs": {"level": 1}, "children": [{"tag": "spell", "text": card}]})
	var shop := _place(director, "shop", 25, 84, {"node": node})
	var replace := ELFirstAIEconomy._replacement_slot(state, hero, card)
	var net := hero.duplicate(true)
	var under := ELRunes.under(hero)
	if ELRunes.unlimited(profile, hero, hero.cards[replace]): under[replace] = hero.cards[replace]
	net.cards[replace] = card
	net.rune_uses[replace] = mini(ELFirstAIEconomy.RUNE_LOAD, ELRunes.capacity(hero))
	ELRunes.set_under(net, under)
	for guard_first in [false, true]:
		director.monster_forecasts[ELFirstAI._forecast_key(state, hero, mob, guard_first, tile)] = {"base_approved": false, "samples": 3}
		director.monster_forecasts[ELFirstAI._forecast_key(state, net, mob, guard_first, tile)] = {"base_approved": true, "narrow": false, "samples": 10, "extended": true}
	ai.assigned = [[int(hero.uid), {"kind": "shop", "target": int(shop.uid), "guard": int(mob.uid)}]]
	ELFirstAIEconomy.visit(director, hero, shop)
	check(hero.cards[replace] == card and int(hero.rune_uses[replace]) == 0, "P: buying the spell alone leaves its runes empty")
	check(not ai.assigned.is_empty() and int(ai.assigned[0][1].get("target", -1)) == int(portal.uid), "P: the next objective carries the refill to the portal")
	if ai.assigned.is_empty(): return
	ai.assigned[0][1] = ELFirstAI._task(state, JSON.parse_string(JSON.stringify(ai.assigned[0][1])))
	check(ai.assigned[0][1].has("refill"), "P: the matchup refill survives save validation")
	for guard_first in [false, true]:
		director.monster_forecasts[ELFirstAI._forecast_key(state, hero, mob, guard_first, tile)] = {"base_approved": false, "samples": 3}
	ELFirstAIEconomy.visit(director, hero, portal)
	check(int(hero.rune_uses[replace]) == int(net.rune_uses[replace]), "P: the portal fills the planned copy")
	check(not ai.assigned.is_empty() and ai.assigned[0][1].get("kind") == "monster", "P: the purchased book leads back to the guard")

# --- Q: short strategic lookahead --------------------------------------------

## A leader below siege level; a mine penned in with its one gap guarded by a
## weak creature, and a Teacher a little nearer the other way (alone, the
## Teacher is worth a little more than the creature).
func _q_world() -> Array:
	var director := _world()
	var lead := _hero(director, 2, 30, 60, 5)
	lead.health = 26
	var mine := _place(director, "mine", 50, 60, {"owner": -1})
	var gap := Vector2i(int(mine.x) - 2, int(mine.y))
	_pen(director, mine, 2, [gap])
	# The gap is one cell wide (walls take the terrain corners beside it);
	# the guard stands two cells out, its area covering the cell before it.
	var guard := _place(director, "monster", gap.x - 2, gap.y, {"owner": 0, "level": 1, "health": 4, "cards": ["CAFG"], "rune_uses": [4]})
	var teacher := _place(director, "Teacher", 14, 60)
	director.interception.rebuild(director.state, director.grid)
	return [director, lead, mine, guard, teacher]

func _case_q_lookahead() -> void:
	var plain := _q_world()
	_planner_set("lookahead", false)
	_pass(plain[0])
	var single := _task_of(plain[0], plain[1])
	_planner_set("lookahead", true)
	var looked := _q_world()
	_pass(looked[0])
	var chosen := _task_of(looked[0], looked[1])
	if not smart:
		check(single.hash() == chosen.hash(), "Q: without the option the lookahead changes nothing (%s / %s)" % [str(single), str(chosen)])
		return
	var director: ELAdventureDirector = looked[0]
	var guard: Dictionary = looked[3]
	check(ELFirstAI._route_cost(director, looked[1], looked[2], true) == ELFirstAI.NONE, "Q: the mine has no way in but past its guard")
	check(int(single.get("target", -1)) == int(plain[4].uid), "Q: plain smarter planning takes the best single objective, the Teacher (%s)" % str(single))
	check(int(chosen.get("target", -1)) == int(guard.uid), "Q: the lookahead clears the guard first, which opens the mine behind it (%s)" % str(chosen))

# --- T: living world ------------------------------------------------------------

## A level-two hero with nothing to do and two mines of its own.
func _t_idle() -> Array:
	var director := _world()
	var home := _castle(director, 2)
	var hero := _hero(director, 2, int(home.x) - 10, int(home.y) + 10, 2)
	var first := _place(director, "mine", int(home.x) - 16, int(home.y) + 4, {"owner": 2})
	var second := _place(director, "mine", int(home.x) - 4, int(home.y) + 18, {"owner": 2})
	return [director, hero, first, second]

func _case_t_patrol() -> void:
	var world := _t_idle()
	var director: ELAdventureDirector = world[0]
	var hero: Dictionary = world[1]
	_pass(director)
	check(_task_of(director, hero).is_empty(), "T: without the switch an idle hero stays idle (%s)" % str(_task_of(director, hero)))
	if not _living(director, true): return
	_pass(director)
	var task := _task_of(director, hero)
	if not smart:
		check(task.is_empty(), "T: without smarter players the switch changes nothing (%s)" % str(task))
		return
	check(task.get("kind") == "patrol" and not hero.strategy_order.is_empty(), "T: an idle hero sets out on a patrol of its sites (%s)" % str(task))
	var stop := director.state.object(int(task.get("target", -1)))
	if stop.is_empty(): return
	# Beside that stop, the patrol goes on to the next one.
	hero.x = int(stop.x) - 1
	hero.y = int(stop.y)
	director.grid.update_actor(hero)
	_pass(director)
	var next := _task_of(director, hero)
	check(next.get("kind") == "patrol" and int(next.get("target", -1)) != int(stop.uid), "T: beside one stop the patrol walks on to the next (%s)" % str(next))
	# Work comes first: a free mine nearby ends the patrol.
	var mine := _place(director, "mine", int(hero.x) - 3, int(hero.y) + 3, {"owner": -1})
	_pass(director)
	check(int(_task_of(director, hero).get("target", -1)) == int(mine.uid), "T: a patrolling hero takes up real work when it appears (%s)" % str(_task_of(director, hero)))

func _case_t_raid() -> void:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	var site := _place(director, "mine", 38, 90, {"owner": 3})
	ELFog.refresh(state)
	var planner := _planner()
	if planner == null: return
	var task := {"kind": "mine", "target": int(site.uid)}
	var before: float = planner.call("utility", director, side, 1, task, {}, true)
	if not _living(director, true): return
	var raid: float = planner.call("utility", director, side, 1, task, {}, true)
	if not smart:
		check(before == raid, "T: without smarter players there is no raid weighing")
		return
	check(raid > before + 10.0, "T: an undefended enemy mine is worth a raid (%.0f -> %.0f)" % [before, raid])
	var keeper := _hero(director, 3, 39, 92, 3)
	ELFog.refresh(state)
	var guarded: float = planner.call("utility", director, side, 1, task, {}, true)
	check(guarded < raid, "T: not when a hero of its owner stands by (%.0f)" % guarded)
	check(keeper.alive, "T: the keeper stays")

func _case_t_escort() -> void:
	var director := _world()
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 6)
	var side := _hero(director, 2, int(home.x) - 8, int(home.y) + 4, 3)
	_living(director, true)
	_pass(director)
	_pass(director)
	var siege := _task_of(director, lead)
	var task := _task_of(director, side)
	if not smart:
		check(task.get("kind") != "escort", "T: without smarter players no escort is made")
		return
	check(siege.get("kind") == "tower", "T: the level-six leader besieges a castle (%s)" % str(siege))
	check(task.get("kind") == "escort" and int(task.get("target", -1)) == int(lead.uid), "T: a supporter escorts the weak besieger (%s)" % str(task))
	_living(director, false)
	_pass(director)
	check(_task_of(director, side).get("kind") != "escort", "T: without the switch the escort is given up (%s)" % str(_task_of(director, side)))

func _case_t_retreat() -> void:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	for kind: String in state.players[2].resources: state.players[2].resources[kind] = 5000
	var portal := _place(director, "portal", 34, 90)
	var mine := _place(director, "mine", 26, 90, {"owner": -1})
	var slot := _rune_slot(side)
	if slot < 0:
		check(false, "T: the hero has a spell that uses runes")
		return
	# Every rune-using copy down to one rune: low, but none empty.
	for index in side.rune_uses.size():
		if int(side.rune_uses[index]) >= 0: side.rune_uses[index] = 1
	_pass(director)
	var plain := _task_of(director, side)
	ELFirstAI.data(state, 2).assigned = []
	_living(director, true)
	_pass(director)
	var task := _task_of(director, side)
	if not smart:
		check(plain.get("kind") == task.get("kind") and plain.get("target") == task.get("target"), "T: without smarter players the switch changes nothing")
		return
	check(int(plain.get("target", -1)) == int(mine.uid), "T: without the switch the hero takes the mine (%s)" % str(plain))
	check(int(task.get("target", -1)) == int(portal.uid), "T: low on runes, the hero turns back to the portal (%s)" % str(task))

func _case_t_doctrine() -> void:
	var director := _world()
	var state := director.state
	var planner := _planner()
	if planner == null or not "living_world" in director: return
	var chosen := {}
	var repeat := true
	for seed in range(1, 13):
		# A new session with this seed chooses afresh.
		state.seed_value = seed
		ELFirstAI.data(state, 2).erase("doctrine")
		var name: String = planner.call("doctrine", state, 2)
		if name != planner.call("doctrine", state, 2): repeat = false
		chosen[name] = true
		# Later random events move the seed on; the doctrine stays.
		state.seed_value = seed * 7919 + 17
		if name != planner.call("doctrine", state, 2): repeat = false
	check(repeat, "T: the doctrine is chosen once and kept while the session's random numbers move on")
	check(chosen.size() >= 2 and not chosen.has(""), "T: seeds give players different doctrines (%s)" % str(chosen.keys()))
	state.seed_value = 212
	ELFirstAI.data(state, 2).erase("doctrine")
	var hero := _hero(director, 2, 30, 90, 3)
	var name: String = planner.call("doctrine", state, 2)
	check(float(planner.call("weight", director, hero, "tower")) == 1.0, "T: without the switch every weight is one")
	_living(director, true)
	var expected := float(planner.DOCTRINES[name].get("tower", 1.0)) if smart else 1.0
	check(float(planner.call("weight", director, hero, "tower")) == expected, "T: with it the %s doctrine weighs sieges %.2f" % [name, expected])
	# A chapter that names this player's castle keeps the plain weights.
	var id := state.map.id
	state.map.id = "mission12"
	check(planner.call("doctrine", state, 4) == "" and planner.call("doctrine", state, 2) != "", "T: no doctrine for a player whose castle the chapter names, one for the others")
	var named := _hero(director, 4, 40, 90, 3)
	check(float(planner.call("weight", director, named, "tower")) == 1.0, "T: its heroes keep the plain weights")
	state.map.id = id

func _case_t_story() -> void:
	# The idle-hero fixture, with the switch on: a map's own hero in a
	# campaign chapter and a hero a queued script command names stay idle.
	var world := _t_idle()
	var director: ELAdventureDirector = world[0]
	var state := director.state
	var hero: Dictionary = world[1]
	if not _living(director, true): return
	state.scenario.campaign = true
	hero.source_index = 3
	_pass(director)
	check(_task_of(director, hero).is_empty(), "T: a map's own hero in a campaign chapter is left to the plain planning (%s)" % str(_task_of(director, hero)))
	hero.source_index = -1
	state.commands.append({"kind": "Moving", "arguments": [hero.uid, 10, 10]})
	_pass(director)
	check(_task_of(director, hero).is_empty(), "T: so is a hero a script command names (%s)" % str(_task_of(director, hero)))
	state.commands.clear()
	# Neutral creatures keep their places and get no orders.
	var creature := _place(director, "monster", 60, 60, {"owner": 0, "level": 2})
	for round in 3: _pass(director)
	check(Vector2i(creature.x, creature.y) == Vector2i(60, 60) and creature.get("strategy_order", {}).is_empty(), "T: neutral creatures stay home")

func _case_t_off() -> void:
	# A busy little world planned with the switch off twice and on once: the
	# planning repeats, and without smarter players the switch changes nothing.
	var plans: Array = []
	for on: bool in [false, false, true]:
		var director := _world()
		var home := _castle(director, 2)
		_hero(director, 2, int(home.x) - 6, int(home.y), 7)
		_hero(director, 2, 30, 90, 3)
		_hero(director, 2, 40, 80, 2)
		_place(director, "mine", 36, 92, {"owner": 3})
		_place(director, "mine", 46, 84, {"owner": -1})
		_place(director, "monster", 50, 96, {"owner": 0, "level": 1})
		_place(director, "Teacher", 34, 70)
		_living(director, on)
		for round in 3: _pass(director)
		plans.append(var_to_str(ELFirstAI.data(director.state, 2).assigned))
	check(plans[0] == plans[1], "T: planning is repeatable")
	if not smart: check(plans[0] == plans[2], "T: without smarter players the switch changes nothing")

# --- V: economy -------------------------------------------------------------------

## The first of `codes` that a global-spell scroll gives `player` (its colour
## or colourless); "" if none.
func _spell_code(state: ELAdventureSession, player: int, codes: Array) -> String:
	var colour := str(state.players[player].get("color", ""))
	for code: Variant in codes:
		if ELMapPickups.resolve(profile, [str(code)], colour) == str(code): return str(code)
	return ""

func _rich(state: ELAdventureSession, player: int, amount := 5000) -> void:
	for kind: String in state.players[player].resources: state.players[player].resources[kind] = amount

## The ether income of `player`'s castle (its MainTower).
func _tower_income(state: ELAdventureSession, player: int, amount: int) -> void:
	for item: Dictionary in state.objects.values():
		if item.get("group") == "buildings" and item.get("name") == "MainTower" and int(item.get("owner", -1)) == player:
			if not item.node.has("attrs"): item.node.attrs = {}
			item.node.attrs.mana_income = amount

func _case_v_cast() -> void:
	# Castle 7 energy, 7 damage pending, a repair that today's ether finishes:
	# cast today it saves the castle; left until tomorrow the castle falls.
	if not smart: return
	var director := _world()
	var state := director.state
	# A computer player whose colour has a repair spell.
	var player := -1
	var code := ""
	for id: int in ELFirstAI.computer_players(state):
		code = _spell_code(state, id, ELGlobalSpells.REPAIRS.keys())
		if not code.is_empty():
			player = id
			break
	check(not code.is_empty(), "V: a repair spell for a computer player's colour")
	if code.is_empty(): return
	var hero := _hero(director, player, 30, 90, 3)
	_rich(state, player)
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	var cost := ELGlobalSpells.ether_cost(state, player, code)
	var castle: Dictionary = state.scenario.castles[player]
	castle.health = 7
	castle.pending = 7
	state.players[player].free_ether = cost
	var repair := int(ELGlobalSpells.REPAIRS[code])
	var expected := maxi(repair, ELFirstScenario.regeneration(cost))
	ELFirstAIEconomy.global_spells(director, player)
	ELFirstScenario.regenerate(state)
	ELFirstScenario.end_night(director)
	check(castle.alive and int(castle.health) == expected, "V: a repair finished today is cast at once (%s costs %d ether: energy %d after the night, best %d)" % [code, cost, int(castle.health), expected])

func _case_v_income() -> void:
	# No ether income tomorrow, but ether in hand today: a spell it pays for is begun.
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	_rich(state, 2)
	var code := ""
	for candidate: String in ELGlobalSpells.CASTLE_DAMAGE:
		if _spell_code(state, 2, [candidate]) == candidate and ELGlobalSpells.upkeep(profile, candidate) == 0:
			code = candidate
			break
	check(not code.is_empty(), "V: a castle-damage spell for this colour")
	if code.is_empty(): return
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	_tower_income(state, 2, 0)
	check(ELResourceSites.mana_income(state, 2) == 0, "V: the player has no ether income")
	state.players[2].free_ether = ELGlobalSpells.ether_cost(state, 2, code)
	var record := ELGlobalSpells.data(state, 2)
	var serial := int(record.serial)
	ELFirstAIEconomy.global_spells(director, 2)
	check(not record.production.is_empty() or int(record.serial) > serial, "V: today's ether is spent though tomorrow brings none (%s)" % str(record.production))

func _case_v_runes() -> void:
	# The least resources that buy a spell with a full load of five runes:
	# with room for fifteen, the spell is still bought, with fewer runes.
	if not smart: return
	var director := _world()
	var state := director.state
	var side := _hero(director, 2, 30, 90, 3)
	_place(director, "portal", 20, 80)
	_rich(state, 2)
	var shop := {}
	for proto: Dictionary in protos.get("shops", []):
		var candidate := _place(director, "shop", 32, 90, {"name": proto.name, "node": proto.node, "level": 0, "owner": 0})
		if ELFirstAIEconomy.wants(director, side, candidate) > 0:
			shop = candidate
			break
		_kill(director, candidate)
		state.objects.erase(int(candidate.uid))
	check(not shop.is_empty(), "V: a spell shop that sells this hero something")
	if shop.is_empty(): return
	# Over a sweep of the resources held, room for fifteen runes (Provision)
	# never buys fewer spells that need runes than room for five.
	var worst := ""
	var bought := 0
	var amount := 4
	while amount <= 3000:
		var five := _rune_buys(state, side, shop, amount, false)
		var fifteen := _rune_buys(state, side, shop, amount, true)
		bought = maxi(bought, five)
		if fifteen < five and worst.is_empty(): worst = "%d resources: %d with room for 5, %d with room for 15" % [amount, five, fifteen]
		amount += 3 if amount < 300 else 50
	check(bought > 0, "V: the shop sells spells that need runes")
	check(worst.is_empty(), "V: more rune room does not stop a purchase that fits (%s)" % worst)

## Spells needing runes a visit to `shop` buys with `amount` of each resource
## (with or without Provision's room for fifteen); everything is put back.
func _rune_buys(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, amount: int, provision: bool) -> int:
	var hero_copy := hero.duplicate(true)
	var shop_copy := shop.duplicate(true)
	var wallet: Dictionary = state.players[2].resources.duplicate()
	_rich(state, 2, amount)
	if provision: hero.skills.PRVD = 2
	else: hero.skills.erase("PRVD")
	var before := ELFirstAIEconomy.empty_copies(hero)
	ELFirstAIEconomy._shop(state, hero, shop, true)
	var result := ELFirstAIEconomy.empty_copies(hero) - before
	hero.clear()
	hero.merge(hero_copy)
	shop.clear()
	shop.merge(shop_copy)
	state.players[2].resources = wallet
	return result

func _case_v_portal() -> void:
	# A visit that upgrades the portal anyway upgrades it before buying, so its
	# runes come at the next level's price.
	if not smart: return
	var director := _world()
	var state := director.state
	var side := _hero(director, 2, 30, 90, 3)
	_rich(state, 2)
	# A spell of the hero's colour and a portal whose runes for it are dear
	# enough that the upgrade's discount shows.
	var colour_name := ELFirstSpellShop.hero_color(profile, side)
	var spells: Dictionary = profile.table("CombatSpells")
	var portal := {}
	for proto: Dictionary in protos.get("portals", []):
		for code: String in spells:
			if spells[code].get("Color") != colour_name or spells[code].get("Rarity") not in ["Common", "Rare", "Unique"]: continue
			var low := proto.duplicate()
			low.level = 0
			var high := proto.duplicate()
			high.level = 1
			if ELRuneShop.price(profile, side, low, code) == ELRuneShop.price(profile, side, high, code): continue
			side.cards[0] = code
			ELRunes.initialize(profile, side)
			portal = _place(director, "portal", 31, 90, {"name": proto.name, "node": proto.node, "level": 0, "owner": 0})
			break
		if not portal.is_empty(): break
	var slot := _rune_slot(side)
	check(not portal.is_empty() and slot >= 0 and ELStrategy.adjacent(director, side, portal), "V: the hero has a rune spell (%d) whose runes the upgrade makes cheaper, and stands by the portal" % slot)
	if portal.is_empty() or slot < 0: return
	for index in side.rune_uses.size():
		if int(side.rune_uses[index]) >= 0: side.rune_uses[index] = 0
	var colour := str(state.players[2].color)
	var upgrade := ELBuildings.upgrade_price(profile, portal, colour)
	var before: Dictionary = state.players[2].resources.duplicate()
	var uses: Array = side.rune_uses.duplicate()
	ELFirstAIEconomy.visit(director, side, portal)
	check(int(portal.level) == 1, "V: the portal is upgraded (level %d)" % int(portal.level))
	var expected := {}
	for kind: String in before: expected[kind] = int(upgrade.get(kind, 0))
	var bought := 0
	for index in uses.size():
		var count := int(side.rune_uses[index]) - int(uses[index])
		bought += count
		var unit := ELRuneShop.price(profile, side, portal, side.cards[index])
		for kind: String in expected: expected[kind] += int(unit.get(kind, 0)) * count
	var spent := {}
	for kind: String in before: spent[kind] = int(before[kind]) - int(state.players[2].resources[kind])
	check(bought > 0 and spent == expected, "V: the runes were bought after the upgrade, at its price (%d runes, spent %s, upgrade first %s)" % [bought, str(spent), str(expected)])

func _case_v_upkeep() -> void:
	# All ether goes to hero upkeep: a recruit's upkeep would not fit, so it is
	# not paid, which costs nothing; a summoning spell is still worth casting.
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	_tower_income(state, 2, ELStrategy.upkeep(profile, hero))
	var prefix: String = ELFirstAIEconomy.SUMMON_PREFIX.get(str(state.players[2].color), "")
	var code := prefix + "WR"
	var recruit := int(profile.table("HeroesStats").get("ManaUpkeep", {}).get("Level1", 0))
	check(ELGlobalSpells.SUMMONS.has(code) and recruit > 0 and ELFirstAIEconomy._daily_ether(state, 2) == 0, "V: income %d all spent on upkeep, a recruit costs %d" % [ELResourceSites.mana_income(state, 2), recruit])
	check(ELFirstAIEconomy._score(director, 2, code) > 0.0, "V: an unpaid recruit costs nothing, so the summoning is worth it (%.0f)" % ELFirstAIEconomy._score(director, 2, code))

func _case_v_mine() -> void:
	# A held mine whose upgrade soon repays itself is upgraded from the
	# player's screen, with no hero beside it.
	if not smart: return
	var director := _world()
	var state := director.state
	_hero(director, 2, 30, 90, 3)
	_rich(state, 2)
	var rows: Dictionary = profile.table("ResourceMine")
	var chosen := {}
	var best := -INF
	for row: Dictionary in rows.values():
		if int(row.get("Level", -1)) != 0 or not row.has("UpgradeCost"): continue
		var mine := {"group": "mines", "name": row.Name, "level": 0}
		var next := {"group": "mines", "name": row.Name, "level": 1}
		var cost := ELFirstAIEconomy._total(ELResourceSites.upgrade_price(profile, mine))
		var gain := ELFirstAIEconomy._total(ELResourceSites.production(profile, next)) - ELFirstAIEconomy._total(ELResourceSites.production(profile, mine))
		if ELResourceSites.definition(profile, next).is_empty() or cost <= 0: continue
		var score := float(gain * 30 - cost)
		if score > best:
			best = score
			chosen = row
	check(not chosen.is_empty() and best >= 0.0, "V: a mine whose upgrade repays itself (%s, %.0f)" % [str(chosen.get("Name", "")), best])
	if chosen.is_empty(): return
	var site := _place(director, "mine", 60, 60, {"owner": 2, "name": chosen.Name, "level": 0})
	ELFirstAIEconomy.daily(director, 2)
	check(int(site.level) == 1, "V: the held mine is upgraded without a hero beside it (level %d)" % int(site.level))

# --- W: goals and roles ------------------------------------------------------------

## A map pickup at (x, y): a battle artifact, or a global-spell scroll.
func _pickup(director: ELAdventureDirector, x: int, y: int, group: String, name: String, spells: Array = []) -> Dictionary:
	var node := {"tag": "object", "attrs": {}, "children": []}
	if not spells.is_empty():
		var list := {"tag": "spells", "attrs": {}, "children": []}
		for code: String in spells: list.children.append({"tag": "spell", "attrs": {"code": code}, "children": []})
		node.children.append(list)
	return _place(director, "pickup", x, y, {"group": group, "name": name, "type": "object", "owner": -1, "alive": true, "visible": true, "enabled": true, "placed": true, "rotation": 0, "node": node})

func _case_w_pickup() -> void:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 2)
	var artifact := _pickup(director, 35, 90, "artefacts", str(profile.table("Artefacts").keys()[0]))
	_pass(director)
	var task := _task_of(director, side)
	if not smart:
		check(task.get("kind") != "pickup", "W: without the option nobody sets out for a pickup")
		return
	check(task.get("kind") == "pickup" and int(task.get("target", -1)) == int(artifact.uid), "W: a supporter sets out for a battle artifact (%s)" % str(task))
	# Parts of a global spell complete it on one hero only: the hero already
	# holding two parts goes for the third, though another is nearer.
	var colour := str(state.players[2].color)
	var code := ""
	for candidate: String in profile.table("GlobalSpells"):
		if _spell_code(state, 2, [candidate]) == candidate and not ELMapPickups.available_codes(state, 2).has(candidate) and _castable(candidate):
			code = candidate
			break
	check(not code.is_empty(), "W: a global spell this player lacks")
	if code.is_empty(): return
	var other := _world()
	var holder := _hero(other, 2, 30, 90, 2)
	var near := _hero(other, 2, 30, 100, 2)
	var leader_home := _castle(other, 2)
	_hero(other, 2, int(leader_home.x) - 6, int(leader_home.y), 7)
	holder.gs_items = [{"kind": ELMapPickups.PART, "spells": [code]}, {"kind": ELMapPickups.PART, "spells": [code]}]
	var part := _pickup(other, 34, 97, "global_spells", ELMapPickups.PART, [code])
	_pass(other)
	check(int(_task_of(other, holder).get("target", -1)) == int(part.uid), "W: the third part goes to the hero holding two (%s / nearer %s)" % [str(_task_of(other, holder)), str(_task_of(other, near))])
	check(colour != "", "W: the player has a colour")

func _case_w_commander() -> void:
	# The most experienced hero holds a fortification: it still meets ethereal
	# attacks, while the next hero leads in the field.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	var keeper := _hero(director, 2, int(home.x) - 6, int(home.y), 9)
	keeper.spell_fort = 1
	var field := _hero(director, 2, int(home.x) - 8, int(home.y) + 4, 7)
	_pass(director)
	check(_task_of(director, field).get("kind") == "tower", "W: the field commander besieges while the champion holds its fort (%s)" % str(_task_of(director, field)))
	check(ELGlobalSpells.defender(state, 2) == keeper, "W: the champion stays the realm's ethereal defender")

func _case_w_promotion() -> void:
	# A supporter sent to a far mine becomes the leader when the leader falls;
	# a leader takes only sites on its way, so the far mine is given up.
	var director := _world()
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 5)
	var mine := _place(director, "mine", 56, 90, {"owner": -1})
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "W: the supporter is sent to the far mine (%s)" % str(_task_of(director, side)))
	_kill(director, lead)
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(mine.uid), "W: promoted to leader, it gives up the far mine (%s)" % str(_task_of(director, side)))

func _case_w_hidden() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 40, 90, 2)
	var mine := _place(director, "mine", 46, 92, {"owner": -1})
	var far := _hero(director, 2, 20, 100, 2)
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "W: the nearest supporter is sent to the mine")
	# A script takes the hero off the map: its reservation lapses.
	side.visible = false
	_pass(director)
	check(int(_task_of(director, far).get("target", -1)) == int(mine.uid), "W: another supporter takes the mine a hidden hero held (%s)" % str(_task_of(director, far)))

func _case_w_pile() -> void:
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 40, 90, 2)
	var mine := _place(director, "mine", 46, 92, {"owner": -1, "visible": false})
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(mine.uid), "W: a hidden site is not an objective (%s)" % str(_task_of(director, side)))
	mine.visible = true
	mine.enabled = false
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(mine.uid), "W: nor a disabled one (%s)" % str(_task_of(director, side)))
	mine.enabled = true
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) == int(mine.uid), "W: once usable it is (%s)" % str(_task_of(director, side)))

func _case_w_peace() -> void:
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	_hero(director, 2, int(home.x) - 8, int(home.y) + 4, 6)
	_pass(director)
	var task := _task_of(director, lead)
	check(task.get("kind") == "tower", "W: the leader besieges a castle")
	var castle := state.object(int(task.get("target", -1)))
	if castle.is_empty(): return
	# A scripted peace with the castle's owner.
	var owner := int(castle.owner)
	var lower: Dictionary = state.players[mini(2, owner)]
	var upper: Dictionary = state.players[maxi(2, owner)]
	if not lower.has("relations"): lower.relations = {}
	var value := int(lower.relations.get(maxi(2, owner), upper.get("relations", {}).get(mini(2, owner), 0)))
	lower.relations[maxi(2, owner)] = value | 4
	check(not state.hostile(lead, castle), "W: the castle's owner is at peace now")
	_pass(director)
	check(int(_task_of(director, lead).get("target", -1)) != int(castle.uid), "W: a siege of a castle at peace ends (%s)" % str(_task_of(director, lead)))

func _case_w_scouts() -> void:
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var first := _hero(director, 2, 58, 60, 2)
	var second := _hero(director, 2, 58, 62, 2)
	_unexplore(director, 2, Rect2i(64, 0, state.map.width - 64, state.map.height))
	_pass(director)
	var tiles: Array[Vector2i] = []
	for hero: Dictionary in [first, second]:
		var task := _task_of(director, hero)
		if task.get("kind") == "explore": tiles.append(Vector2i(int(task.tile[0]), int(task.tile[1])))
	check(tiles.size() == 2, "W: both scouts explore (%s / %s)" % [str(_task_of(director, first)), str(_task_of(director, second))])
	if tiles.size() < 2: return
	var gap := maxi(absi(tiles[0].x - tiles[1].x), absi(tiles[0].y - tiles[1].y))
	check(gap >= 2 * ELFirstAIPlanner.REVEAL_RADIUS, "W: two scouts take different stretches of frontier (%s, %s: %d apart)" % [str(tiles[0]), str(tiles[1]), gap])

func _case_w_tinkerer() -> void:
	if not smart: return
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 40, 90, 2)
	var tinkerer := _place(director, "GnomeMerchant", 44, 90, {"name": "GnomeTinkerer", "used": false})
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(tinkerer.uid), "W: nobody walks to the Gnome Tinkerer, whose visit changes nothing (%s)" % str(_task_of(director, side)))

func _case_w_siege() -> void:
	# A level-six besieger (6 damage a night) at a full castle whose owner
	# leaves 216 ether unused (6 energy back each night) makes no progress:
	# it turns to a mine beside it.
	if not smart: return
	var director := _world()
	var state := director.state
	var target := _castle(director, 3)
	var lead := _hero(director, 2, int(target.x) - 1, int(target.y), 6)
	_pass(director)
	check(_task_of(director, lead).get("kind") == "tower", "W: the leader besieges the castle beside it (%s)" % str(_task_of(director, lead)))
	var castle: Dictionary = state.scenario.castles[int(target.owner)]
	castle.max = 24
	castle.health = 24
	castle.pending = 0
	state.players[int(target.owner)].free_ether = 216
	var mine := _place(director, "mine", int(lead.x) - 3, int(lead.y) + 1, {"owner": -1})
	_pass(director)
	var task := _task_of(director, lead)
	check(int(task.get("target", -1)) != int(target.uid), "W: a siege the castle regenerates away is given up (%s)" % str(task))
	var other := director.state.object(int(task.get("target", -1)))
	var planner := _planner()
	var known: bool = planner != null and planner.get_script_method_list().any(func(entry: Dictionary): return entry.name == "siege_nights")
	var onward: bool = int(task.get("target", -1)) == int(mine.uid) or (task.get("kind") == "tower" and other != target and known and int(planner.call("siege_nights", director, lead, other)) > 0)
	check(onward, "W: for the mine beside it or a siege that gains (%s)" % str(task))

func _case_w_unfound() -> void:
	# A leader ready for a siege whose player has found no enemy castle yet
	# looks for the way to one (it used to roam after creatures and never
	# meet the idle human's castle); once it is found, the siege begins.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var bit := ELFog.bit(2)
	var keep := Rect2i(int(home.x) - 14, int(home.y) - 14, 28, 28)
	for y in state.map.height:
		for x in state.map.width:
			if not keep.has_point(Vector2i(x, y)): state.explored[y * state.map.width + x] &= ~bit
	var castles := {}
	for item: Dictionary in state.objects.values():
		if ELFirstScenario.is_castle(item) and int(item.owner) >= 1 and int(item.owner) != 2 and not keep.has_point(Vector2i(int(item.x), int(item.y))): castles[int(item.uid)] = true
	check(not castles.is_empty(), "W: enemy castles lie outside the explored ground")
	_pass(director)
	var task := _task_of(director, lead)
	check(task.get("kind") == "explore" and castles.has(int(task.get("toward", -1))), "W: the leader seeks the way to an unfound enemy castle (%s)" % str(task))
	state.explored.fill(0xff)
	_pass(director)
	_pass(director)
	check(_task_of(director, lead).get("kind") == "tower", "W: with the castle found it besieges it (%s)" % str(_task_of(director, lead)))

func _case_w_human() -> void:
	# The human's castle is the main objective: a leader between it and a
	# computer's castle a little nearer besieges the human's.
	if not smart: return
	var director := _world()
	var state := director.state
	var human := _castle(director, 1)
	var rival := _castle(director, 3)
	check(not human.is_empty() and not rival.is_empty(), "W: a human and a computer castle")
	if human.is_empty() or rival.is_empty(): return
	# Halfway between them, two tiles nearer the computer's castle.
	var from := Vector2i(int(human.x), int(human.y))
	var to := Vector2i(int(rival.x), int(rival.y))
	var spot := from + (to - from) / 2
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	spot += step * 2
	var lead := _hero(director, 2, spot.x, spot.y, 7)
	_pass(director)
	var task := _task_of(director, lead)
	check(task.get("kind") == "tower" and int(task.get("target", -1)) == int(human.uid), "W: the leader besieges the human's castle before a nearer computer's (%s)" % str(task))

func _castable(code: String) -> bool:
	return ELFirstAIEconomy._usable(code)

## A global spell `player` lacks whose casting the computer does (`castable`)
## or does not consider, or "".
func _lacking(state: ELAdventureSession, player: int, castable: bool) -> String:
	for candidate: String in profile.table("GlobalSpells"):
		if _spell_code(state, player, [candidate]) != candidate or ELMapPickups.available_codes(state, player).has(candidate): continue
		if ELFirstAIEconomy._usable(candidate) == castable: return candidate
	return ""

func _case_w_scrolls() -> void:
	# A scroll of a global spell the computer never casts is not worth the
	# trip (a leader chasing such scrolls reached the enemy castles days
	# later); a scroll it would cast still is.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 2)
	var idle := _lacking(state, 2, false)
	var useful := _lacking(state, 2, true)
	check(not idle.is_empty() and not useful.is_empty(), "W: global spells the computer does and does not cast (%s, %s)" % [idle, useful])
	if idle.is_empty() or useful.is_empty(): return
	var junk := _pickup(director, 34, 90, "global_spells", ELMapPickups.FULL, [idle])
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(junk.uid), "W: nobody fetches a scroll of %s, which the computer never casts (%s)" % [idle, str(_task_of(director, side))])
	var other := _world()
	var leader_home := _castle(other, 2)
	_hero(other, 2, int(leader_home.x) - 6, int(leader_home.y), 7)
	var fetcher := _hero(other, 2, 30, 90, 2)
	var scroll := _pickup(other, 34, 90, "global_spells", ELMapPickups.FULL, [useful])
	_pass(other)
	check(int(_task_of(other, fetcher).get("target", -1)) == int(scroll.uid), "W: a scroll of %s, which it casts, is fetched (%s)" % [useful, str(_task_of(other, fetcher))])
	# The leader takes only a pickup on its way: one days off is left to
	# the supporters, one beside it is taken.
	var third := _world()
	var third_home := _castle(third, 2)
	var lead := _hero(third, 2, int(third_home.x) - 6, int(third_home.y), 4)
	var far := _pickup(third, int(lead.x) - 40, int(lead.y), "global_spells", ELMapPickups.FULL, [useful])
	_pass(third)
	check(int(_task_of(third, lead).get("target", -1)) != int(far.uid), "W: the leader leaves a scroll days away (%s)" % str(_task_of(third, lead)))
	var fourth := _world()
	var fourth_home := _castle(fourth, 2)
	var near_lead := _hero(fourth, 2, int(fourth_home.x) - 6, int(fourth_home.y), 4)
	var close := _pickup(fourth, int(near_lead.x) - 3, int(near_lead.y), "global_spells", ELMapPickups.FULL, [useful])
	_pass(fourth)
	check(int(_task_of(fourth, near_lead).get("target", -1)) == int(close.uid), "W: and takes one beside it (%s)" % str(_task_of(fourth, near_lead)))

# --- X: navigation and information --------------------------------------------------

func _case_x_arrival() -> void:
	# Two arrival cells beside a site cost the same; the one inside an avoided
	# (guarded) area is not chosen.
	var director := _world()
	var grid := director.grid
	var site := _place(director, "mine", 50, 60, {"owner": -1})
	var from := Vector2i(36, 61)
	var size: Vector2i = grid.footprints.get(int(site.uid), {}).get("size", Vector2i.ONE)
	var cells: Array = []
	var cheapest := 0x7fffffff
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
			var point := Vector2i(int(site.x) + x, int(site.y) + y)
			var path := grid.path(from, point)
			if path.is_empty(): continue
			var cost := grid.path_cost(path)
			if cost < cheapest:
				cheapest = cost
				cells = []
			if cost == cheapest: cells.append(point)
	check(cells.size() >= 2, "W: two arrival cells cost the same (%s)" % str(cells))
	if cells.size() < 2: return
	var avoid: Array[Vector2i] = [cells[0]]
	var route := grid.approach(from, site, false, avoid)
	check(not route.is_empty() and route[-1] != cells[0] and grid.path_cost(route) == cheapest, "X: the route arrives on the unguarded cell (%s, guarded %s)" % [str(route.back() if not route.is_empty() else null), str(cells[0])])

func _case_x_placed() -> void:
	# A hero set down inside a creature's guard area stays there that night.
	var director := _world()
	var state := director.state
	var guard := _place(director, "monster", 60, 60, {"owner": 0, "level": 3})
	var hero := _hero(director, 2, 61, 60, 2)
	check(director.interception.zones.has(int(guard.uid)), "X: the creature guards an area")
	state.event.emit({"kind": "hero_placed", "id": hero.uid})
	check(hero.get("intercepted", false), "X: the hero set down in the guard area is stopped")
	check(not director.interception.can_step(state, director.grid, hero, Vector2i(62, 60)), "X: and cannot step out")

func _case_x_chase() -> void:
	# The leader goes after an enemy hero; the enemy moves out of sight. The
	# route leads to where it was seen, not where it is.
	var director := _world()
	var state := director.state
	var lead := _hero(director, 2, 30, 60, 5)
	var enemy := _hero(director, 3, 34, 60, 1)
	ELFog.refresh(state)
	_pass(director)
	var task := _task_of(director, lead)
	check(int(task.get("target", -1)) == int(enemy.uid), "X: the leader goes after the enemy hero (%s)" % str(task))
	if lead.strategy_order.is_empty(): return
	var seen := Vector2i(int(enemy.x), int(enemy.y))
	var away := Vector2i(-1, -1)
	for spot: Vector2i in [Vector2i(30, 15), Vector2i(90, 20), Vector2i(90, 110), Vector2i(10, 120)]:
		if director.grid.passability(spot) >= 0 and not ELFog.visible(state, 2, spot):
			away = spot
			break
	check(away.x >= 0, "X: a tile out of the player's sight")
	if away.x < 0: return
	_take(director, enemy, away)
	ELFog.refresh(state)
	var path := ELStrategy.order_path(director, lead)
	check(not path.is_empty() and maxi(absi(path[-1].x - seen.x), absi(path[-1].y - seen.y)) <= 1, "X: the route ends where the enemy was last seen (%s, seen %s, now %s)" % [str(path.back() if not path.is_empty() else null), str(seen), str(away)])

func _case_x_sight() -> void:
	# mission23: a neutral hero of the shared-sight colour shows every player
	# its surroundings, also right after it steps.
	var director := _world()
	var state := director.state
	var template := ""
	var rows: Dictionary = profile.table("HeroTemplates")
	for key: String in rows:
		if str(rows[key].get("Color", "")) == ELFog.SHARED_SIGHT_COLOR:
			template = key
			break
	check(not template.is_empty(), "X: a template of the shared-sight colour")
	if template.is_empty(): return
	var id := state.map.id
	state.map.id = ELFog.SHARED_SIGHT_MAP
	var walker := state.object(ELAdditionalBuildings.spawn_hero(state, template, 0, 20, 20))
	ELFog.refresh(state)
	var spot := Vector2i(-1, -1)
	for candidate: Vector2i in [Vector2i(20, 50), Vector2i(50, 20), Vector2i(60, 60)]:
		if director.grid.passability(candidate) >= 0 and not ELFog.visible(state, 2, candidate):
			spot = candidate
			break
	check(ELFog.visible(state, 2, Vector2i(20, 20)) and spot.x >= 0, "X: the neutral hero's surroundings are seen, a far tile is not")
	if spot.x >= 0:
		walker.x = spot.x
		walker.y = spot.y
		ELFog.moved(state, walker)
		check(ELFog.visible(state, 2, spot), "X: after its step the new surroundings are seen at once")
	state.map.id = id

func _case_x_rounds() -> void:
	# Free movement: a hero that steps out of the only gap in a wall and spends
	# its movement opens the way for a hero waiting behind it the same day.
	var director := _world(true)
	var home := _castle(director, 2)
	var lead := _hero(director, 2, int(home.x) - 6, int(home.y), 7)
	lead.ap = 0
	_wall_line(director, 40, 0, director.state.map.height - 1, [60])
	var plug := _hero(director, 2, 40, 60, 2)
	var waiting := _hero(director, 2, 43, 60, 2)
	var near := _place(director, "mine", 30, 50, {"owner": -1})
	var beyond := _place(director, "mine", 26, 66, {"owner": -1})
	# Two steps take the hero in the gap clear of it, toward its mine, with
	# nothing left.
	plug.ap = director.grid.passability(Vector2i(39, 60)) + director.grid.passability(Vector2i(38, 59))
	if not ELStrategy.free_mode(director):
		check(false, "X: free movement applies on this map")
		return
	director.free_queue = [{"kind": "ai", "player": 2, "round": 0, "pending": [], "planned": false, "positions": {}}]
	ELStrategy.free_next(director)
	for step in 20000:
		if not director.error.is_empty(): break
		if director.strategy.is_empty() and director.movement.is_empty() and director.free_queue.is_empty(): break
		if not director.strategy.is_empty() and director.strategy.get("free", "") == "night": break
		director.advance(0.1)
	check(int(near.owner) == 2 or (int(plug.x) < 39 and int(plug.ap) == 0), "X: the hero in the gap steps clear of it and spends its movement (%s, %d left)" % [str(Vector2i(plug.x, plug.y)), int(plug.ap)])
	check(int(waiting.x) < 40 or int(beyond.owner) == 2, "X: the waiting hero goes through the gap the same day (%s)" % str(Vector2i(waiting.x, waiting.y)))

# --- Y: audit findings (castle defence, matching, economy, rules) --------------

## The soonest fall of a defence() result (a large number when it holds).
func _soonest(falls: Dictionary) -> int:
	var soonest := 1 << 20
	for id: Variant in falls: soonest = mini(soonest, int(falls[id]))
	return soonest

## A computer player whose colour has a repair spell (-1 if none).
func _repairer(state: ELAdventureSession) -> int:
	for id: int in ELFirstAI.computer_players(state):
		if not _spell_code(state, id, ELGlobalSpells.REPAIRS.keys()).is_empty(): return id
	return -1

func _case_y_garrison() -> void:
	# A hero standing beside the castle with an errand elsewhere does not
	# stop a raider (first-game heroes have no guard area); only a hero sent
	# to attack it counts, from when it can reach it.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	state.scenario.castles[2].health = 9
	_hero(director, 2, 20, 100, 8)
	var side := _hero(director, 2, int(home.x) - 1, int(home.y), 6)
	var raider := _hero(director, 3, int(home.x) - 6, int(home.y) - 8, 5)
	ELFog.refresh(state)
	var planner := _planner()
	var seen: Dictionary = planner.call("threats", director, 2)
	var falls: Dictionary = planner.call("defence", director, 2, seen)
	check(falls.has(int(raider.uid)), "Y1: a hero standing by the castle does not hold it (%s)" % str(falls))
	var guarded: Dictionary = planner.call("defence", director, 2, seen, {int(raider.uid): [side]})
	check(_soonest(guarded) > _soonest(falls), "Y1: a hero sent to attack the raider does (%s / %s)" % [str(guarded), str(falls)])
	_pass(director)
	var defended := false
	for pair: Array in ELFirstAI.data(state, 2).assigned:
		if int(pair[1].get("target", -1)) == int(raider.uid): defended = true
	check(defended, "Y1: so a hero is sent to meet the raider (%s)" % str(ELFirstAI.data(state, 2).assigned))

func _case_y_reopen() -> void:
	# The same raider grows more dangerous (its defender falls): the hero on
	# a mine errand turns to meet it, though no new enemy appeared.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	state.scenario.castles[2].health = 9
	_hero(director, 2, 20, 100, 8)
	var first := _hero(director, 2, int(home.x) - 8, int(home.y) + 2, 6)
	var second := _hero(director, 2, int(home.x) - 9, int(home.y) + 4, 6)
	_place(director, "mine", int(home.x) - 14, int(home.y) + 6, {"owner": -1})
	_place(director, "mine", int(home.x) - 16, int(home.y) + 10, {"owner": -1})
	var raider := _hero(director, 3, int(home.x) - 6, int(home.y) - 8, 5)
	ELFog.refresh(state)
	_pass(director)
	var defender := {}
	var other := {}
	for hero: Dictionary in [first, second]:
		if int(_task_of(director, hero).get("target", -1)) == int(raider.uid): defender = hero
		else: other = hero
	check(not defender.is_empty() and not _task_of(director, other).is_empty(), "Y2: one hero meets the raider, the other goes about an errand (%s / %s)" % [str(_task_of(director, first)), str(_task_of(director, second))])
	if defender.is_empty(): return
	var alarm: Variant = ELFirstAI.data(state, 2).get("alarm")
	_kill(director, defender)
	_pass(director)
	check(int(_task_of(director, other).get("target", -1)) == int(raider.uid), "Y2: its defender fallen, the other hero leaves its mine for the raider (%s, alarm %s)" % [str(_task_of(director, other)), str(alarm)])

func _case_y_idle() -> void:
	# A battle the hero is all but sure to lose is not taken for want of
	# anything better: waiting is worth more.
	if not smart: return
	var director := _world()
	var state := director.state
	director.set("battle_estimate", true)
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 8)
	var side := _hero(director, 2, 30, 90, 2)
	var brute := _hero(director, 3, 36, 90, 3)
	brute.health = 400
	ELFog.refresh(state)
	var planner := _planner()
	var chance := float(planner.call("win_chance", director, side, brute))
	var points := float(planner.call("utility", director, side, 1, {"kind": "hero", "target": int(brute.uid)}, {}, true))
	check(chance < 0.01 and points == -INF, "Y3: a hopeless attack is no objective (chance %.4f, %s)" % [chance, str(points)])
	_pass(director)
	check(int(_task_of(director, side).get("target", -1)) != int(brute.uid), "Y3: the hero does not attack (%s)" % str(_task_of(director, side)))

func _case_y_siege() -> void:
	# A partner fourteen days away adds nothing to the first nights of a siege.
	if not smart: return
	var director := _world()
	var state := director.state
	var target := _castle(director, 3)
	var near := _hero(director, 2, int(target.x) - 1, int(target.y), 8)
	var far := _hero(director, 2, int(target.x) - 1, int(target.y), 8)
	var task := {"kind": "tower", "target": int(target.uid), "personal": true}
	var ai := ELFirstAI.data(state, 2)
	var planner := _planner()
	ai.assigned = [[int(near.uid), task]]
	var alone := int(planner.call("siege_nights", director, near, target))
	ai.assigned = [[int(near.uid), task], [int(far.uid), task.duplicate()]]
	var together := int(planner.call("siege_nights", director, near, target))
	far.x = int(target.x) - 1 - 14 * int(far.strategy_capacity)
	var later := int(planner.call("siege_nights", director, near, target))
	check(together > 0 and (alone < 0 or together < alone), "Y4: a partner beside the castle shortens the siege (%d nights, alone %d)" % [together, alone])
	check(later == alone or (later > together and alone < 0), "Y4: one fourteen days away counts only from its arrival (%d nights, alone %d)" % [later, alone])

func _case_y_atomic() -> void:
	# A hero reconsidering (a new threat) that can reach nothing keeps no
	# objective another hero is given: one holder per objective.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	state.scenario.castles[2].health = 9
	_hero(director, 2, 20, 100, 8)
	var holder := _hero(director, 2, 40, 90, 3)
	var mine := _place(director, "mine", 46, 92, {"owner": -1})
	_hero(director, 2, 44, 96, 3)
	# A hero by the castle sees the raider.
	_hero(director, 2, int(home.x) - 1, int(home.y), 1)
	_pen(director, holder, 1)
	ELFirstAI.data(state, 2).assigned = [[int(holder.uid), {"kind": "mine", "target": int(mine.uid)}]]
	_hero(director, 3, int(home.x) - 6, int(home.y) - 8, 5)
	ELFog.refresh(state)
	_pass(director)
	var holders := 0
	for pair: Array in ELFirstAI.data(state, 2).assigned:
		if pair[1].get("kind") == "mine" and int(pair[1].get("target", -1)) == int(mine.uid): holders += 1
	check(holders == 1 and int(_task_of(director, holder).get("target", -1)) != int(mine.uid), "Y5: the mine has one holder, a hero that can reach it (%s)" % str(ELFirstAI.data(state, 2).assigned))

func _case_y_order() -> void:
	# A fortified enemy hero stops an attacker that enters its area and
	# fights first: at equal level three it wins 4 times in 7.
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	var enemy := _hero(director, 3, 36, 90, 3)
	ELFog.refresh(state)
	var planner := _planner()
	var open := float(planner.call("win_chance", director, hero, enemy))
	enemy.spell_fort = 1
	director.interception.rebuild(state, director.grid)
	var held := float(planner.call("win_chance", director, hero, enemy))
	check(absf(open - 4.0 / 7.0) < 1e-6, "Y6: an attacker moving first wins 4 in 7 (%.3f)" % open)
	check(absf(held - 3.0 / 7.0) < 1e-6, "Y6: against a fortified hero, which fights first, 3 in 7 (%.3f)" % held)

func _case_y_urgent() -> void:
	# An empty spell sends the hero to a portal only when a refill can be paid.
	if not smart: return
	var director := _world()
	var state := director.state
	var side := _hero(director, 2, 30, 90, 3)
	_place(director, "portal", 60, 60)
	var slot := _rune_slot(side)
	if slot < 0: return
	side.rune_uses[slot] = 0
	_rich(state, 2, 0)
	check(not ELFirstAIEconomy.urgent(director, side), "Y7: with nothing to pay a rune with, the errand goes on")
	_rich(state, 2)
	check(ELFirstAIEconomy.urgent(director, side), "Y7: with resources, the hero goes for its runes")

func _case_y_turns() -> void:
	# A repair four ether from completion is kept although an active spell's
	# upkeep no longer fits the income (the settlement will drop that spell).
	if not smart: return
	var director := _world()
	var state := director.state
	var player := _repairer(state)
	var code := _spell_code(state, player, ELGlobalSpells.REPAIRS.keys())
	check(not code.is_empty(), "Y8: a repair spell for a computer player's colour")
	if code.is_empty(): return
	var hero := _hero(director, player, 30, 90, 1)
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	var dear := ""
	for candidate: String in ELGlobalSpells.ENCHANTMENTS:
		if dear.is_empty() or ELGlobalSpells.upkeep(profile, candidate) > ELGlobalSpells.upkeep(profile, dear): dear = candidate
	var upkeep := ELGlobalSpells.upkeep(profile, dear)
	var heroes := int(ELStrategy.mana_budget(state, player).spent)
	check(upkeep > heroes + 1, "Y8: a spell whose upkeep can outgrow the income (%s, %d)" % [dear, upkeep])
	if upkeep <= heroes + 1: return
	_tower_income(state, player, upkeep - 1)
	var record := ELGlobalSpells.data(state, player)
	record.production = {"code": code, "cost": 40, "spent": 36, "state": 1}
	record.active = [{"serial": 1, "code": dear, "hero": -1, "castle": player, "protection": 0}]
	check(ELFirstAIEconomy.turns_left(state, player) <= ELFirstAIEconomy.STALL_DAYS, "Y8: the forecast finishes it soon (%d days)" % ELFirstAIEconomy.turns_left(state, player))
	ELFirstAIEconomy.global_spells(director, player)
	check(str(record.production.get("code", "")) == code, "Y8: the repair is not dispelled (%s)" % str(record.production))

func _case_y_stock() -> void:
	# A shop's next level is worth a visit only for purchases that can happen.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	_rich(state, 2)
	_place(director, "portal", 20, 80)
	var found := {}
	for proto: Dictionary in protos.get("shops", []):
		var shop := _place(director, "shop", 36, 90, {"name": proto.name, "node": proto.node, "level": 0, "owner": 0})
		var stock := ELFirstSpellShop.authored_stock(profile, shop, ELFirstSpellShop.hero_color(profile, side))
		if stock.is_empty(): continue
		for slot in side.cards.size(): side.cards[slot] = stock[slot % stock.size()]
		ELRunes.initialize(profile, side)
		for slot in side.rune_uses.size():
			if int(side.rune_uses[slot]) >= 0: side.rune_uses[slot] = ELRunes.capacity(side)
		if ELFirstAIEconomy._shop(state, side, shop, false) == 0 and int(ELFirstAIEconomy._next_stock_helps(state, side, shop)) > 0:
			found = shop
			break
		_kill(director, shop)
		state.objects.erase(int(shop.uid))
	check(not found.is_empty(), "Y9: a shop whose next level sells this hero something")
	if found.is_empty(): return
	_rich(state, 2, 0)
	check(int(ELFirstAIEconomy._next_stock_helps(state, side, found)) == 0 and ELFirstAIEconomy.wants(director, side, found) == 0, "Y9: with nothing to pay, its next level is no reason to go")

func _case_y_restore() -> void:
	# A loaded game keeps the field commander (its shopping share), the alarm
	# and the doctrine.
	var director := _world()
	var state := director.state
	var lead := _hero(director, 2, 30, 90, 3)
	var other := _hero(director, 2, 34, 90, 5)
	var ai := ELFirstAI.data(state, 2)
	ai.champion = int(other.uid)
	ai.commander = int(lead.uid)
	ai.alarm = 3
	ai.doctrine = "economic"
	var share := ELFirstAIEconomy._budget(state, lead)
	check(ELFirstAI.restore(state).is_empty(), "Y10: the plans restore")
	ai = ELFirstAI.data(state, 2)
	check(int(ai.get("commander", -1)) == int(lead.uid) and int(ai.get("alarm", -1)) == 3 and str(ai.get("doctrine", "")) == "economic", "Y10: with the commander, alarm and doctrine (%s)" % str(ai))
	check(ELFirstAIEconomy._budget(state, lead) == share, "Y10: the commander's shopping budget is unchanged")

func _case_y_strength() -> void:
	# The strength estimate tells a specialized hero from the same hero without.
	var director := _world()
	var hero := _hero(director, 2, 30, 90, 3)
	var planner := _planner()
	hero.specialization = "NONE"
	var plain := float(planner.call("strength", director.state, hero))
	hero.specialization = "SPECIAL"
	check(float(planner.call("strength", director.state, hero)) > plain, "Y11: a specialization counts though the rest is cached")

func _case_y_sightings() -> void:
	# An enemy that falls out of sight is remembered where it was seen.
	if not smart: return
	var director := _world()
	var state := director.state
	_hero(director, 2, 30, 90, 3)
	var enemy := _hero(director, 3, 34, 90, 3)
	ELFog.refresh(state)
	var planner := _planner()
	planner.call("observe", director, 2)
	var key := str(enemy.uid)
	check(ELFirstAI.data(state, 2).get("seen", {}).has(key), "Y13: the enemy is seen")
	enemy.visible = false
	enemy.alive = false
	planner.call("observe", director, 2)
	check(ELFirstAI.data(state, 2).get("seen", {}).has(key), "Y13: its fall out of sight is not known (%s)" % str(ELFirstAI.data(state, 2).get("seen", {})))

func _case_y_loop() -> void:
	# Two repairs finished the same day are both cast.
	if not smart: return
	var director := _world()
	var state := director.state
	var player := _repairer(state)
	var code := _spell_code(state, player, ELGlobalSpells.REPAIRS.keys())
	check(not code.is_empty(), "Y14: a repair spell for a computer player's colour")
	if code.is_empty(): return
	var hero := _hero(director, player, 30, 90, 3)
	_rich(state, player)
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	var castle: Dictionary = state.scenario.castles[player]
	castle.max = maxi(int(castle.max), 30)
	castle.health = 7
	castle.pending = 9
	var cost := ELGlobalSpells.ether_cost(state, player, code)
	state.players[player].free_ether = 2 * cost
	var record := ELGlobalSpells.data(state, player)
	var serial := int(record.serial)
	ELFirstAIEconomy.global_spells(director, player)
	check(int(record.serial) - serial >= 2 and int(record.production.get("state", 0)) != 2, "Y14: a spell finished after a cast is cast too (%s costs %d: %d cast, production %s)" % [code, cost, int(record.serial) - serial, str(record.production)])

func _case_y_impending() -> void:
	# An enemy beside the castle will strike tonight: the ether that would
	# keep the castle standing is not spent on an attack.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	var code := ""
	for candidate: String in ELGlobalSpells.CASTLE_DAMAGE:
		if _spell_code(state, 2, [candidate]) == candidate and ELGlobalSpells.upkeep(profile, candidate) == 0: code = candidate
	if code.is_empty(): return
	var hero := _hero(director, 2, int(home.x) - 3, int(home.y), 3)
	_rich(state, 2)
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	var castle: Dictionary = state.scenario.castles[2]
	castle.health = 5
	castle.pending = 0
	var cost := ELGlobalSpells.ether_cost(state, 2, code)
	state.players[2].free_ether = maxi(cost, 6)
	var before := ELFirstAIEconomy.night_health(state, 2)
	var raider := _hero(director, 3, int(home.x) - 1, int(home.y) + 1, 5)
	ELFog.refresh(state)
	var after := ELFirstAIEconomy.night_health(state, 2)
	check(before - after == mini(before, ELFirstScenario.hero_value(raider)), "Y15: the raider's coming assault is foreseen (%d -> %d)" % [before, after])
	check(ELFirstAIEconomy._choose(director, 2) != code or ELFirstAIEconomy.night_health(state, 2, cost) > 0, "Y15: the ether that saves the castle is not spent on an attack")

func _case_y_route() -> void:
	# A weak creature behind a fortified enemy hero. The scout can go around
	# in the open, but a walled passage forces a battle it is likely to lose.
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	var creature := _place(director, "monster", 42, 90, {"owner": 0, "level": 1, "health": 4, "cards": ["CAFG"], "rune_uses": [4]})
	var enemy := _hero(director, 3, 36, 90, 3)
	ELFog.refresh(state)
	director.interception.rebuild(state, director.grid)
	var planner := _planner()
	var task := {"kind": "monster", "target": int(creature.uid)}
	var open := float(planner.call("utility", director, hero, 1, task, {}, true))
	enemy.spell_fort = 1
	director.interception.rebuild(state, director.grid)
	var detour := float(planner.call("utility", director, hero, 1, task, {}, true))
	check(detour > -INF and detour < open, "Y16: a safe detour makes the creature cost more time (%.1f -> %.1f)" % [open, detour])
	for x in range(27, 46):
		_wall(director, Vector2i(x, 88))
		_wall(director, Vector2i(x, 92))
	for y in range(89, 92):
		_wall(director, Vector2i(27, y))
		_wall(director, Vector2i(45, y))
	director.interception.rebuild(state, director.grid)
	var guarded := float(planner.call("utility", director, hero, 1, task, {}, true))
	check(open > -INF and guarded < open, "Y16: the battle on the way lowers the creature's worth (%.1f -> %s)" % [open, str(guarded)])
	check(guarded == -INF, "Y16: below waiting, it is left")

func _case_y_bounds() -> void:
	# The bound that prunes objectives is never below the exact worth: a
	# portal refilling three empty spells stays on the shortlist.
	if not smart: return
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 90, 3)
	_rich(state, 2)
	var colour := ELFirstSpellShop.hero_color(profile, side)
	var spells: Dictionary = profile.table("CombatSpells")
	var slot := 0
	for code: String in spells:
		if slot >= 3: break
		if spells[code].get("Color") == colour and spells[code].get("Rarity") == "Common":
			side.cards[slot] = code
			slot += 1
	ELRunes.initialize(profile, side)
	for index in side.rune_uses.size():
		if int(side.rune_uses[index]) >= 0: side.rune_uses[index] = 0
	_place(director, "portal", 36, 92)
	_place(director, "mine", 40, 96, {"owner": -1})
	_place(director, "monster", 26, 86, {"owner": 0, "level": 1})
	_place(director, "Teacher", 24, 96)
	if protos.has("shop"): _place(director, "shop", 34, 84, {"owner": 0})
	director.interception.rebuild(state, director.grid)
	_planner_set("_urgent", {})
	var planner := _planner()
	var bad: Array = []
	var priced := 0
	for task: Dictionary in ELFirstAI.objectives(director, 2):
		var bound := float(planner.call("utility", director, side, 1, task, {}, false))
		var exact := float(planner.call("utility", director, side, 1, task, {}, true))
		if exact == -INF: continue
		priced += 1
		if exact > bound + 1e-6: bad.append("%s %.1f > %.1f" % [task.kind, exact, bound])
	check(priced >= 3 and bad.is_empty(), "Y17: every exact worth is within its bound (%d priced; %s)" % [priced, str(bad)])

func _case_y_widen() -> void:
	# Five supporters, four mines near them and one far: all five get a mine.
	if not smart: return
	var director := _world()
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var sides: Array[Dictionary] = []
	for at: Vector2i in [Vector2i(30, 90), Vector2i(31, 90), Vector2i(30, 91), Vector2i(31, 91), Vector2i(32, 90)]: sides.append(_hero(director, 2, at.x, at.y, 2))
	for at: Vector2i in [Vector2i(36, 90), Vector2i(36, 94), Vector2i(36, 86), Vector2i(40, 90), Vector2i(76, 60)]: _place(director, "mine", at.x, at.y, {"owner": -1})
	_pass(director)
	var mines := {}
	for hero: Dictionary in sides:
		var task := _task_of(director, hero)
		if task.get("kind") == "mine": mines[int(task.target)] = true
	check(mines.size() == 5, "Y18: each of the five supporters takes its own mine (%d)" % mines.size())

func _case_y_body() -> void:
	# A guard standing in the one-cell gap to a mine: the lookahead knows the
	# gap is open once the guard is beaten.
	if not smart: return
	var director := _world()
	var lead := _hero(director, 2, 30, 60, 5)
	lead.health = 26
	var mine := _place(director, "mine", 50, 60, {"owner": -1})
	var gap := Vector2i(int(mine.x) - 2, int(mine.y))
	_pen(director, mine, 2, [gap])
	var guard := _place(director, "monster", gap.x, gap.y, {"owner": 0, "level": 1, "health": 4, "cards": ["CAFG"], "rune_uses": [4]})
	_place(director, "Teacher", 12, 60)
	director.interception.rebuild(director.state, director.grid)
	_pass(director)
	check(int(_task_of(director, lead).get("target", -1)) == int(guard.uid), "Y20: the guard in the gap is cleared first (%s)" % str(_task_of(director, lead)))

func _case_y_leg() -> void:
	# The two open cells beside a target nearest the hero lie in a sealed
	# pocket: the lookahead's leg goes round to the far side.
	if not smart: return
	var director := _world()
	var grid := director.grid
	var sealed: Array[Vector2i] = [Vector2i(48, 58), Vector2i(49, 58), Vector2i(50, 58), Vector2i(48, 59), Vector2i(50, 59), Vector2i(48, 60), Vector2i(50, 60), Vector2i(48, 61), Vector2i(49, 61), Vector2i(50, 61)]
	for cell: Vector2i in sealed: grid.land.set_point_solid(cell, true)
	_planner_set("_legs", 0)
	_planner_set("_leg_cache", {})
	var leg: Array = _planner().call("_leg", director, Vector2i(40, 60), Rect2i(50, 60, 1, 1), 2.0)
	for cell: Vector2i in sealed: grid._update_cell(cell)
	check(float(leg[0]) > 0.0 and leg[1].x == 51, "Y21: the leg reaches the open side (%s)" % str(leg))

func _case_y_resolver() -> void:
	# The estimated resolver wins as often as the estimate says.
	if not smart: return
	var director := _world()
	var state := director.state
	var first := _hero(director, 2, 30, 90, 3)
	var second := _hero(director, 3, 32, 90, 3)
	var chance := ELFirstAIPlanner.estimate(state, first, second)
	var wins := 0
	var trials := 20000
	for trial in trials:
		if ELFirstAI.winner(state, first, second, true) == first: wins += 1
	var share := float(wins) / trials
	check(absf(share - chance) < 0.015, "Y23: the first side wins %.3f of estimated battles, as estimated (%.3f)" % [share, chance])

func _case_y_mark() -> void:
	# Free movement: collecting an artifact is progress (the faction plans again).
	var director := _world(true)
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 3)
	var item := _pickup(director, 31, 90, "artefacts", "")
	var before := ELStrategy._free_mark(state, 2)
	if not hero.has("artifacts"): hero.artifacts = []
	hero.artifacts.append(str(item.get("name", "artifact")))
	item.alive = false
	check(ELStrategy._free_mark(state, 2) != before, "Y24: a taken artifact changes the round's fingerprint")

func _case_y_buffs() -> void:
	# No Concentration for a commander that has the skill.
	if not smart: return
	var director := _world()
	var state := director.state
	var lead := _hero(director, 2, 30, 90, 5)
	ELFirstAI.data(state, 2).commander = int(lead.uid)
	lead.skills.erase("CONC")
	var without := ELFirstAIEconomy._score(director, 2, "CNTR")
	lead.skills["CONC"] = 0
	check(without > 0.0 and ELFirstAIEconomy._score(director, 2, "CNTR") == 0.0, "Y25: Concentration only for a commander without the skill (%.0f)" % without)

func _case_y_summon() -> void:
	# No summons while every tile before the castle is taken: the finished
	# spell waits instead of being used up with no hero.
	if not smart: return
	var director := _world()
	var state := director.state
	_hero(director, 2, 30, 90, 3)
	for attempt in 8:
		var spot := ELGlobalSpells.castle_spot(state, 2)
		if spot == ELGlobalSpells.NO_SPOT: break
		_place(director, "monster", spot.x, spot.y, {"owner": 0, "level": 1})
	check(ELGlobalSpells.castle_spot(state, 2) == ELGlobalSpells.NO_SPOT, "Y26: the castle's front is full")
	var code := str(ELFirstAIEconomy.SUMMON_PREFIX.get(str(state.players[2].color), "")) + "WR"
	check(ELFirstAIEconomy._score(director, 2, code) == 0.0, "Y26: a summons is not begun")
	var record := ELGlobalSpells.data(state, 2)
	record.production = {"code": code, "cost": 10, "spent": 10, "state": 2}
	var heroes := ELFirstAI.heroes_of(state, 2).size()
	check(not ELFirstAIEconomy._cast(director, 2) and str(record.production.get("code", "")) == code and ELFirstAI.heroes_of(state, 2).size() == heroes, "Y26: a finished one waits for room")

func _case_y_combats() -> void:
	# An ethereal battle's mark is no actor id.
	var director := _world()
	var state := director.state
	director.strategy = {"phase": "combat", "actors": [], "index": 0, "combats": [[5, 7, 1]], "legacy_orders": false}
	ELStrategy.queue_combat(director, 1, 5)
	check(director.strategy.combats.size() == 2, "Y27: a battle of actors 1 and 5 is queued beside the ethereal 5 and 7")
	for id: int in [1, 5, 7]:
		if not state.objects.has(id): state.objects[id] = {"uid": id, "type": "monster", "owner": 0, "alive": true}
		check(state.object(id).get("type") in ["hero", "monster"], "Y27: actor %d stands for a fighter" % id)
	var turn := ELStrategy.restore_turn({"phase": "combat", "actors": [], "index": 0, "combats": [[5, 7, 1], [1, 5]], "legacy_orders": false}, state)
	check(not turn.has("error"), "Y27: and such a turn loads (%s)" % str(turn.get("error", "")))
	director.strategy = {}

func _case_y_hire() -> void:
	# Hiring for resources only when the ether does not reach a summoning spell.
	if not smart: return
	var director := _world()
	var state := director.state
	var hero := _hero(director, 2, 30, 90, 5)
	ELFirstAI.data(state, 2).champion = int(hero.uid)
	_rich(state, 2)
	var code := _spell_code(state, 2, [str(ELFirstAIEconomy.SUMMON_PREFIX.get(str(state.players[2].color), "")) + "WR"])
	check(not code.is_empty(), "Y28: a summoning spell of this colour")
	if code.is_empty(): return
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": [code]}]
	state.players[2].free_ether = ELGlobalSpells.ether_cost(state, 2, code)
	var heroes := ELFirstAI.heroes_of(state, 2).size()
	ELFirstAIEconomy.reinforce(director, 2)
	check(ELFirstAI.heroes_of(state, 2).size() == heroes, "Y28: with the ether for a summoning spell no hero is hired")
	state.players[2].free_ether = 0
	_tower_income(state, 2, 0)
	ELFirstAIEconomy.reinforce(director, 2)
	check(ELFirstAI.heroes_of(state, 2).size() == heroes + 1, "Y28: without the ether for one, a hero is hired")

# --- S: saved plans -------------------------------------------------------------

func _case_s_saved() -> void:
	# Plans, assignment progress and route rules survive a save (JSON numbers
	# come back as floats).
	var director := _world()
	var state := director.state
	var home := _castle(director, 2)
	_hero(director, 2, int(home.x) - 6, int(home.y), 7)
	var side := _hero(director, 2, 30, 60, 2)
	_place(director, "mine", 52, 60, {"owner": -1})
	_place(director, "Teacher", 34, 64)
	_pass(director)
	_pass(director)
	var before: Dictionary = ELFirstAI.data(state, 2).duplicate(true)
	state.players[2].ai = JSON.parse_string(JSON.stringify(before))
	check(ELFirstAI.restore(state).is_empty(), "S: saved plans restore")
	check(ELFirstAI.data(state, 2).assigned.size() == before.assigned.size(), "S: the assignments come back")
	var order: Dictionary = JSON.parse_string(JSON.stringify(side.strategy_order))
	var copy := side.duplicate(true)
	copy.strategy_order = order
	check(ELStrategy.restore(profile, copy, state.map), "S: an order with its route rules restores")
	check(copy.strategy_order.get("route", {}).hash() == side.strategy_order.get("route", {}).hash(), "S: the route rules are kept (%s)" % str(copy.strategy_order.get("route")))

# --- G, I: second-game movement and fog ---------------------------------------

func _second_cases(second: ELProfile) -> void:
	var catalog := ELSingleScenario.catalog(second)
	var director: ELAdventureDirector = null
	for entry: Dictionary in catalog:
		var map := ELAdventureMap.new()
		if not map.load_map(second, str(entry.id)): continue
		var state := ELAdventureSession.new()
		if not state.start(map, 1, 212, str(entry.get("script", "")), 1, false): continue
		director = ELAdventureDirector.new()
		if not director.build(state):
			director = null
			continue
		director.fast_mode = true
		break
	check(director != null, "G: a second-game map starts")
	if director == null: return
	var state := director.state
	# A guard with open ground beside it.
	var guard := {}
	var step := Vector2i.ZERO
	for item: Dictionary in state.objects.values():
		if not ELInterception.second_guard(item) or item.get("type") != "monster" or not director.interception.zones.has(int(item.uid)): continue
		for direction: Vector2i in ELInterception.DIRECTIONS:
			var to := Vector2i(item.x, item.y) + direction
			if director.grid.passability(to) >= 0:
				guard = item
				step = to
				break
		if not guard.is_empty(): break
	check(not guard.is_empty(), "G: the map has a guard that can step")
	if not guard.is_empty():
		director._begin_move(guard, step, false)
		_drive(director)
		check(Vector2i(guard.x, guard.y) == step, "G: the guard stepped")
		var live: Dictionary = director.interception.zones.get(int(guard.uid), {})
		var fresh := ELInterception.new()
		fresh.rebuild(state, director.grid)
		var rebuilt: Dictionary = fresh.zones.get(int(guard.uid), {})
		check(live.get("origin") == step, "G: the moving guard's area follows it (%s)" % str(live.get("origin")))
		check(live.get("cells", []).size() == rebuilt.get("cells", []).size() and live.get("origin") == rebuilt.get("origin"), "G: the live area matches a rebuilt one")
	# Two heroes of the first player; the second steps onto the first one's
	# destination after its route is made.
	var walker := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and int(item.get("owner", -1)) == 1 and item.alive and item.visible:
			walker = item
			break
	check(not walker.is_empty(), "G: the map has a hero of the first player")
	if walker.is_empty(): return
	var goal := Vector2i(-1, -1)
	for distance in range(3, 7):
		for direction: Vector2i in ELInterception.DIRECTIONS:
			var to := Vector2i(walker.x, walker.y) + direction * distance
			var path := director.grid.path(Vector2i(walker.x, walker.y), to)
			if path.size() < 3: continue
			var safe := true
			for point: Vector2i in path:
				if director.interception.cells.has(point): safe = false
			if safe:
				goal = to
				break
		if goal.x >= 0: break
	check(goal.x >= 0, "G: there is open, unguarded ground near the hero")
	if goal.x < 0: return
	var other: Dictionary = walker.duplicate(true)
	other.uid = state._next_object
	state._next_object += 1
	other.x = 0
	other.y = 0
	other.visible = false
	state.objects[int(other.uid)] = other
	var start := Vector2i(walker.x, walker.y)
	director._begin_move(walker, goal, false)
	_take(director, other, goal)
	var before := int(state.fog.get("refreshes", 0))
	var steps := _drive(director, walker)
	check(Vector2i(walker.x, walker.y) != Vector2i(other.x, other.y), "G: a hero does not walk onto a tile taken after its route was made")
	var refreshes := int(state.fog.get("refreshes", -1)) - before
	check(steps > 0 and refreshes == steps, "I: one fog refresh per step (%d refreshes, %d steps)" % [refreshes, steps])
	# A scripted move meets the same taken tile: the hero stops short and the
	# command still completes, so the queue goes on.
	_take(director, other, Vector2i(0, 0), false)
	walker.x = start.x
	walker.y = start.y
	director.grid.update_actor(walker)
	state.commands.clear()
	var command := {"kind": "Moving", "arguments": [walker.uid, goal.x, goal.y]}
	state.commands.append(command)
	director._running = command
	director._begin_move(walker, goal, true)
	_take(director, other, goal)
	_drive(director, walker)
	check(Vector2i(walker.x, walker.y) != Vector2i(other.x, other.y), "G: a scripted move does not walk onto a taken tile either")
	check(state.commands.is_empty(), "G: the scripted move still completes its command")

## Puts `actor` on `tile` (shown) or takes it off the map.
func _take(director: ELAdventureDirector, actor: Dictionary, tile: Vector2i, shown := true) -> void:
	actor.visible = shown
	actor.x = tile.x
	actor.y = tile.y
	director.grid.update_actor(actor)

## Runs the current move to its end; returns the tiles `actor` entered.
func _drive(director: ELAdventureDirector, actor := {}) -> int:
	var steps := 0
	var at := Vector2i(int(actor.get("x", 0)), int(actor.get("y", 0)))
	for step in 2000:
		if director.movement.is_empty() or not director.error.is_empty(): break
		director._advance_movement(0.02)
		if not actor.is_empty() and Vector2i(actor.x, actor.y) != at:
			at = Vector2i(actor.x, actor.y)
			steps += 1
	return steps
