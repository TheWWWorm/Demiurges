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
## Second-game portal and dock use, which hold the next order until arrival.
var travel: Dictionary = {}
const PORTAL_SECONDS := 40.0 / 15.0
const DOCK_FADE_SECONDS := 15.0 / 15.0
const DOCK_MESSAGE_SECONDS := 20.0 / 15.0
var strategy: Dictionary = {}
var strategy_shop_wait: Callable
## Empty in local play. Network planning keeps the map's viewing player and
## the set of human commanders separate.
var _strategic_players: Array[int] = []
## Remake option: first-game heroes move at once, several times a day
## (ELStrategy.free_mode). The queue holds the rest of the computer players'
## day while it runs.
var free_movement := false
## Remake option: computer players pick skills, shop and cast global spells
## (ELFirstAIEconomy).
var smart_ai := false
var free_queue: Array = []
var _strategic_ai := -1
var _strategic_handoff_day := -1
var _strategic_forfeits := {}
var _strategic_ready: Array[int] = []
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
## Played when player 1's hero is stopped by a hostile zone.
const ENEMY_SOUND := "Buttons/Enemy.wav"
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
		if _strategic_players.is_empty() and int(data.player) == state.current_player: open_first_shop(data.hero, data.shop, true)
		return
	if data.kind == "hero_placed":
		# A hero set down inside a hostile zone cannot move on that night.
		var placed := state.object(data.id)
		grid.update_actor(placed)
		interception.rebuild(state, grid)
		# Second game: only player 1's heroes get the stop flag.
		var stoppable: bool = state.map.profile.id != "el2" or placed.get("type") == "hero" and int(placed.get("owner", -1)) == 1
		if stoppable and not interception.enemies(state, placed, Vector2i(placed.x, placed.y)).is_empty():
			placed.intercepted = true
			warn_danger(placed)
		return
	if data.kind == "object_killed" and ELGlobalSpells.applies(state) and state.object(data.id).get("type") == "hero": ELGlobalSpells.hero_died(state, state.object(data.id))
	# Second game: a fallen hero's keys return to their warding stones.
	if data.kind == "object_killed" and ELSecondGates.applies(state) and state.object(data.id).get("type") in ["hero", "monster"]: ELSecondGates.drop_keys(state, state.object(data.id))
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
## Player 1's hero stopped by a hostile zone: its ground ring pulses and
## Buttons\Enemy.wav plays until the turn boundary (EL1
## EL2).
func warn_danger(hero: Dictionary) -> void:
	if hero.get("type") != "hero" or int(hero.get("owner", -1)) != 1: return
	hero.danger_pulse = true
	ELUiSounds.play(state.map.profile, ENEMY_SOUND)

func end_player_turn() -> void:
	for actor: Dictionary in state.objects.values():
		if int(actor.get("owner", -1)) == state.current_player:
			if actor.get("intercepted", false): actor.intercepted = false
			actor.erase("danger_pulse")
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
		if int(actor.get("owner", -1)) == player and actor.get("alive", false) and not actor.get("orders", []).is_empty():
			var order: Variant = actor.orders[0]
			if not order is Dictionary or order.get("kind") != "RemoteUseHero": return true
	return false

## The local EL2 commander ends its turn when a remote plan is waiting and
## activates it when the next round starts. Keep that phase on the saved plan.
func _advance_remote_order() -> void:
	for id: int in state._mobs():
		var actor := state.object(id)
		if int(actor.owner) != 1 or not actor.alive or actor.orders.is_empty(): continue
		var order: Variant = actor.orders[0]
		if not order is Dictionary or order.get("kind") != "RemoteUseHero": continue
		if not order.has("resume_round"):
			order.resume_round = player_round + 1
			end_player_turn()
		elif player_round >= int(order.resume_round):
			state.commands.append(order.duplicate(true))
		return

func advance(delta: float) -> void:
	if not error.is_empty() or not state.outcome.is_empty() or encounter != null or _shopping(): return
	if not dialogue.is_empty(): return
	var action_held := action_wait > 0.0
	if not action_held and not movement.is_empty(): _advance_movement(delta)
	if not travel.is_empty():
		_advance_travel(delta)
		return
	if encounter != null or _shopping(): return
	if not strategy.is_empty():
		ELStrategy.advance(self)
		return
	if action_held:
		action_wait = maxf(0.0, action_wait - delta)
		if is_zero_approx(action_wait): action_wait = 0.0
	if _waiting and not action_held:
		wait_remaining -= delta
		if wait_remaining > 0: return
		_waiting = false
		_finish_command()
	_clock += delta
	# The second game's mission update runs 15 times per second (
	# ExWaitCmd and the tutorial's "150 segments = 10 sec").
	if _clock >= (1.0 / 15.0 if state.map.profile.id == "el2" else 0.1):
		_clock = 0.0
		var wake := not action_held and movement.is_empty() and not _busy(state.current_player)
		if not state.step(wake):
			_fail(state.error)
			return
		if wake: _woken = state.current_player
	# A mission action can start during the step hook or a queued callback.
	# It suspends the storyboard and commander while step/post-step still tick.
	if action_held or action_wait > 0.0 or not movement.is_empty(): return
	for budget in 32:
		if not state.commands.is_empty(): _commands_pending = true
		if state.commands.is_empty() or not dialogue.is_empty() or not movement.is_empty() or not travel.is_empty() or _waiting or not error.is_empty() or encounter != null or _shopping(): break
		_execute(state.commands[0])
		if action_wait > 0.0: return
	if _commands_pending and state.commands.is_empty() and movement.is_empty() and travel.is_empty() and not _waiting and dialogue.is_empty() and error.is_empty() and encounter == null:
		_commands_pending = false
		if not state.hook("Hook_AllCommandsFinished"): _fail(state.error)
	# A computer player's commander, once woken with no hero busy, queues its end
	# of turn at once; script commands run on their own queue.
	if state.map.profile.id == "el2":
		if state.current_player != 1 and _woken == state.current_player and error.is_empty() and encounter == null and travel.is_empty() and not _busy(state.current_player):
			end_player_turn()
		elif state.current_player == 1 and _map_idle() and movement.is_empty() and not _waiting:
			_advance_remote_order()

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
	if box.has("items"): dialogue.items = box.items.duplicate(true)
	if box.get("created", false): dialogue.created = true
	presentation.emit({"kind": "dialogue", "dialogue": dialogue})

func can_move() -> bool:
	# Second game: the local player waits while other players take their turn.
	if state.map.profile.id == "el2" and state.current_player != 1: return false
	return not strategy_ready(state.current_player) and _map_idle()

func _map_idle() -> bool:
	return error.is_empty() and state.outcome.is_empty() and dialogue.is_empty() and state.commands.is_empty() and action_wait <= 0.0 and not state.exclusive and encounter == null and not _shopping() and strategy.is_empty() and travel.is_empty()

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
	if state.map.profile.id == "el1": return submit_strategy_turn(state.current_player, state.day)
	if not can_move() or not movement.is_empty():
		notice = "Finish the current action before waiting for the next day."
		return false
	notice = ""
	# The original calls the hook for its effects and discards its result. The
	# second game calls it only when a player round ends (end_player_turn).
	if state.map.profile.id != "el2" and state.vm != null and state.vm.has_function("Hook_EndOfTurn"):
		state.vm.invoke("Hook_EndOfTurn", [float(state.current_player)])
		if not state.vm.error.is_empty(): return _fail(state.vm.error)
	# The placement stop flag lasts until that player's turn boundary.
	for actor: Dictionary in state.objects.values():
		if int(actor.get("owner", -1)) == state.current_player:
			if actor.get("intercepted", false): actor.intercepted = false
			actor.erase("danger_pulse")
	return ELAdventureClock.end_player_day(state, state.current_player)

func request_move(id: int, destination: Vector2i, use_id := -1) -> bool:
	if state.map.profile.id == "el1": return plan_strategy_move(state.current_player, state.day, id, destination, use_id)
	if not can_move():
		notice = "Finish the current conversation first."
		return false
	var actor := state.object(id)
	if actor.is_empty() or actor.owner != state.current_player or not actor.alive: return false
	notice = ""
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
	return cancel_strategy_move(state.current_player, state.day, id)

## Bind human commanders before accepting orders. Single-player keeps its
## original local commander and still lets the AI plan at night.
func bind_strategy_players(players: Array[int], local_authority := false) -> bool:
	if not _strategic_players.is_empty() or not ELFirstScenario.applies(state) or bool(state.scenario.get("campaign", false)): return false
	if players.size() < 2 or not players.has(state.current_player) or not can_move() or not movement.is_empty(): return false
	if local_authority and (players.size() != 2 or players[0] != state.current_player): return false
	var unique := {}
	for player: int in players:
		if unique.has(player) or not state.players.has(player): return false
		if not ELFirstScenario.alive(state, player) and (not local_authority or player != players[1]): return false
		unique[player] = true
	_strategic_players.assign(players)
	if local_authority: _strategic_ai = players[1]
	return true

func is_strategy_human(player: int) -> bool:
	return player == state.current_player if _strategic_players.is_empty() else player != _strategic_ai and _strategic_players.has(player)

## Orders already committed for this night keep the departed player's rules.
func is_human_strategy_order(player: int) -> bool:
	return is_strategy_human(player) or (player == _strategic_ai and _strategic_handoff_day == state.day and not strategy.is_empty())

func strategy_commanders() -> Array[int]:
	var commanders := _strategic_players.duplicate()
	commanders.erase(_strategic_ai)
	return commanders

func strategy_seats() -> Array[int]:
	return _strategic_players.duplicate()

func replace_strategy_guest(player: int) -> void:
	_strategic_ai = player
	_strategic_handoff_day = state.day if not strategy.is_empty() else -1
	_strategic_ready.clear()
	# Only battle records already queued at departure can be forfeited.
	_strategic_forfeits.clear()
	var from := int(strategy.index) if strategy.get("phase") == "combat" else 0
	for pair: Array in strategy.get("combats", []).slice(from):
		var first := int(pair[0])
		var second := int(pair[1])
		var first_left: bool = state.object(first).get("owner") == player
		var second_left: bool = state.object(second).get("owner") == player
		if first_left != second_left:
			_strategic_forfeits[Vector2i(mini(first, second), maxi(first, second))] = second if first_left else first

func strategic_forfeit_winner(first: int, second: int) -> int:
	if _strategic_handoff_day != state.day or strategy.get("phase") != "combat": return -1
	return int(_strategic_forfeits.get(Vector2i(mini(first, second), maxi(first, second)), -1))

func strategy_ready(player: int) -> bool:
	return _strategic_ready.has(player)

## Network hero orders apply to the authenticated commander, independently of
## the map's viewing seat. They use the existing inventory and skill rules.
func manage_strategy_hero(player: int, day: int, order: Array) -> String:
	if not _strategy_input(player, day) or not movement.is_empty(): return "This commander cannot change heroes now."
	if order.size() == 2 and order[0] in ELBuildingScreen.STRATEGIC_UPGRADES.values() and _strategy_number(order[1]):
		var id := int(order[1])
		var building := state.object(id)
		if (ELBuildingScreen.STRATEGIC_UPGRADES.get(building.get("type")) != order[0]
			or not building.get("alive", false) or not building.get("visible", false) or not building.get("enabled", false)):
			match order[0]:
				"upgrade_fort": return "This fort is unavailable."
				"upgrade_mine": return "This mine is unavailable."
				_: return "This shop is unavailable."
		var problem := ELBuildingScreen.upgrade_problem(state, player, id, true)
		if not problem.is_empty(): return problem
		return "" if ELBuildingScreen.upgrade(state, player, id, true) else "This building cannot be upgraded."
	if order.size() < 2 or not order[0] is String or not _strategy_number(order[1]): return "Invalid hero order."
	var id := int(order[1])
	var hero := state.object(id)
	if hero.get("type") != "hero" or hero.get("owner") != player or not hero.get("alive", false):
		return "That hero is unavailable."
	if order[0] == "dismiss_hero":
		if order.size() != 2: return "Invalid dismissal order."
		return "" if ELHeroExchange.dismiss(self, id, player) else "This hero cannot be dismissed."
	if order[0] == "leave_fort":
		if order.size() != 2: return "Invalid fort order."
		return "" if ELForts.leave(state, id) else "This hero cannot leave right now."
	if order.size() < 3: return "Invalid hero order."
	var previous_error := state.error
	var applied := false
	match order[0]:
		"equip", "reserve":
			if order.size() != 4 or not _strategy_code(order[2]) or not _strategy_number(order[3]): return "Invalid spellbook order."
			var index := int(order[3])
			if order[0] == "equip": applied = state.move_spell(id, order[2], -1, index, player)
			else:
				if index >= hero.cards.size() or hero.cards[index] != order[2]: return "That spellbook slot has changed."
				applied = state.move_spell(id, "", index, 0, player)
		"learn_skill":
			if order.size() != 3 or not _strategy_code(order[2]): return "Invalid skill order."
			ELHeroSkills.prepare(state.map.profile, hero)
			applied = state.choose_skill(id, order[2], player)
		"transfer":
			if order.size() != 5 or not _strategy_number(order[2]) or not _strategy_number(order[3]) or not _strategy_number(order[4]): return "Invalid equipment order."
			var target := int(order[3])
			if target != id:
				var receiver := state.object(target)
				if not receiver.get("visible", false) or not receiver.get("placed", true) or receiver.get("fortified", false):
					return "That hero is unavailable."
				var problem := ELHeroExchange.exchange_problem(self, id, target, player)
				if not problem.is_empty(): return problem
			return "" if ELHeroExchange.transfer(state, id, int(order[2]), target, int(order[4]), player) else "That equipment cannot be moved."
		"buy_runes", "buy_spells":
			return strategy_purchase(player, hero, order)
		_: return "Unknown hero order."
	var reason := state.error
	state.error = previous_error
	return "" if applied else reason if not reason.is_empty() else "The hero order was refused."

## Open an independent draft. The authority uses the same draft rules with
## the authenticated commander, even when its own shop screen is open.
func strategy_shop_trade(player: int, hero_id: int, shop_id: int, remote := false) -> RefCounted:
	var hero := state.object(hero_id)
	var target := state.object(shop_id)
	if hero.get("owner") != player or hero.get("type") != "hero" or not hero.get("alive", false) or target.is_empty(): return null
	if remote:
		if ELGlobalSpells.held(hero) or not ELFog.explored(state, player, Vector2i(target.x, target.y)): return null
	else:
		if not hero.get("visible", false) or not hero.get("placed", true) or hero.get("fortified", false) or int(hero.get("camp", -1)) >= 0: return null
		if not target.get("placed", true) or target.owner != player or not ELFog.shown(state, player, target) or not ELStrategy.adjacent(self, hero, target): return null
	if target.type == "rune_shop":
		var runes := ELRuneShop.new()
		if runes.open(state, hero_id, shop_id, true, player): return runes
	elif target.type == "el1_spell_shop":
		var spells := ELFirstSpellShop.new()
		if spells.open(state, hero_id, shop_id, true, player): return spells
	return null

func strategy_purchase(player: int, hero: Dictionary, order: Array, remote := false) -> String:
	if not _strategy_number(order[2]) or order.size() != 3 + hero.cards.size(): return "Invalid shop order."
	var trade := strategy_shop_trade(player, hero.uid, int(order[2]), remote)
	if order[0] == "buy_runes" and trade is ELRuneShop:
		for slot in hero.cards.size():
			if not ELLuaSave._integer(order[slot + 3], 0, 15): return "Invalid rune purchase."
			if not trade.set_amount(slot, int(order[slot + 3])): return trade.error
	elif order[0] == "buy_spells" and trade is ELFirstSpellShop:
		for slot in hero.cards.size():
			var card: Variant = order[slot + 3]
			if not card is String or (not card.is_empty() and card.length() != 4): return "Invalid spell purchase."
			if not card.is_empty() and not trade.replace(slot, card): return trade.error
	else: return "Move next to a shop you control first."
	return "" if trade.commit() else trade.error

static func _strategy_number(value: Variant) -> bool:
	return ELLuaSave._integer(value, 0, 0x7fffffff)

static func _strategy_code(value: Variant) -> bool:
	return value is String and value.length() <= 32 and value.is_valid_identifier()

func manage_strategy_spell(player: int, day: int, order: Array) -> String:
	if not _strategy_input(player, day) or not movement.is_empty(): return "This commander cannot use global spells now."
	if order.size() < 2: return "Invalid global spell order."
	var previous := state.error
	if order[0] == "global_dispel":
		if order.size() != 2 or not _strategy_number(order[1]): return "Invalid global spell order."
		var dispelled := ELGlobalSpells.dispel(state, player, int(order[1]))
		var problem := state.error
		state.error = previous
		return "" if dispelled else problem
	if not order[1] is String: return "Invalid global spell order."
	var code: String = order[1]
	var applied := false
	if order[0] == "global_produce":
		var cost := ELGlobalSpells.ether_cost(state, player, code)
		if order.size() != 3 or not ELLuaSave._integer(order[2], 0, 1000000 - cost): return "Invalid global spell order."
		applied = ELGlobalSpells.produce(state, player, code, int(order[2]))
	else:
		if ELGlobalSpells.data(state, player).production.get("code") != code: return "The current global spell has changed."
		if order[0] == "global_cast":
			var targets := order.slice(2)
			for id: Variant in targets:
				if not _strategy_number(id): return "Invalid global spell order."
			applied = ELGlobalSpells.cast(state, player, targets)
		elif order[0] == "global_cancel":
			if order.size() != 2: return "Invalid global spell order."
			applied = ELGlobalSpells.cancel(state, player)
		else:
			return "Invalid global spell order."
	var reason := state.error
	state.error = previous
	return "" if applied else reason if not reason.is_empty() else "The global spell order was refused."

func manage_strategy_diplomacy(player: int, day: int, order: Array) -> String:
	if not _strategy_input(player, day): return "This commander cannot use diplomacy now."
	return ELDiplomacy.strategic_order(state, player, order)

func _strategy_input(player: int, day: int, ending := false) -> bool:
	if state.map.profile.id != "el1" or not is_strategy_human(player) or day != state.day: return false
	if not _map_idle() or ((ending or not _strategic_players.is_empty()) and not movement.is_empty()):
		notice = "Finish the current action before waiting for the next day." if ending else "Finish the current conversation first."
		return false
	if strategy_ready(player):
		notice = "This commander has ended the turn."
		return false
	return _strategic_players.is_empty() or ELFirstScenario.alive(state, player)

func plan_strategy_move(player: int, day: int, id: int, destination: Vector2i, use_id := -1) -> bool:
	if not _strategy_input(player, day): return false
	var actor := state.object(id)
	if actor.is_empty() or actor.owner != player or not actor.alive: return false
	notice = ""
	if not _strategic_players.is_empty():
		if actor.type != "hero" or not actor.visible: return false
		if use_id >= 0:
			var target := state.object(use_id)
			if target.is_empty() or not target.alive or not target.visible or not target.enabled or not target.get("placed", true) or not ELFog.shown(state, player, target): return false
			var size: Vector2i = grid.footprints.get(use_id, {}).get("size", Vector2i.ONE)
			if not Rect2i(target.x, target.y, size.x, size.y).has_point(destination): return false
	# Free movement: choosing the planned destination again sets off at once.
	if ELStrategy.free_mode(self) and actor.type == "hero":
		var order: Dictionary = actor.get("strategy_order", {})
		if not order.is_empty() and int(order.use) == use_id and (use_id >= 0 or Vector2i(order.destination[0], order.destination[1]) == destination):
			return ELStrategy.act(self, actor)
	return ELStrategy.plan(self, actor, destination, use_id)

func cancel_strategy_move(player: int, day: int, id: int) -> bool:
	if not _strategy_input(player, day): return false
	var actor := state.object(id)
	if actor.is_empty() or actor.owner != player: return false
	if not _strategic_players.is_empty() and (actor.type != "hero" or not actor.alive or not actor.visible): return false
	actor.strategy_order = {}
	notice = ""
	presentation.emit({"kind": "route", "id": id, "path": []})
	presentation.emit({"kind": "notice", "text": notice})
	return true

func submit_strategy_turn(player: int, day: int) -> bool:
	if not _strategy_input(player, day, true): return false
	notice = ""
	if _strategic_players.is_empty(): return ELStrategy.begin(self)
	_strategic_ready.append(player)
	for commander: int in strategy_commanders():
		if ELFirstScenario.alive(state, commander) and not strategy_ready(commander):
			presentation.emit({"kind": "strategy_ready", "player": player})
			return true
	var begun := ELStrategy.begin(self)
	if begun: _strategic_ready.clear()
	return begun

func _begin_move(actor: Dictionary, destination: Vector2i, queued: bool, use_id := -1, use_at_end := true) -> bool:
	# Second game: Hook_OnHeroCommandRun(hero) as the order executes (
	# ), for player clicks and scripted moves alike; a true result
	# discards the order and the hero stays put.
	if state.map.profile.id == "el2" and _command_run_vetoed(actor):
		if queued: _finish_command()
		return queued
	var from := Vector2i(actor.x, actor.y)
	# A new order while this hero is between two tiles finishes that step
	# and goes on from the next tile, so the figure never jumps back.
	var stepping: Vector2i = from
	var progress := 0.0
	if not queued and not movement.is_empty() and int(movement.id) == int(actor.uid) and float(movement.progress) > 0.0:
		stepping = movement.path[int(movement.index) + 1]
		progress = float(movement.progress)
	# Second game: routes avoid hostile guard zones where they can.
	var avoid := interception.hostile_cells(state, actor) if state.map.profile.id == "el2" else ([] as Array[Vector2i])
	var path := grid.approach(stepping, state.object(use_id), actor.get("ship", false), avoid) if use_id >= 0 else grid.path(stepping, destination, actor.get("ship", false), avoid)
	if stepping != from:
		if path.is_empty() or path[0] != stepping:
			progress = 0.0
			path = grid.approach(from, state.object(use_id), actor.get("ship", false), avoid) if use_id >= 0 else grid.path(from, destination, actor.get("ship", false), avoid)
		else:
			path.insert(0, from)
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
	movement = {"id": actor.uid, "path": path, "index": 0, "progress": progress, "queued": queued, "use": use_id if use_at_end else -1}
	actor.orders.assign(["move"])
	presentation.emit({"kind": "route", "id": actor.uid, "path": path})
	if path.size() == 1: _complete_movement()
	return true

## Travel in tiles per second. Second-game figures receive a six-unit-per-second
## map speed override, or four times that in accelerated mode.
func movement_speed(actor: Dictionary) -> float:
	if state.map.profile.id == "el1": return 16.0 if fast_mode else 4.0
	if fast_mode: return 12.0
	return 4.5 if actor.get("ship", false) and ELSecondBuildings.has_beacon(actor) else 3.0

func _advance_movement(delta: float) -> void:
	var actor := state.object(movement.id)
	if actor.is_empty() or not actor.alive or actor.orders.is_empty():
		_complete_movement(false)
		return
	var travel := delta * movement_speed(actor)
	var second := state.map.profile.id == "el2"
	var fog_viewer := 1 if second else state.current_player
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
		# Hidden EL2 steps spend no animation time, including on AI turns.
		if (second or movement.get("strategic", false)) and not ELFog.visible(state, fog_viewer, Vector2i(from)) and not ELFog.visible(state, fog_viewer, Vector2i(to)):
			if second: remaining = 0.0
			else: travel = maxf(travel, remaining)
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
	var corpse: bool = state.map.profile.id == "el2" and target.get("type") == "corpse"
	# A lair's creature waits off the map; its battle is still fought.
	if actor.is_empty() or target.is_empty() or not (target.alive or corpse) or not (target.visible or target.has("dungeon")) or not target.enabled or encounter != null or _shopping() or not travel.is_empty(): return
	if corpse and hero_id != state.main_hero: return
	if state.vm != null:
		var result := state.vm.invoke("Hook_OnPreUse", [float(target_id), float(hero_id)])
		if not state.vm.error.is_empty():
			_fail(state.vm.error)
			return
		if not result.is_empty() and not ELAdventureSession._truthy_flag(result[0]): return
	# Looting is wholly scripted through Hook_OnPreUse.
	if corpse: return
	if target.type in ["hero", "monster"] and state.hostile(actor, target):
		_begin_encounter(actor, target, defender)
	else:
		if ELResourceSites.TYPES.has(target.group):
			inspect_site(hero_id, target_id)
		elif target.type == "fort" and state.map.profile.id == "el2" and int(actor.get("fort", -1)) == target_id:
			if ELForts.leave(state, hero_id): ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
		elif target.type == "fort":
			var garrison := state.object(target.garrison)
			var assault: bool = state.map.profile.id == "el2" and garrison.get("alive", false) and state.hostile(actor, garrison)
			var problem := ELForts.enter_problem(state, hero_id, target_id, assault)
			if not problem.is_empty() or not ELStrategy.adjacent(self, actor, target):
				if actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": problem if not problem.is_empty() else "Move next to this fort first."})
				return
			if assault: _begin_encounter(actor, garrison, -1, target_id)
			elif ELForts.enter(state, hero_id, target_id) and state.map.profile.id == "el2":
				ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
		elif target.group == "resource_cuts":
			if not state.collect_resources(hero_id, target_id): presentation.emit({"kind": "notice", "text": state.error})
		elif target.type in ["el1_spell_shop", "rune_shop"]:
			if _strategic_players.is_empty(): open_first_shop(hero_id, target_id)
			elif is_human_strategy_order(actor.owner):
				ELBuildings.capture(state, target, actor.owner)
				if is_strategy_human(actor.owner):
					state.event.emit({"kind": "strategy_shop_visit", "hero": hero_id, "shop": target_id, "player": actor.owner})
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
			elif actor.owner == 1: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
		elif ELSecondArtifacts.applies(state.map.profile) and ELSecondArtifacts.is_building(target): ELSecondArtifacts.visit(self, actor, target)
		elif ELSecondGates.applies(state) and not ELBattlegrounds.affect(state, target).is_empty():
			if not ELStrategy.adjacent(self, actor, target):
				if actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
			elif not ELBattlegrounds.use(self, actor, target) and actor.owner == state.current_player: presentation.emit({"kind": "notice", "text": "This building cannot be used now."})
		elif ELSecondBuildings.applies(state, target):
			if not ELStrategy.adjacent(self, actor, target):
				if actor.owner == 1: presentation.emit({"kind": "notice", "text": "Move next to this building first."})
			elif not ELSecondBuildings.use(self, actor, target) and actor.owner == 1: presentation.emit({"kind": "notice", "text": "This building cannot be used now."})
		elif target.type == "teleport": _teleport(actor, target)
		elif state.map.profile.id == "el2" and ELSecondBuildings.is_tunnel(target): _use_tunnel(actor, target)
		elif target.type == "dock":
			var ship: bool = not actor.get("ship", false)
			var exit := grid.dock_exit(target, ship)
			if exit.x >= 0:
				if state.map.profile.id == "el2": _begin_travel("dock", actor, target, target.uid, exit, DOCK_FADE_SECONDS)
				else: _arrive_dock(actor, exit, ship)
			else: presentation.emit({"kind": "notice", "text": "There is no room to leave this dock."})
		else: presentation.emit({"kind": "use_object", "hero": hero_id, "target": target_id})

func _begin_encounter(actor: Dictionary, target: Dictionary, defender := -1, assault_fort := -1, remote_use := false) -> void:
	var next := ELAdventureEncounter.new()
	if not next.prepare(state, int(actor.uid), int(target.uid), defender):
		_refuse_battle(next.error)
		return
	next.assault_fort = assault_fort
	encounter = next
	if not next.unsupported_artifacts.is_empty() and state.current_player in [int(actor.owner), int(target.owner)]:
		var names: Array[String] = []
		for name: String in next.unsupported_artifacts: names.append(ELMapPickups.artifact_title(state.map.profile, name))
		notice = "Not usable in battle yet: " + ", ".join(names)
		presentation.emit({"kind": "notice", "text": notice})
	if next.scripted_winner >= 0 or next.auto:
		finish_encounter()
		return
	presentation.emit({"kind": "encounter", "hero": actor.uid, "opponent": target.uid, "remote_use": remote_use})

## EL2 Lake: scry the matching ReflectingEyes and show the visitor's local
## owner the Lake message every time.
func _lake(actor: Dictionary, lake: Dictionary) -> void:
	# The Lake is always usable and pays the shared 2-point use price.
	ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
	ELFog.scry(state, actor, lake)
	if int(actor.owner) != 1: return
	var row: Dictionary = state.map.profile.table("AdditionalBuildings").get(ELFog.EL2_LAKE, {})
	var key := str(row.get("Message1", ""))
	presentation.emit({"kind": "building_message", "hero": actor.uid, "building": lake.uid, "title": state.map.profile.text(str(row.get("ELKName", lake.name))),
		"text": state.map.profile.text(key), "resources": [], "skill": "", "key": key})

## A two-coordinate EL2 portal has no receiver object.
static func teleport_coordinates(source: Dictionary) -> Vector2i:
	var params := str(ELXml.value(source.get("node", {}), "params"))
	var parts := params.replace(",", " ").replace("\t", " ").replace("\n", " ").split(" ", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return Vector2i(-1, -1)
	return Vector2i(parts[0].to_int(), parts[1].to_int())

func _teleport(actor: Dictionary, source: Dictionary) -> bool:
	var second := state.map.profile.id == "el2"
	var time := PORTAL_SECONDS if second and (int(actor.owner) == 1 or ELFog.object_state(state, 1, source) == ELFog.VISIBLE) else 0.0
	if second:
		var coordinates := teleport_coordinates(source)
		if grid.contains(coordinates):
			var exit := grid.find_landing(Rect2i(coordinates, Vector2i.ONE).grow(1), coordinates, actor.get("ship", false))
			if exit.x < 0: return false
			_begin_travel("teleport", actor, source, -1, exit, time)
			return true
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
	var origin := Vector2i(target.x, target.y)
	var preferred: Vector2i = origin + offsets[(int(target.rotation) >> 2) & 3]
	if second:
		var size: Vector2i = grid.footprints.get(int(target.uid), {}).get("size", Vector2i.ONE)
		var exit := grid.find_landing(Rect2i(origin, size).grow(1), preferred, actor.get("ship", false))
		if exit.x < 0: return false
		_begin_travel("teleport", actor, source, target.uid, exit, time)
		return true
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

func _begin_travel(kind: String, actor: Dictionary, source: Dictionary, target_id: int, destination: Vector2i, time: float) -> void:
	travel = {"kind": kind, "hero": int(actor.uid), "source": int(source.uid), "target": target_id,
		"x": destination.x, "y": destination.y, "remaining": time, "arrived": false}
	presentation.emit({"kind": "travel_phase"})
	if time <= 0.0: _advance_travel(0.0)

func _advance_travel(delta: float) -> void:
	travel.remaining = maxf(0.0, float(travel.remaining) - delta)
	if travel.remaining > 0.00001: return
	var actor := state.object(travel.hero)
	if not actor.get("alive", false):
		_end_travel()
		return
	if not travel.arrived:
		travel.arrived = true
		var exit := Vector2i(travel.x, travel.y)
		if travel.kind == "dock":
			_arrive_dock(actor, exit, not actor.get("ship", false))
			travel.remaining = DOCK_MESSAGE_SECONDS if int(actor.owner) == 1 else 0.0
		else:
			state._native([float(actor.uid), float(exit.x), float(exit.y)], "ExJumpToPos")
			presentation.emit({"kind": "teleport", "hero": actor.uid, "source": travel.source, "target": travel.target})
			var target := state.object(travel.target)
			var visible := int(actor.owner) == 1 or (ELFog.visible(state, 1, exit) if target.is_empty() else ELFog.object_state(state, 1, target) == ELFog.VISIBLE)
			travel.remaining = PORTAL_SECONDS if visible else 0.0
		ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
		if travel.remaining > 0.0:
			presentation.emit({"kind": "travel_phase"})
			return
	_end_travel()

func _arrive_dock(actor: Dictionary, exit: Vector2i, ship: bool) -> void:
	actor.ship = ship
	ELSecondBuildings.refresh_travel(actor)
	state._native([float(actor.uid), float(exit.x), float(exit.y)], "ExJumpToPos")
	presentation.emit({"kind": "dock", "hero": actor.uid, "ship": ship})

func _end_travel() -> void:
	var finished := travel
	travel = {}
	presentation.emit({"kind": "travel_finished", "hero": finished.hero})
	var actor := state.object(finished.hero)
	if finished.kind == "dock" and finished.arrived and actor.get("alive", false) and int(actor.owner) == 1:
		var key := "BldngMsg1Dock" if actor.get("ship", false) else "BldngMsg2Dock"
		presentation.emit({"kind": "building_message", "hero": actor.uid, "building": finished.source, "text": state.map.profile.text(key), "key": key})

func _use_tunnel(actor: Dictionary, source: Dictionary) -> void:
	var route := ELSecondBuildings.params(source).get_slice(";", 0)
	if route.is_empty(): return
	var exits: Array[Dictionary] = []
	for target: Dictionary in state.objects.values():
		if int(target.uid) == int(source.uid) or not ELSecondBuildings.is_tunnel(target) or ELSecondBuildings.params(target).get_slice(";", 0) != route: continue
		var cell := grid.tunnel_exit(target, actor.get("ship", false))
		if cell.x >= 0: exits.append({"id": target.uid, "cell": cell})
	if exits.is_empty(): return
	var guard := state.object(source.get("guard"))
	if guard.get("alive", false):
		guard.tunnel_source = int(source.uid)
		if int(actor.owner) == state.current_player:
			var key := str(ELSecondBuildings.definition(state.map.profile, source).get("Message1", ""))
			presentation.emit({"kind": "building_message", "hero": actor.uid, "building": source.uid,
				"text": state.map.profile.text(key).replace("%s", str(guard.get("title", guard.name))), "key": key})
		_begin_encounter(actor, guard)
		return
	state.seed_value = (state.seed_value * 0x343fd + 0x269ec3) & 0xffffffff
	var exit: Dictionary = exits[((state.seed_value >> 16) & 0x7fff) % exits.size()]
	ELAdventureClock.use_points(state, actor, ELSecondBuildings.USE_COST)
	state._native([float(actor.uid), float(exit.cell.x), float(exit.cell.y)], "ExJumpToPos")
	presentation.emit({"kind": "tunnel", "hero": actor.uid, "source": source.uid, "target": exit.id})

## A Warrior of the Realm battle with a human commander. Keep the viewing
## player's usual slot if involved, otherwise put the remote commander first.
func start_ethereal(attacker: int, defender: int) -> void:
	var attacker_owner := int(state.object(attacker).owner)
	var defender_owner := int(state.object(defender).owner)
	var local_first := attacker_owner == state.current_player or (defender_owner != state.current_player and is_strategy_human(attacker_owner))
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
	var battle := {"hero": encounter.attacker(), "opponent": encounter.target(), "winner": encounter.winner}
	var report := encounter.report
	var encounter_lost := encounter.lose_screen
	var assault_fort := encounter.assault_fort
	encounter = null
	# The fort action resumes after battle resolution clears its garrison.
	if assault_fort >= 0 and battle.winner == battle.hero and state.outcome.is_empty():
		if ELForts.enter(state, battle.hero, assault_fort):
			ELAdventureClock.use_points(state, state.object(battle.hero), ELSecondBuildings.USE_COST)
	# The local winner sees the experience gained: after a creature, with the
	# loot under it as resource rows; after a hero, the experience alone.
	var first := state.map.profile.id == "el1"
	var hero_loot: Array = report.get("artifacts", [])
	# Second game: the experience line after any won
	# battle; after a creature with trophies, T_MB_LOOT_MONSTER_2 and the
	# trophies under it.
	var show: bool = not report.is_empty() and (report.get("monster", false) or first or state.map.profile.id == "el2" or not hero_loot.is_empty())
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
			message.key = "T_MB_LOOT_MONSTER_OR_HERO_1"
			message.resources = []
			var trophies: Array = report.get("resources", [])
			if report.get("monster", false) and not trophies.is_empty():
				message.text = "\n".join(PackedStringArray([text, profile.text("T_MB_LOOT_MONSTER_2")] + Array(ELSecondLoot.lines(profile, trophies))))
			message.trophies = trophies.duplicate(true)
		presentation.emit(message)
	if not interrupted and encounter_lost: presentation.emit({"kind": "lose_battle", "hero": battle.hero, "opponent": battle.opponent})
	var opponent := state.object(battle.opponent)
	if state.outcome.is_empty() and battle.winner == battle.hero and opponent.has("tunnel_source") and not opponent.alive:
		var source := state.object(opponent.tunnel_source)
		if not source.is_empty():
			ELSecondBuildings.clear_tunnel_guards(state, source)
			_use_tunnel(state.object(battle.hero), source)
	if not interrupted: ELFirstScenario.evaluate(self, battle)
	return true

## The pre-battle panel's Cancel declines the prepared battle (second game;
## first game against a neutral creature).
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
		"RemoteUseHero":
			var actor := state.object(first)
			var target := state.object(args[1]) if args.size() > 1 else {}
			_finish_command()
			var plan: Variant = actor.get("orders", []).front() if not actor.get("orders", []).is_empty() else null
			if not plan is Dictionary or plan.get("kind") != kind or plan.get("arguments") != args: return
			actor.orders.clear()
			if actor.alive and target.get("alive", false) and not _command_run_vetoed(actor):
				_begin_encounter(actor, target, int(target.uid), -1, true)
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
		"StartLight":
			ELSecondAmbience.start_light(state, args)
			_finish_command()
		"FinishLight":
			ELSecondAmbience.finish_light(state, first)
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
