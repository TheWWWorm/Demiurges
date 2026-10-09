class_name ELAdventureDirector
extends RefCounted
## Advances the original command queue and tile movement independently of UI.
signal presentation(data: Dictionary)
var state: ELAdventureSession
var grid: ELAdventureGrid
var dialogue: Dictionary = {}
## Direct script message boxes waiting for the current dialogue to close.
var boxes: Array[Dictionary] = []
## Script waits on the mission's action list, in seconds.
var action_wait := 0.0
var movement: Dictionary = {}
var strategy: Dictionary = {}
var interception := ELInterception.new()
## Second game: completed player rounds (Hook_EndOfTurn's argument; saved).
var player_round := 0
var _woken := -1
## Options "fast adventure mode": map movement at four times the normal speed.
var fast_mode := false
var wait_remaining := 0.0
var error := ""
var notice := ""
## Why the last battle could not be prepared (diagnostics only; the player
## sees BATTLE_REFUSED). The original starts every battle it is asked to.
var battle_refusal := ""
const BATTLE_REFUSED := "This battle cannot be fought in the remake yet."
var encounter: ELAdventureEncounter
var shop: ELSpellShop
var rune_shop: ELRuneShop
var first_shop: ELFirstSpellShop
var _clock := 0.0
var _waiting := false
## Script commands were pending; the original calls Hook_AllCommandsFinished
## once the queue drains (EL2 command processor).
var _commands_pending := false
## The command being executed (by reference); null after a load.
var _running: Variant = null

func build(session: ELAdventureSession) -> bool:
	state = session
	grid = ELAdventureGrid.new()
	if not grid.build(state.map, state.objects): return _fail(grid.error)
	state.grid = grid
	state.interception = interception
	# ExIsDesktopModalChild; the adventure view adds its own windows.
	state.desktop_modal = func() -> bool: return not dialogue.is_empty() or _shopping()
	interception.rebuild(state, grid)
	if not state.event.is_connected(_world_changed): state.event.connect(_world_changed)
	return true

## Opens an EL1 spell shop or component portal; Remote Use passes `remote`,
## which leaves the shop's owner unchanged.
func open_first_shop(hero_id: int, target_id: int, remote := false) -> void:
	if state.object(target_id).get("type") == "el1_spell_shop":
		var next := ELFirstSpellShop.new()
		if not next.open(state, hero_id, target_id, remote):
			presentation.emit({"kind": "notice", "text": next.error})
			return
		first_shop = next
		presentation.emit({"kind": "el1_spell_shop", "hero": hero_id, "shop": target_id})
	else:
		var next := ELRuneShop.new()
		if not next.open(state, hero_id, target_id, remote):
			presentation.emit({"kind": "notice", "text": next.error})
			return
		rune_shop = next
		presentation.emit({"kind": "rune_shop", "hero": hero_id, "shop": target_id})

func _world_changed(data: Dictionary) -> void:
	if data.kind == "message_box":
		boxes.append(data)
		_show_box()
		return
	if data.kind == "script_notice":
		presentation.emit({"kind": "notice", "text": str(data.text)})
		return
	if data.kind == "script_wait":
		# Waits run on the mission's action list at 15 ticks per second.
		action_wait += float(data.ticks) / 15.0
		return
	if data.kind == "orient_to_point":
		var turned := state.object(data.id)
		presentation.emit({"kind": "orient", "id": int(data.id), "direction": Vector2(float(data.x) / 2.0 - 0.5 - turned.get("x", 0), float(data.y) / 2.0 - 0.5 - turned.get("y", 0))})
		return
	if data.kind == "remote_use":
		# Only the local caster sees the screen (the computer never casts).
		if int(data.player) == state.current_player: open_first_shop(data.hero, data.shop, true)
		return
	if data.kind == "hero_placed":
		# A hero set down inside a hostile zone cannot move on that night.
		var placed := state.object(data.id)
		grid.update_actor(placed)
		interception.rebuild(state, grid)
		# Second game: only player 1's heroes get the stop flag.
		var stoppable: bool = state.map.profile.id != "el2" or placed.get("type") == "hero" and int(placed.get("owner", -1)) == 1
		if stoppable and not interception.enemies(state, placed, Vector2i(placed.x, placed.y)).is_empty(): placed.intercepted = true
		return
	if data.kind == "object_killed" and ELGlobalSpells.applies(state) and state.object(data.id).get("type") == "hero": ELGlobalSpells.hero_died(state, state.object(data.id))
	# Second game: a fallen hero's keys return to their warding stones.
	if data.kind == "object_killed" and ELSecondGates.applies(state) and state.object(data.id).get("type") == "hero": ELSecondGates.drop_keys(state, state.object(data.id))
	if data.kind not in ["object_changed", "object_killed", "object_created", "shape_changed"]: return
	var actor := state.object(data.id)
	if actor.get("type") in ["hero", "monster"]:
		# Removing a garrison first leaves its fort; the fort keeps its owner.
		if data.kind == "object_killed" and actor.get("fortified", false): ELForts.leave(state, actor.uid, false)
		# A hero lost inside a training camp frees it.
		if data.kind == "object_killed" and int(actor.get("camp", -1)) >= 0: ELAdditionalBuildings.release_camp(state, actor)
		grid.update_actor(actor)
		if interception.zones.has(int(data.id)) or ELInterception.guards(actor) or actor.get("fortified", false) or ELInterception.spell_fort(actor) or state.map.profile.id == "el2" and ELInterception.second_guard(actor): interception.rebuild(state, grid)
	else:
		grid.rebuild(state.objects)
		interception.rebuild(state, grid)

## Second game: a script end of turn passes the turn to each later living
## player in index order (each gets only Hook_Wake, then ends); after the last
## the round counter grows, Hook_EndOfTurn(round) runs and player 1 resumes.
## The travel day, income and the date are untouched.
func end_player_turn() -> void:
	for actor: Dictionary in state.objects.values():
		if int(actor.get("owner", -1)) == state.current_player and actor.get("intercepted", false): actor.intercepted = false
	var next := -1
	var ids := state.players.keys()
	ids.sort()
	for id: Variant in ids:
		if int(id) > state.current_player and _player_alive(int(id)):
			next = int(id)
			break
	_woken = -1
	if next >= 0:
		state.current_player = next
	else:
		player_round += 1
		state.current_player = 1
		if not state.hook("Hook_EndOfTurn", [float(player_round)]): _fail(state.error)
	if ELFog.applies(state): ELFog.refresh(state)

func _player_alive(player: int) -> bool:
	for actor: Dictionary in state.objects.values():
		if actor.get("type") in ["hero", "monster"] and actor.get("alive", false) and int(actor.get("owner", -1)) == player: return true
	return false

func _busy(player: int) -> bool:
	for actor: Dictionary in state.objects.values():
		if int(actor.get("owner", -1)) == player and actor.get("alive", false) and not actor.get("orders", []).is_empty(): return true
	return false

func advance(delta: float) -> void:
	if not error.is_empty() or not state.outcome.is_empty() or encounter != null or _shopping(): return
	if not dialogue.is_empty(): return
	if not movement.is_empty(): _advance_movement(delta)
	if encounter != null or _shopping(): return
	if not strategy.is_empty():
		ELStrategy.advance(self)
		return
	if action_wait > 0.0:
		action_wait = maxf(0.0, action_wait - delta)
		return
	if _waiting:
		wait_remaining -= delta
		if wait_remaining > 0: return
		_waiting = false
		_finish_command()
	_clock += delta
	# The second game's mission update runs 15 times per second (
	# ExWaitCmd and the tutorial's "150 segments = 10 sec").
	if _clock >= (1.0 / 15.0 if state.map.profile.id == "el2" else 0.1):
		_clock = 0.0
		var wake := movement.is_empty() and not _busy(state.current_player)
		if not state.step(wake):
			_fail(state.error)
			return
		if wake: _woken = state.current_player
	if not movement.is_empty(): return
	for budget in 32:
		if not state.commands.is_empty(): _commands_pending = true
		if state.commands.is_empty() or not dialogue.is_empty() or not movement.is_empty() or _waiting or not error.is_empty() or encounter != null or _shopping(): break
		_execute(state.commands[0])
	if _commands_pending and state.commands.is_empty() and movement.is_empty() and not _waiting and dialogue.is_empty() and error.is_empty() and encounter == null:
		_commands_pending = false
		if not state.hook("Hook_AllCommandsFinished"): _fail(state.error)
	# A computer player's commander, once woken with no hero busy, queues its end
	# of turn at once; script commands run on their own queue.
	if state.map.profile.id == "el2" and state.current_player != 1 and _woken == state.current_player and error.is_empty() and encounter == null and not _busy(state.current_player):
		end_player_turn()

func acknowledge(answer := "OK") -> bool:
	if dialogue.is_empty(): return false
	var direct: bool = dialogue.get("direct", false)
	var hook: bool = dialogue.get("hook", true)
	dialogue.clear()
	if not direct: _finish_command()
	presentation.emit({"kind": "dialogue_closed"})
	# Queued Text and Question boxes and direct boxes report their answer
	# (the direct action box does not).
	if hook and not state.hook("Hook_OnCloseMessageBox", [answer]): return _fail(state.error)
	_show_box()
	return true

## Shows the next direct script box once no other dialogue is open.
func _show_box() -> void:
	if not dialogue.is_empty() or boxes.is_empty(): return
	var box: Dictionary = boxes.pop_front()
	var speaker := state.object(box.speaker)
	dialogue = {"actor": int(box.speaker), "title": speaker.get("title", speaker.get("name", "")), "text_id": "", "text": str(box.text),
		"question": bool(box.question), "arguments": [], "direct": true, "hook": bool(box.hook),
		"box": str(box.get("box", "text")), "speaker_box": bool(box.get("speaker_box", false))}
	if box.has("offset"): dialogue.offset = box.offset
	presentation.emit({"kind": "dialogue", "dialogue": dialogue})

func can_move() -> bool:
	# Second game: the local player waits while other players take their turn.
	if state.map.profile.id == "el2" and state.current_player != 1: return false
	return error.is_empty() and state.outcome.is_empty() and dialogue.is_empty() and state.commands.is_empty() and not state.exclusive and encounter == null and not _shopping() and strategy.is_empty()

## Hook_OnHeroCommandRun: a missing hook or a script error lets the
## order run; otherwise the native boolean of the result (nil and 0 false).
func _command_run_vetoed(actor: Dictionary) -> bool:
	if state.vm == null or not state.vm.has_function("Hook_OnHeroCommandRun"): return false
	var result := state.vm.invoke("Hook_OnHeroCommandRun", [float(actor.uid)])
	if not state.vm.error.is_empty():
		push_warning("Hook_OnHeroCommandRun: " + state.vm.error)
		state.vm.error = ""
		return false
	return not result.is_empty() and ELAdventureSession._truthy_flag(result[0])

func _shopping() -> bool:
	return shop != null or rune_shop != null or first_shop != null

## A hero at a mine or ether node of another player captures it (the first
## game plans the walk first). An own site does nothing and opens no window:
## the originals have none; the capture shows its message box.
func inspect_site(hero_id: int, site_id: int) -> bool:
	if not can_move() or not movement.is_empty(): return false
	var site := state.object(site_id)
	var owned: bool = not site.is_empty() and site.owner == state.current_player
	if owned: return false
	notice = ELResourceSites.visit_problem(state, hero_id, site_id, true)
	if not notice.is_empty():
		presentation.emit({"kind": "notice", "text": notice})
		return false
	if state.map.profile.id == "el1": return request_move(hero_id, Vector2i(site.x, site.y), site_id)
	if not ELResourceSites.capture(state, hero_id, site_id): return false
	if state.map.profile.id == "el2": ELAdventureClock.use_points(state, state.object(hero_id), 2)
	return true

func end_day() -> bool:
	if not can_move() or not movement.is_empty():
		notice = "Finish the current action before waiting for the next day."
		return false
	notice = ""
	if state.map.profile.id == "el1": return ELStrategy.begin(self)
	# The original calls the hook for its effects and discards its result. The
	# second game calls it only when a player round ends (end_player_turn).
	if state.map.profile.id != "el2" and state.vm != null and state.vm.has_function("Hook_EndOfTurn"):
		state.vm.invoke("Hook_EndOfTurn", [float(state.current_player)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
	# The placement stop flag lasts until that player's turn boundary.
	for actor: Dictionary in state.objects.values():
		if int(actor.get("owner", -1)) == state.current_player and actor.get("intercepted", false): actor.intercepted = false
	return ELAdventureClock.end_player_day(state, state.current_player)

func request_move(id: int, destination: Vector2i, use_id := -1) -> bool:
	if not can_move():
		notice = "Finish the current conversation first."
		return false
	var actor := state.object(id)
	if actor.is_empty() or actor.owner != state.current_player or not actor.alive: return false
	notice = ""
	if state.map.profile.id == "el1": return ELStrategy.plan(self, actor, destination, use_id)
	if actor.get("fortified", false):
		# Second game: a garrison cannot step; using its own fort
		# again is how it leaves.
		if use_id >= 0 and use_id == int(actor.get("fort", -1)):
			use_object(id, use_id)
			return true
		notice = "Use the fort again to leave it."
		return false
	# EL2: the local player may only target a tile it sees now; the route
	# itself is not limited by fog.
	if not ELFog.targetable(state, state.current_player, destination):
		notice = "That place is not in sight."
		return false
	return _begin_move(actor, destination, false, use_id)

## The hero panel's leave control: a fort garrison or a training-camp guest
## returns to the tile it entered from, immediately.
func leave_fort(id: int) -> bool:
	var actor := state.object(id)
	if state.map.profile.id != "el1" or not can_move() or not movement.is_empty() or actor.is_empty() or actor.owner != state.current_player: return false
	if int(actor.get("camp", -1)) >= 0:
		var camp := state.object(actor.camp)
		if not ELAdditionalBuildings.leave_camp(state, id): return false
		notice = ""
		presentation.emit({"kind": "notice", "text": "%s left the %s." % [actor.get("title", actor.name), ELAdditionalBuildings.title(state.map.profile, camp).to_lower()]})
		return true
	if not ELForts.leave(state, id): return false
	notice = ""
	presentation.emit({"kind": "notice", "text": "%s left the fort." % actor.get("title", actor.name)})
	return true

func upgrade_fort(id: int) -> bool:
	if state.map.profile.id != "el1" or not can_move() or not movement.is_empty(): return false
	notice = ELForts.upgrade_problem(state, id)
	if not notice.is_empty(): return false
	return ELForts.upgrade(state, id)

func cancel_order(id: int) -> bool:
	var actor := state.object(id)
	if state.map.profile.id != "el1" or not can_move() or actor.is_empty() or actor.owner != state.current_player: return false
	actor.strategy_order = {}
	notice = ""
	presentation.emit({"kind": "route", "id": id, "path": []})
	presentation.emit({"kind": "notice", "text": notice})
	return true

func _begin_move(actor: Dictionary, destination: Vector2i, queued: bool, use_id := -1, use_at_end := true) -> bool:
	# Second game: Hook_OnHeroCommandRun(hero) as the order executes (
	# ), for player clicks and scripted moves alike; a true result
	# discards the order and the hero stays put.
	if state.map.profile.id == "el2" and _command_run_vetoed(actor):
		if queued: _finish_command()
		return queued
	var from := Vector2i(actor.x, actor.y)
	# Second game: routes avoid hostile guard zones where they can.
	var avoid := interception.hostile_cells(state, actor) if state.map.profile.id == "el2" else ([] as Array[Vector2i])
	var path := grid.approach(from, state.object(use_id), actor.get("ship", false), avoid) if use_id >= 0 else grid.path(from, destination, actor.get("ship", false), avoid)
	if path.is_empty():
		notice = "No route to that location."
		if queued:
			# Second game: a scripted move without a route completes at once and
			# the hero stays put; the queue carries on.
			if state.map.profile.id == "el2":
				notice = ""
				_finish_command()
				return true
			return _fail("The scenario could not find a route for %s to %s." % [actor.name, destination])
		return false
	if not movement.is_empty(): state.object(movement.id).orders.clear()
	movement = {"id": actor.uid, "path": path, "index": 0, "progress": 0.0, "queued": queued, "use": use_id if use_at_end else -1}
	actor.orders.assign(["move"])
	presentation.emit({"kind": "route", "id": actor.uid, "path": path})
	if path.size() == 1: _complete_movement()
	return true

func _advance_movement(delta: float) -> void:
	var actor := state.object(movement.id)
	if actor.is_empty() or not actor.alive or actor.orders.is_empty():
		_complete_movement(false)
		return
	var travel := delta * (16.0 if fast_mode else 4.0)
	for budget in 64:
		var index: int = movement.index
		var from := Vector2(movement.path[index])
		var to := Vector2(movement.path[index + 1])
		var cost := grid.passability(Vector2i(to), actor.get("ship", false))
		if movement.get("strategic", false) and not interception.can_step(state, grid, actor, Vector2i(to)):
			_complete_movement(false)
			return
		var distance := from.distance_to(to)
		var remaining: float = distance * (1.0 - movement.progress)
		# EL1: a step the local player cannot see on either tile takes no time.
		if movement.get("strategic", false) and not ELFog.visible(state, state.current_player, Vector2i(from)) and not ELFog.visible(state, state.current_player, Vector2i(to)): travel = maxf(travel, remaining)
		if travel < remaining:
			movement.progress += travel / distance
			presentation.emit({"kind": "actor_moving", "id": actor.uid, "position": from.lerp(to, movement.progress), "moving": true})
			return
		travel -= remaining
		movement.progress = 0.0
		movement.index += 1
		actor.x = int(to.x)
		actor.y = int(to.y)
		grid.update_actor(actor)
		if state.map.profile.id == "el2":
			# Each step refreshes the owner's sight.
			ELFog.moved(state, actor)
			ELAdventureClock.use_points(state, actor, 1)
		elif movement.get("strategic", false):
			actor.ap -= cost
			ELStrategy.entered(self, actor)
		presentation.emit({"kind": "actor_moving", "id": actor.uid, "position": to, "moving": true})
		if actor.get("intercepted", false) or int(movement.index) >= movement.path.size() - 1:
			_complete_movement()
			return

func _complete_movement(use := true) -> void:
	if movement.is_empty(): return
	var finished := movement
	movement = {}
	var actor := state.object(finished.id)
	if not actor.is_empty():
		actor.orders.clear()
		if finished.get("strategic", false):
			ELStrategy.after_movement(self, actor)
			var order: Dictionary = actor.get("strategy_order", {})
			if not order.is_empty() and order.use < 0 and Vector2i(actor.x, actor.y) == Vector2i(order.destination[0], order.destination[1]): actor.strategy_order = {}
		presentation.emit({"kind": "actor_moving", "id": actor.uid, "position": Vector2(actor.x, actor.y), "moving": false})
	if finished.queued: _finish_command()
	if use and int(finished.use) >= 0: use_object(int(finished.id), int(finished.use))

func use_object(hero_id: int, target_id: int, defender := -1) -> void:
	var actor := state.object(hero_id)
	var target := state.object(target_id)
	# A lair's creature waits off the map; its battle is still fought.
	if actor.is_empty() or target.is_empty() or not target.alive or not (target.visible or target.has("dungeon")) or not target.enabled or encounter != null or _shopping(): return
	if state.vm != null:
		var result := state.vm.invoke("Hook_OnPreUse", [float(target_id), float(hero_id)])
		if not state.vm.error.is_empty():
			_fail(state.vm.error)
			return
		if not result.is_empty() and result[0] == null: return
	if target.type in ["hero", "monster"] and state.hostile(actor, target):
		var next := ELAdventureEncounter.new()
		if not next.prepare(state, hero_id, target_id, defender):
			_refuse_battle(next.error)
			return
		encounter = next
		if not next.unsupported_artifacts.is_empty() and state.current_player in [int(actor.owner), int(target.owner)]:
			var names: Array[String] = []
			for name: String in next.unsupported_artifacts: names.append(ELMapPickups.artifact_title(state.map.profile, name))
			notice = "Not usable in battle yet: " + ", ".join(names)
			presentation.emit({"kind": "notice", "text": notice})
		if next.scripted_winner >= 0 or next.auto:
			finish_encounter()
			return
		presentation.emit({"kind": "encounter", "hero": hero_id, "opponent": target_id})
	else:
		if ELResourceSites.TYPES.has(target.group):
			inspect_site(hero_id, target_id)
		elif target.type == "fort" and state.map.profile.id == "el2" and int(actor.get("fort", -1)) == target_id:
			ELForts.leave(state, hero_id)
		elif target.type == "fort":
			var problem := ELForts.enter_problem(state, hero_id, target_id)
			if not problem.is_empty() or not ELStrategy.adjacent(self, actor, target):
				if actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": problem if not problem.is_empty() else "Move next to this fort first."})
				return
			ELForts.enter(state, hero_id, target_id)
		elif target.group == "resource_cuts":
			if not state.collect_resources(hero_id, target_id): presentation.emit({"kind": "notice", "text": state.error})
		elif target.type in ["el1_spell_shop", "rune_shop"]: open_first_shop(hero_id, target_id)
		elif target.type == "spell_shop":
			var next := ELSpellShop.new()
			if not next.open(state, hero_id, target_id):
				presentation.emit({"kind": "notice", "text": next.error})
				return
			shop = next
			presentation.emit({"kind": "spell_shop", "hero": hero_id, "shop": target_id})
			# Hook_OnDialogOpen("SpellShop") once the screen is up; its
			# result is ignored.
			if not state.hook("Hook_OnDialogOpen", ["SpellShop"]): _fail(state.error)
		elif ELMapPickups.is_pickup(target) and (state.map.profile.id == "el1" or target.group == "artefacts"): ELMapPickups.take(self, actor, target)
		elif state.map.profile.id == "el1" and ELAdditionalBuildings.supported(target): ELAdditionalBuildings.visit(self, actor, target)
		elif target.type == "townbunker" and state.map.profile.id == "el1": ELFirstScenario.town_bunker(self, actor)
		elif ELSecondGates.applies(state) and (ELSecondGates.is_gate(target) or ELSecondGates.is_warding(target)):
			if ELStrategy.adjacent(self, actor, target): ELSecondGates.use(self, actor, target)
			elif actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
		elif ELSecondGates.applies(state) and target.group == "additional_buildings" and target.name == ELFog.EL2_LAKE:
			if ELStrategy.adjacent(self, actor, target): _lake(actor, target)
			elif actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
		elif ELSecondArtifacts.applies(state.map.profile) and ELSecondArtifacts.is_building(target): ELSecondArtifacts.visit(self, actor, target)
		elif ELSecondGates.applies(state) and not ELBattlegrounds.affect(state, target).is_empty():
			if not ELStrategy.adjacent(self, actor, target):
				if actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
			elif not ELBattlegrounds.use(self, actor, target) and actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "This building cannot be used now."})
		elif ELSecondBuildings.applies(state, target):
			if not ELStrategy.adjacent(self, actor, target):
				if actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
			elif not ELSecondBuildings.use(self, actor, target) and actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "This building cannot be used now."})
		elif target.type == "teleport": _teleport(actor, target)
		elif target.type == "dock":
			var ship: bool = not actor.get("ship", false)
			var exit := grid.dock_exit(target, ship)
			if exit.x >= 0:
				actor.ship = ship
				ELSecondBuildings.refresh_travel(actor)
				state._native([float(actor.uid), float(exit.x), float(exit.y)], "ExJumpToPos")
				presentation.emit({"kind": "dock", "hero": actor.uid, "ship": ship})
			else: presentation.emit({"kind": "notice", "text": "There is no room to leave this dock."})
		else: presentation.emit({"kind": "use_object", "hero": hero_id, "target": target_id})

## EL2 Lake: scry the matching ReflectingEyes and show the visitor's local
## owner the Lake message every time.
func _lake(actor: Dictionary, lake: Dictionary) -> void:
	# The Lake is always usable and pays the shared 2-point use price.
	ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
	ELFog.scry(state, actor, lake)
	if int(actor.owner) != state.current_player: return
	var row: Dictionary = state.map.profile.table("AdditionalBuildings").get(ELFog.EL2_LAKE, {})
	var key := str(row.get("Message1", ""))
	presentation.emit({"kind": "building_message", "hero": actor.uid, "building": lake.uid, "title": state.map.profile.text(str(row.get("ELKName", lake.name))),
		"text": state.map.profile.text(key), "resources": [], "skill": "", "key": key})

func _teleport(actor: Dictionary, source: Dictionary) -> bool:
	var name := ELXml.value(source.node, "params")
	var receivers: Array[Dictionary] = []
	for target: Dictionary in state.objects.values():
		if target.uid != source.uid and target.type in ["teleport", "teleportreceiver"] and ELXml.value(target.node, "params") == name: receivers.append(target)
	if receivers.is_empty():
		presentation.emit({"kind": "notice", "text": "This teleport has no destination."})
		return false
	state.seed_value = (state.seed_value * 0x343fd + 0x269ec3) & 0xffffffff
	var target: Dictionary = receivers[((state.seed_value >> 16) & 0x7fff) % receivers.size()]
	var offsets := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, -1), Vector2i(-1, 1)]
	var preferred: Vector2i = Vector2i(target.x, target.y) + offsets[(int(target.rotation) >> 2) & 3]
	var destination := Vector2i(-1, -1)
	var distance := INF
	for radius in 9:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var point := preferred + Vector2i(x, y)
				if grid.passability(point, actor.get("ship", false)) < 0: continue
				var free := true
				for id: int in state._mob_ids:
					var mob := state.object(id)
					if mob.uid != actor.uid and mob.visible and Vector2i(mob.x, mob.y) == point: free = false
				if free and preferred.distance_squared_to(point) < distance:
					destination = point
					distance = preferred.distance_squared_to(point)
		if destination.x >= 0: break
	if destination.x < 0: return false
	state._native([float(actor.uid), float(destination.x), float(destination.y)], "ExJumpToPos")
	presentation.emit({"kind": "teleport", "hero": actor.uid, "source": source.uid, "target": target.uid})
	return true

## A Warrior of the Realm battle the local player takes part in; the local
## side plays first, as in every adventure battle.
func start_ethereal(attacker: int, defender: int) -> void:
	var local_first := int(state.object(attacker).owner) == state.current_player
	var next := ELAdventureEncounter.new()
	next.ethereal_defender = defender
	if not next.prepare(state, attacker if local_first else defender, defender if local_first else attacker, defender):
		_refuse_battle(next.error)
		return
	encounter = next
	presentation.emit({"kind": "encounter", "hero": next.hero_id, "opponent": next.opponent_id})

## A battle the remake cannot prepare (missing content or an unported rule)
## leaves the map as it was; the internal reason goes to the log, not the HUD.
func _refuse_battle(reason: String) -> void:
	battle_refusal = reason
	push_warning("Battle not started: " + reason)
	notice = BATTLE_REFUSED
	presentation.emit({"kind": "notice", "text": notice})

func finish_encounter() -> bool:
	if encounter == null: return false
	var interrupted := not state.outcome.is_empty()
	if not encounter.finish(): return _fail(encounter.error)
	var battle := {"hero": encounter.hero_id, "opponent": encounter.opponent_id, "winner": encounter.winner}
	var report := encounter.report
	var encounter_lost := encounter.lose_screen
	encounter = null
	# The local winner sees the experience gained: after a creature, with the
	# loot under it as resource rows; after a hero, the experience alone.
	var first := state.map.profile.id == "el1"
	var hero_loot: Array = report.get("artifacts", [])
	var show: bool = not report.is_empty() and (report.get("monster", false) or first or not hero_loot.is_empty())
	if not interrupted and show and int(state.object(report.hero).get("owner", -1)) == state.current_player:
		var profile := state.map.profile
		var text := ELAdditionalBuildings.format(profile, "T_MB_LOOT_MONSTER_OR_HERO_1", [int(report.experience)])
		var message := {"kind": "building_message", "hero": report.hero, "building": -1, "title": "", "text": text, "resources": report.resources, "skill": "", "key": "", "loot": true}
		if first:
			message.box = "first"
			if report.get("monster", false):
				message.text += "\n" + profile.text("T_MB_LOOT_MONSTER_2")
				message.rows = report.resources
		else:
			text += "\n"
			if report.get("monster", false): text += profile.text("T_MB_LOOT_MONSTER_2")
			else:
				# A defeated hero's battle artifacts pass to the winner.
				var names: Array[String] = []
				for item: Dictionary in hero_loot: names.append(ELMapPickups.artifact_title(profile, str(item.name)))
				text += profile.text("T_MB_LOOT_HERO_2") + " " + ", ".join(names)
			message.text = text
		presentation.emit(message)
	if not interrupted and encounter_lost: presentation.emit({"kind": "lose_battle", "hero": battle.hero, "opponent": battle.opponent})
	if not interrupted: ELFirstScenario.evaluate(self, battle)
	return true

## Second game: the pre-battle panel's Cancel declines the prepared battle.
func decline_encounter() -> bool:
	if encounter == null: return false
	if not encounter.decline(): return _fail(encounter.error)
	encounter = null
	return true

## Mid-duel chapter checks; the duel view leaves the battle once an outcome is set.
func watch_encounter() -> String:
	if encounter == null or encounter.battle == null: return ""
	return ELFirstScenario.duel_check(self, encounter.battle, encounter.watch_side)

func _execute(command: Dictionary) -> void:
	_running = command
	var args: Array = command.arguments
	var kind: String = command.kind
	var first: Variant = args[0] if not args.is_empty() else null
	match kind:
		"EndOfTurn":
			if state.map.profile.id == "el2": end_player_turn()
			else: ELAdventureClock.end_player_day(state, state.current_player if first == null or int(first) == -1 else int(first))
			_finish_command()
		"Wait":
			wait_remaining = maxf(0, float(first) / 1000.0)
			_waiting = true
		"Text", "Question":
			var actor := state.object(first)
			# Second game: a set third argument journals the line when it shows
			# as a notebook phrase.
			if args.size() > 2 and ELSecondNotebook.lua_flag(args[2]): ELSecondNotebook.add_phrase(state, args[1], first, true)
			# Second game: a speaker TextDialog; a question whose fourth argument is
			# set offers Move/Explore instead of Yes/No, with no portrait when the
			# speaker is not a hero.
			var move := kind == "Question" and args.size() > 3 and ELSecondNotebook.lua_flag(args[3])
			dialogue = {"actor": int(first), "title": actor.get("title", actor.get("name", "")), "text_id": str(args[1]),
				"text": state.map.profile.text(str(args[1])), "question": kind == "Question", "arguments": args.duplicate(),
				"box": "text", "speaker_box": not move or actor.get("type") == "hero", "move": move}
			presentation.emit({"kind": "dialogue", "dialogue": dialogue})
		"MoveToObject":
			var actor := state.object(first)
			var goal := state.object(args[1]) if args.size() > 1 else {}
			if actor.is_empty() or goal.is_empty():
				_fail("Missing actor in scenario command: " + str(first))
				return
			_begin_move(actor, Vector2i(goal.x, goal.y), true, int(goal.uid), false)
		"Moving", "MoveAndUseObject":
			var actor := state.object(first)
			if actor.is_empty():
				# Second game: "Hero not found" is only logged; the command finishes.
				if state.map.profile.id == "el2":
					push_warning("Scenario move for a missing hero: " + str(first))
					_finish_command()
				else: _fail("Missing actor in scenario command: " + str(first))
				return
			var target := state.object(args[1]) if kind == "MoveAndUseObject" else {}
			if kind == "MoveAndUseObject" and target.is_empty():
				_fail("Missing destination in scenario command.")
				return
			_begin_move(actor, Vector2i(int(args[1]), int(args[2])) if kind == "Moving" else Vector2i(target.x, target.y), true, int(args[1]) if kind == "MoveAndUseObject" else -1)
		"ExecuteScriptFunction":
			_finish_command()
			# A script function, or a native called by name; anything else is
			# reported instead of skipped.
			if state.vm.has_function(str(first)):
				if not state.hook(str(first), args.slice(1)): _fail(state.error)
			elif state._bindings().has(str(first)):
				state._native(args.slice(1), str(first))
				if not state.vm.error.is_empty(): _fail(state.vm.error)
			else: _fail("Scenario command calls an unknown function: " + str(first))
		# Queued observations call the direct natives and complete at once.
		"JumpToPos", "TakeObject", "KillHero", "PlaceObject", "AddArtefact", "AddSpell", "StartObservation", "FinishObservation":
			state._native(args, "Ex" + kind)
			_finish_command()
		"Win", "Lose":
			state._native([1.0 if kind == "Win" else 0.0], "ExWinLoseMission")
			_finish_command()
		"MobOrient", "MobOrientToObject", "MobOrientToPoint":
			var actor := state.object(first)
			var direction := Vector2.ZERO
			if kind == "MobOrient": direction = Vector2(float(args[1]), float(args[2]))
			elif kind == "MobOrientToObject":
				var target := state.object(args[1])
				if not target.is_empty(): direction = Vector2(target.x - actor.x, target.y - actor.y)
			else: direction = Vector2(float(args[1]) / 2.0 - 0.5 - actor.get("x", 0), float(args[2]) / 2.0 - 0.5 - actor.get("y", 0))
			presentation.emit({"kind": "orient", "id": int(first), "direction": direction})
			_finish_command()
		"CameraToObject", "CameraToPos", "CameraRotate", "CameraRotateToObject", "CameraRotateToPos", "CameraAttach":
			presentation.emit({"kind": kind, "arguments": args.duplicate()})
			_finish_command()
		# Queued effects and sounds act like the direct natives and complete at
		# once; a StartEffect has no loop count.
		"StartEffect":
			ELSecondAmbience.start_effect(state, args.slice(0, 5), true)
			_finish_command()
		"StartSound":
			ELSecondAmbience.start_sound(state, args)
			_finish_command()
		"FinishEffect":
			ELSecondAmbience.finish_effect(state, first)
			_finish_command()
		"FinishSound":
			ELSecondAmbience.cancel_sound(state, first)
			_finish_command()
		"OrientEffectByObject":
			ELSecondAmbience.orient_effect(state, first, args[1] if args.size() > 1 else null)
			_finish_command()
		# The queued affect takes (hero, name, id); the direct native (hero, id, name).
		"StartAffect":
			state._native([first, args[2] if args.size() > 2 else "", args[1] if args.size() > 1 else ""], "ExStartAffect")
			_finish_command()
		"FinishAffect":
			state._native(args, "ExFinishAffect")
			_finish_command()
		_: _fail("Unsupported scenario command: " + kind)

## Ends the running command. A script that aborted the queue while a move,
## wait or message was in flight must not lose the first of its new commands.
func _finish_command() -> void:
	if not state.commands.is_empty() and (_running == null or is_same(state.commands[0], _running)): state.commands.pop_front()
	_running = null

func _fail(message: String) -> bool:
	error = message
	presentation.emit({"kind": "error", "text": message})
	return false
