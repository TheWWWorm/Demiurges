class_name ELStrategicSession
extends Node
## One authority advances the adventure director. The other peer renders
## checkpoints and sends orders. Both play the same tactical command stream.
signal world_ready(restored: Dictionary)
signal message(text: String)
signal closed(reason: String)
signal turn_timeout
signal management_changed
signal takeover_notice(text: String)

const MAX_SITE_NOTICES := 128
const SHOP_CAPTURE_TYPES := ["el1_spell_shop", "rune_shop"]
const BUILDING_WORLD_ORDERS := ["leave_fort", "upgrade_fort", "upgrade_mine"]
const OBSERVED_RESULT_MS := 5000

var link := ELNetworkStrategy.new()
var relay := ELStrategicBattleRelay.new()
var director: ELAdventureDirector
var profile: ELProfile
var turn_committed := false
var battle_started := false
var presentation_ready: Callable
var site_notice_open: Callable
var _setup := {}
var _restored_host := {}
var _codec := ELAdventureSave.new()
var _next_world := {}
var _receiving_day := 0
var _receiving_revision := 0
var _world_open := false
var _send_world := false
var _accepted := false
var _battle_id := 0
var _own_battle_ready := false
var _guest_battle_ready := false
var _finished := false
var _wire_ready: Array[int] = []
var _battle_deadline := 0
var _observer_ai_clock := 0.0
var _observer_note := ""
var _observer_note_until := 0
var _next_request := 1
var _management := {}
var _management_deadline := 0
var _guest_pickups: Array[Array] = []
var _guest_recruit := -1
## Sent with the next checkpoint. A guest can receive several checkpoints
## before its view is ready, so it queues the cues until it installs the map.
var _summon_cues: Array = []
var _shop_visits: Array[Array] = []
var _site_cues: Array[Array] = []
var _active_shop: Array = []
var _remote_shops := {}
var _clock_view_day := 0
var _clock_guest_day := 0
var _clock_day := 0
var _clock_deadline := 0
var _clock_expired_day := 0
var _clock_ack_deadline := 0
var _leaving := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	link.message.connect(func(text: String): message.emit(text))
	link.closed.connect(func(reason: String):
		if not _leaving: closed.emit.call_deferred(reason))
	link.can_replace_guest = _can_replace_guest
	link.guest_departed.connect(_guest_departed)
	link.started.connect(_started)
	link.clock_event.connect(_clock_event)
	link.plan_received.connect(_accept_plan)
	link.command_received.connect(_accept_management)
	link.command_replied.connect(_management_reply)
	link.readiness_changed.connect(_ready_changed)
	link.snapshot_received.connect(_received_world)
	link.battle_received.connect(_received_battle)
	relay.outbound.connect(func(id: int, payload: Array):
		if not link.local_authority and not link.send_battle(id, payload): relay.transport_failed())
	relay.failed.connect(link.abort)
	relay.host_finished.connect(func(_id: int, _winner: int): _finished = true)

func _exit_tree() -> void:
	relay.detach()
	link.close()
	if not _restored_host.is_empty(): _restored_host.state.close()
	if director != null and not _world_open: director.state.close()

func _process(delta: float) -> void:
	if link.live: _tick_clock()
	link.poll()
	if not link.live: return
	if _battle_deadline > 0 and Time.get_ticks_msec() > _battle_deadline:
		link.abort("The other player did not open the strategic battle.")
		return
	if _management_deadline > 0 and Time.get_ticks_msec() > _management_deadline:
		link.abort("The host did not confirm the hero order.")
		return
	if _world_open and director != null and director.state.outcome.is_empty() and director.strategy.is_empty() and not turn_committed and not ELFirstScenario.alive(director.state, link.local_player):
		link.set_ready(director.state.day, true)
	if battle_started: _tick_battle(delta)
	if link.is_host and _send_world:
		_send_world = false
		if link.local_authority: link.finish_local_day(director.state.day)
		else: _publish_world()
	elif not _next_world.is_empty() and (_world_open or director == null) and _can_install_snapshot() and _presentation_idle():
		_open_snapshot()

func _presentation_idle() -> bool:
	return not presentation_ready.is_valid() or presentation_ready.call()

func _can_install_snapshot() -> bool:
	# Reliable packets are only ordered within a channel. A world checkpoint
	# can reach the guest while the final tactical commit is still pending.
	if relay.duel != null and not relay.result_confirmed(): return false
	if site_notice_open.is_valid() and site_notice_open.call(): return false
	# Keep the caster's draft and its controls while the other commander acts.
	# An accepted close or purchase releases it on the resulting checkpoint.
	# A submitted diplomacy order also keeps its dialog until the reply arrives.
	var diplomacy_pending: bool = not _management.is_empty() and _management.order[0] in ELDiplomacy.STRATEGIC_ORDERS
	if not remote_shop_open(link.local_player) and not diplomacy_pending: return true
	return _management.has("wait_revision") and _receiving_revision >= int(_management.wait_revision)

## Own the decoded save while the new guest connects. No saved connection or
## End Turn marker carries over into the new session.
func host_saved(restored: Dictionary, port: int, advertise := false) -> Error:
	_restored_host = restored
	var world: ELAdventureSession = restored.state
	var players: Array[int] = restored.players
	return link.host(profile, world.map.id, port, Vector2i(players[0], players[1]), world.difficulty, world.seed_value,
		world.day, int(restored.get("turn_seconds", 0)), int(restored.get("combat_seconds", 0)), advertise)

func resume_local(restored: Dictionary) -> void:
	_restored_host = restored
	link.open_local(restored.state.map, restored.players, restored.state.day)
	_started({"players": restored.players, "turn_seconds": restored.turn_seconds, "combat_seconds": restored.combat_seconds})

func leave_guest() -> void:
	_leaving = true
	link.send_leave()
	var deadline := Time.get_ticks_msec() + 900
	while link.live and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _can_replace_guest() -> bool:
	if not _world_open or director == null or not ELFirstScenario.alive(director.state, link.local_player): return false
	if relay.duel != null: return relay.error.is_empty()
	var night := director.strategy
	var phase: String = night.get("phase", "")
	# Keep the current night queue during movement and the later shop hold.
	if phase in ["movement", "combat"] or (phase == "use" and night.index == night.actors.size()):
		return director.error.is_empty() and director.state.outcome.is_empty()
	return director._map_idle() and director.movement.is_empty()

func _guest_departed(voluntary: bool) -> void:
	var guest := link.remote_player
	director.replace_strategy_guest(guest)
	_wire_ready.clear()
	_remote_shops.erase(guest)
	_site_cues.clear()
	_shop_visits.assign(_shop_visits.filter(func(visit: Array): return visit[2] != guest))
	if not _active_shop.is_empty() and _active_shop[2] == guest: _active_shop.clear()
	if relay.duel != null:
		relay.guest_departed()
		_guest_battle_ready = false
		_battle_deadline = 0
		# If the host is still opening its view, view_opened starts the battle.
		if _own_battle_ready and not battle_started: _battle_began()
	var commander_name := "Player %d" % guest
	for slot: Dictionary in director.state.map.players:
		if int(slot.attrs.id) == guest:
			var name_key := ELXml.value(slot, "name")
			if not name_key.is_empty(): commander_name = profile.text(name_key)
			break
	var notice_key := "T_MM_B_SURRENDER_CHANGE2AI" if voluntary else "T_MM_B_CONNECTION_LOST_CHANGE2AI"
	takeover_notice.emit(profile.text(notice_key).strip_edges() % commander_name)
	if relay.duel == null and director.strategy.is_empty() and turn_committed and not director.submit_strategy_turn(link.local_player, director.state.day):
		link.abort("End Turn was refused by the map.")

func _new_host_world(setup: Dictionary) -> Dictionary:
	var map := ELAdventureMap.new()
	var world := ELAdventureSession.new()
	var next := ELAdventureDirector.new()
	if not map.load_map(profile, setup.map) or not world.start(map, setup.difficulty, setup.seed, "", link.local_player) or not next.build(world):
		world.close()
		return {}
	return {"state": world, "director": next, "camera": {}}

func _started(setup: Dictionary) -> void:
	_setup = setup
	if not link.is_host: return
	var restored := _restored_host if not _restored_host.is_empty() else _new_host_world(setup)
	_restored_host = {}
	if restored.is_empty():
		link.abort("The strategic map could not be started.")
		return
	var world: ELAdventureSession = restored.state
	director = restored.director
	var players: Array[int] = []
	players.assign(setup.players)
	if not director.bind_strategy_players(players, link.local_authority):
		world.close()
		director = null
		link.abort("The strategic map could not be started.")
		return
	director.presentation.connect(_host_presentation)
	director.strategy_shop_wait = _wait_for_shop_visits
	world.event.connect(func(data: Dictionary):
		if data.kind == "mission_finished": _send_world = true
		elif data.kind == "pickup_taken" and data.player == link.remote_player:
			_guest_pickups.append([data.hero, data.id])
		elif data.kind == "hero_placed" and data.get("recruited", false) and world.object(data.id).owner == link.remote_player:
			_guest_recruit = data.id
		elif data.kind == "summon_cast":
			_summon_cues.append([data.id, data.spell])
		elif data.kind == "strategy_shop_visit":
			_shop_visits.append([data.hero, data.shop, data.player])
		elif data.kind == "resources_collected" and not link.local_authority and data.player == link.remote_player:
			_site_cues.append([data.id, data.player])
			_send_world = true
		elif data.kind == "building_used" and not link.local_authority and data.player == link.remote_player and ELAdditionalBuildings.is_strategic_visit(world.object(data.id)):
			if data.has("bonus"): _site_cues.append([data.id, data.player, data.hero, "spring", data.bonus])
			elif world.object(data.id).name in ELAdditionalBuildings.RUNE_VISITS: _site_cues.append([data.id, data.player, data.hero, "runes"])
			else: _site_cues.append([data.id, data.player, data.hero, "visit"])
			_send_world = true
		elif data.kind in ["site_captured", "shop_captured"] and not link.local_authority and link.remote_player in [data.player, data.previous]:
			if data.previous == link.remote_player and world.object(data.id).get("group") == "mana_nodes": return
			_site_cues.append([data.id, data.player, data.previous])
			_send_world = true
		elif data.kind == "remote_use" and director.strategy_shop_trade(data.player, data.hero, data.shop, true) != null:
			_remote_shops[data.player] = [data.hero, data.shop])
	_send_world = true
	_show_world(restored)

func _show_world(restored: Dictionary) -> void:
	_world_open = false
	world_ready.emit.call_deferred(restored)

func view_opened() -> void:
	_world_open = true
	if relay.duel == null or _own_battle_ready: return
	_own_battle_ready = true
	if link.local_authority: _battle_began()
	elif link.is_host: _start_battle_if_ready()
	elif not link.send_battle(relay.battle_id, ["ready", relay.digest()]):
		link.abort("The battle could not be confirmed.")

func can_plan() -> bool:
	return (link.live and _world_open and not turn_committed and _clock_expired_day != link.current_day
		and _management.is_empty() and not remote_shop_open(link.local_player)
		and director != null and director.state.day == link.current_day and ELFirstScenario.alive(director.state, link.local_player)
		and director.can_move() and director.movement.is_empty())

func clock_remaining() -> int:
	if _clock_day == 0 or _clock_day != link.current_day or turn_committed or _clock_expired_day == _clock_day: return -1
	return maxi(0, ceili(float(_clock_deadline - Time.get_ticks_msec()) / 1000.0))

func _clock_event(kind: String, day: int) -> void:
	if kind == "clock_open" and _clock_guest_day != day:
		_clock_guest_day = day
	elif kind == "clock_start" and _clock_day != day and _clock_view_day == day:
		_start_clock(day)
	elif kind == "clock_expire" and _clock_day == day and _clock_expired_day != day:
		_expire_clock(day)
	else:
		link.abort("The strategic clock could not be synchronized.")

func _start_clock(day: int) -> void:
	_clock_day = day
	_clock_deadline = Time.get_ticks_msec() + int(_setup.turn_seconds) * 1000

func _tick_clock() -> void:
	if int(_setup.get("turn_seconds", 0)) == 0 or director == null: return
	var day := link.current_day
	if not _world_open or director.state.day != day or not director.strategy.is_empty() or not director.state.outcome.is_empty(): return
	if _clock_view_day != day:
		# A night settlement notice can be in the checkpoint that opens the next day.
		if site_notice_open.is_valid() and site_notice_open.call(): return
		_clock_view_day = day
		if not link.is_host and not link.send_clock("clock_open", day):
			link.abort("The strategic clock could not be synchronized.")
			return
	if link.is_host and _clock_day != day and (link.local_authority or _clock_guest_day == day):
		if not link.local_authority and not link.send_clock("clock_start", day):
			link.abort("The strategic clock could not be synchronized.")
			return
		_start_clock(day)
	if _clock_day != day: return
	var now := Time.get_ticks_msec()
	if link.is_host and _clock_expired_day != day and now >= _clock_deadline:
		if not link.local_authority and not link.send_clock("clock_expire", day):
			link.abort("The strategic clock could not be synchronized.")
			return
		_expire_clock(day)
		_clock_ack_deadline = now + ELNetworkStrategy.CONNECT_TIMEOUT
	if _clock_expired_day != day: return
	if link.is_host and not link.local_authority and not link._remote_ready and now >= _clock_ack_deadline:
		link.abort("The other player did not finish the timed turn.")
		return
	if _world_open and not turn_committed and _management.is_empty() and director._map_idle() and director.movement.is_empty():
		if not link.set_ready(day, true): link.abort("The timed turn could not be ended.")

func _expire_clock(day: int) -> void:
	_clock_expired_day = day
	if link.is_host:
		for player: int in [link.local_player, link.remote_player]:
			if not director.is_strategy_human(player): continue
			var committed := link._local_ready if player == link.local_player else link._remote_ready
			if committed: continue
			var production: Dictionary = ELGlobalSpells.data(director.state, player).get("production", {})
			if production.get("state") == 2: ELGlobalSpells.cancel(director.state, player)
		_remote_shops.clear()
		_send_world = true
	else:
		_remote_shops.erase(link.local_player)
	if not turn_committed: turn_timeout.emit()

func can_save() -> bool:
	return link.can_checkpoint() and not _send_world and _remote_shops.is_empty() and relay.duel == null and can_plan()

func save_problem() -> String:
	if not link.is_host: return "The strategic host saves the match."
	if not _remote_shops.is_empty(): return "Finish the remote shop visit first."
	return "" if can_save() else "Save during planning, before either commander ends the turn."

func save(name: String, camera: Dictionary) -> String:
	var problem := save_problem()
	if not problem.is_empty(): return problem
	return ELSaveSlots.write_strategy(name, director, director.strategy_seats(), camera, int(_setup.turn_seconds), int(_setup.combat_seconds), link.local_authority)

func manage_hero(order: Array, completed: Callable) -> bool:
	if order.is_empty(): return false
	if order[0] in ELNetworkStrategy.VISIT_ORDERS:
		if not _management.is_empty() or not _matches_shop_visit(link.local_player, order): return false
	elif not can_plan(): return false
	var day := director.state.day
	if link.is_host:
		completed.call_deferred(_apply_management(link.local_player, day, order))
		return true
	if not link.submit_command(day, _next_request, order): return false
	_management = {"request": _next_request, "day": day, "order": order.duplicate(), "completed": completed}
	_management_deadline = Time.get_ticks_msec() + 15000
	_next_request += 1
	management_changed.emit()
	return true

func _accept_management(player: int, day: int, request: int, order: Array) -> void:
	var reason := _apply_management(player, day, order) if _world_open else "The strategic map is still loading."
	if not link.reply_command(day, request, reason.is_empty(), reason):
		link.abort("The hero order could not be confirmed.")

func _management_reply(day: int, request: int, accepted: bool, reason: String) -> void:
	if _management.get("request") != request or _management.get("day") != day or director.state.day != day:
		link.abort("A hero order reply arrived for a different turn.")
		return
	var kind: String = _management.order[0]
	if accepted and (kind in ELGlobalSpells.STRATEGIC_WORLD_ORDERS or kind in ELDiplomacy.STRATEGIC_ORDERS or kind in BUILDING_WORLD_ORDERS
		or (kind in ELNetworkStrategy.VISIT_ORDERS and remote_shop_open(link.local_player))):
		# The next checkpoint carries shared map changes without replaying the order.
		_management.wait_revision = link.snapshot_revision + 1
		return
	if accepted and not _next_world.is_empty():
		# A host refresh received before this acknowledgement does not yet
		# include the order. Apply it after installing that checkpoint.
		_management.wait_revision = _receiving_revision
		_management.replay_through = link.snapshot_revision
		return
	_complete_management(accepted, reason)

func _complete_management(replay: bool, reason: String) -> void:
	var pending := _management
	_management = {}
	_management_deadline = 0
	if replay:
		var local_reason := _apply_management(link.local_player, pending.day, pending.order)
		if not local_reason.is_empty():
			link.abort("The local hero inventory differs from the host.")
			return
	management_changed.emit()
	var completed: Callable = pending.completed
	if completed.is_valid(): completed.call_deferred(reason)

func local_shop_visit() -> Array:
	if not link.live or not _world_open: return []
	return _shop_visit(link.local_player)

func remote_shop_open(player: int) -> bool:
	return _remote_shops.has(player)

func _shop_visit(player: int) -> Array:
	if remote_shop_open(player): return _remote_shops[player].duplicate()
	return _active_shop.slice(0, 2) if not _active_shop.is_empty() and _active_shop[2] == player else []

func _matches_shop_visit(player: int, order: Array) -> bool:
	var visit := _shop_visit(player)
	return (link.live and _world_open and not visit.is_empty() and order.size() >= 3
		and ELLuaSave._integer(order[1], visit[0], visit[0])
		and ELLuaSave._integer(order[2], visit[1], visit[1]))

func _apply_management(player: int, day: int, order: Array) -> String:
	if link.is_host and day == _clock_expired_day and director.strategy.is_empty(): return "The planning timer has expired."
	var remote := remote_shop_open(player)
	if remote and order[0] not in ELNetworkStrategy.VISIT_ORDERS: return "Finish the remote shop visit first."
	if order[0] in ELDiplomacy.STRATEGIC_ORDERS:
		var result := director.manage_strategy_diplomacy(player, day, order)
		if link.is_host and result.is_empty(): _send_world = true
		return result
	if order[0] in ELGlobalSpells.STRATEGIC_ORDERS:
		var result := director.manage_strategy_spell(player, day, order)
		if link.is_host and order[0] in ELGlobalSpells.STRATEGIC_WORLD_ORDERS and result.is_empty(): _send_world = true
		return result
	if order[0] not in ELNetworkStrategy.VISIT_ORDERS:
		var result := director.manage_strategy_hero(player, day, order)
		if link.is_host and not link.local_authority and result.is_empty() and order[0] in BUILDING_WORLD_ORDERS: _send_world = true
		return result
	if not _matches_shop_visit(player, order): return "There is no active shop visit for this commander."
	var reason := ""
	if order[0] == "visit_close":
		if order.size() != 3: return "Invalid shop order."
	else:
		var purchase := order.duplicate()
		purchase[0] = str(order[0]).trim_prefix("visit_")
		reason = director.strategy_purchase(player, director.state.object(int(order[1])), purchase, remote)
	if reason.is_empty():
		if remote:
			_remote_shops.erase(player)
			if link.is_host: _send_world = true
		else:
			_active_shop = []
	return reason

## Resolve laboratory visits before component portals, then finish the night.
## The visiting commander alone gets the dialog and releases the shared hold.
func _wait_for_shop_visits() -> bool:
	if not _active_shop.is_empty(): return true
	while not _shop_visits.is_empty():
		var index := 0
		for i in _shop_visits.size():
			if director.state.object(_shop_visits[i][1]).get("type") == "el1_spell_shop":
				index = i
				break
		var next: Array = _shop_visits.pop_at(index)
		if director.strategy_shop_trade(next[2], next[0], next[1]) == null: continue
		_active_shop = next
		if next[2] == link.remote_player: _send_world = true
		return true
	return false

func move(hero: int, destination: Vector2i, target: int) -> bool:
	if not can_plan(): return false
	if target >= 0 and not _supported_target(target, hero):
		director.notice = "" if ELAdditionalBuildings.is_strategic_visit(director.state.object(target)) else "This map target is unavailable in the strategic preview."
		return false
	return _submit(hero, destination, target)

func cancel(hero: int) -> bool:
	return can_plan() and _submit(hero, Vector2i(-1, -1), -1)

func end_turn() -> bool:
	return can_plan() and link.set_ready(director.state.day, true)

func _submit(hero: int, destination: Vector2i, target: int) -> bool:
	var day := director.state.day
	var row := [[hero, destination.x, destination.y, target]]
	if link.is_host:
		_accepted = false
		return link.submit_plan(day, row) and _accepted
	# Give the guest the same path preview as the host. The host still checks
	# every order against the authoritative map and the sender's sight.
	var actor := director.state.object(hero)
	var previous: Dictionary = actor.get("strategy_order", {})
	var planned := director.cancel_order(hero) if destination.x < 0 else director.request_move(hero, destination, target)
	if not planned: return false
	if link.submit_plan(day, row): return true
	actor.strategy_order = previous
	director.presentation.emit({"kind": "route", "id": hero, "path": ELStrategy.order_path(director, actor)})
	return false

func _supported_target(id: int, hero: int) -> bool:
	var state := director.state
	var item := state.object(id)
	if ELAdditionalBuildings.is_strategic_visit(item):
		return ELAdditionalBuildings.visit_problem(state, state.object(hero), item).is_empty()
	return (item.get("type") in ["hero", "monster", "rune_shop", "el1_spell_shop", "fort"]
		or item.get("group") == "resource_cuts" or ELResourceSites.TYPES.has(item.get("group"))
		or ELFirstScenario.is_castle(item) or ELMapPickups.is_pickup(item))

func _accept_plan(player: int, day: int, plan: Array) -> void:
	if day == _clock_expired_day or remote_shop_open(player): return
	var row: Array = plan[0]
	if row[3] >= 0 and not _supported_target(row[3], row[0]): return
	_accepted = director.cancel_strategy_move(player, day, row[0]) if row[1] < 0 else director.plan_strategy_move(player, day, row[0], Vector2i(row[1], row[2]), row[3])

func _ready_changed(player: int, day: int, _committed: bool) -> void:
	if remote_shop_open(player):
		link.abort("Finish the remote shop visit first.")
		return
	if player == link.local_player:
		turn_committed = true
		if not link.local_authority: message.emit("Waiting for the other commander…")
	if not link.is_host: return
	if link.local_authority:
		if not director.submit_strategy_turn(player, day): link.abort("End Turn was refused by the map.")
		return
	_wire_ready.append(player)
	for commander: int in _wire_ready:
		if not ELFirstScenario.alive(director.state, commander) or director.strategy_ready(commander): continue
		var other := link.remote_player if commander == link.local_player else link.local_player
		if not ELFirstScenario.alive(director.state, other) and not _wire_ready.has(other): continue
		if not director.submit_strategy_turn(commander, day):
			link.abort("End Turn was refused by the map.")
			return
		if not director.strategy.is_empty():
			_wire_ready.clear()
			return

func _host_presentation(data: Dictionary) -> void:
	if data.kind == "encounter":
		var encounter := director.encounter
		_battle_id += 1
		_clear_battle()
		var forfeit := link.local_authority and director.strategic_forfeit_winner(encounter.hero_id, encounter.opponent_id) >= 0
		var guest_side := -1 if link.local_authority and not forfeit else _side_of(link.remote_player)
		if not relay.attach(_battle_id, encounter.battle, true, _side_of(link.local_player), guest_side, int(_setup.combat_seconds)):
			link.abort("The strategic battle could not be opened.")
			return
		if forfeit: relay.guest_departed()
		if not link.local_authority: _battle_deadline = Time.get_ticks_msec() + 45000
		_send_world = true
	elif data.kind == "strategy_phase" and data.phase == "planning":
		turn_committed = false
		_send_world = true

func _side_of(player: int) -> int:
	var encounter := director.encounter
	if int(director.state.object(encounter.hero_id).owner) == player: return 0
	if int(director.state.object(encounter.opponent_id).owner) == player: return 1
	return -1

func _publish_world() -> void:
	var document := _codec.encode(director)
	if document.is_empty():
		link.abort("The strategic map could not be synchronized.")
		return
	var player := link.remote_player
	document.world.current_player = player
	document.world.main_hero = -1
	for actor: Dictionary in director.state.objects.values():
		if actor.type == "hero" and actor.owner == player and actor.alive:
			document.world.main_hero = actor.uid
			break
	if not document.world.outcome.is_empty():
		document.world.outcome = "win" if ELFirstScenario.alive(director.state, player) else "lose"
	var visit := _active_shop.slice(0, 2) if not _active_shop.is_empty() and _active_shop[2] == player else []
	# Earlier builds read only the notice shapes they know how to present.
	var turns := _site_cues.filter(func(cue: Array) -> bool: return cue.size() != 4 or cue[3] != "runes")
	var settlements := turns.filter(func(cue: Array) -> bool: return cue.size() < 5)
	var legacy_sites := settlements.filter(func(cue: Array) -> bool: return cue.size() < 4)
	var captures := legacy_sites.filter(func(cue: Array) -> bool: return cue.size() == 3)
	var shops := captures.filter(func(cue: Array) -> bool:
		return director.state.object(int(cue[0])).get("type") in SHOP_CAPTURE_TYPES)
	var checkpoint := {"world": document, "battle": relay.battle_id, "pickups": _guest_pickups,
		"shop": visit, "captures": captures, "shop_captures": shops, "remote_shop": _remote_shops.get(player, []),
		"recruit": _guest_recruit, "summons": _summon_cues}
	if captures.size() != legacy_sites.size(): checkpoint.site_notices = legacy_sites
	if legacy_sites.size() != settlements.size(): checkpoint.settlement_notices = settlements
	if settlements.size() != turns.size(): checkpoint.turn_notices = turns
	if turns.size() != _site_cues.size(): checkpoint.action_notices = _site_cues
	if link.publish_snapshot(director.state.day, checkpoint):
		_guest_pickups.clear()
		_guest_recruit = -1
		_summon_cues.clear()
		_site_cues.clear()
	else:
		link.abort("The strategic checkpoint could not be sent.")

func _received_world(day: int, document: Dictionary) -> void:
	if not document.get("world") is Dictionary or not ELLuaSave._integer(document.get("battle"), 0, 0x7fffffff):
		link.abort("Invalid strategic checkpoint.")
		return
	var summons: Variant = document.get("summons", [])
	if not summons is Array or _summon_cues.size() + summons.size() > 32:
		link.abort("Invalid strategic summon cues.")
		return
	for cue: Variant in summons:
		if not cue is Array or cue.size() != 2 or not ELLuaSave._integer(cue[0], 0, 0x7fffffff) or not ELGlobalSpells.SUMMONS.has(cue[1]):
			link.abort("Invalid strategic summon cue.")
			return
	var sites: Variant = []
	for key: String in ["action_notices", "turn_notices", "settlement_notices", "site_notices", "captures", "shop_captures"]:
		if document.has(key):
			sites = document[key]
			break
	if not sites is Array or _site_cues.size() + sites.size() > MAX_SITE_NOTICES:
		link.abort("Invalid strategic site notices.")
		return
	for cue: Variant in sites:
		if (not cue is Array or cue.size() not in [2, 3, 4, 5] or not ELLuaSave._integer(cue[0], 0, 0x7fffffff)
			or not ELLuaSave._integer(cue[1], 1, 32)):
			link.abort("Invalid strategic site notice.")
			return
		if cue.size() == 2:
			if int(cue[1]) == link.local_player: continue
		elif cue.size() >= 4:
			if int(cue[1]) == link.local_player and ELLuaSave._integer(cue[2], 0, 0x7fffffff):
				if cue.size() == 4 and cue[3] in ["visit", "runes"]: continue
				if cue.size() == 5 and cue[3] == "spring" and ELLuaSave._integer(cue[4], 0, 0x1fffffff): continue
		elif (ELLuaSave._integer(cue[2], -1, 32) and int(cue[1]) != int(cue[2])
			and link.local_player in [int(cue[1]), int(cue[2])]): continue
		link.abort("Invalid strategic site notice.")
		return
	_summon_cues.append_array(summons)
	_site_cues.append_array(sites)
	_next_world = document
	_receiving_day = day
	_receiving_revision = link.snapshot_revision

func _open_snapshot() -> void:
	var document := _next_world
	_next_world = {}
	var raw: Dictionary = document.world
	if raw.get("map") != _setup.map or raw.get("world", {}).get("day") != _receiving_day or raw.get("world", {}).get("current_player") != link.local_player:
		link.abort("The strategic checkpoint does not match this map or commander.")
		return
	var restored := _codec.decode(raw, {"el1": profile})
	if restored.is_empty():
		link.abort("The strategic checkpoint could not be restored.")
		return
	var pickups: Variant = document.get("pickups", [])
	var pickup_notices: Variant = _pickup_notices(restored.state, pickups)
	if pickup_notices == null:
		restored.state.close()
		link.abort("The strategic pickup results are invalid.")
		return
	restored.pickup_notices = pickup_notices
	var world: ELAdventureSession = restored.state
	var site_notices: Array[Dictionary] = []
	for cue: Array in _site_cues:
		var item := world.object(int(cue[0]))
		if cue.size() >= 4:
			var hero := world.object(int(cue[2]))
			var types: Array
			match cue[3]:
				"spring": types = ELAdditionalBuildings.WEEKLY_VISITED
				"runes": types = ELAdditionalBuildings.RUNE_VISITS
				_: types = ELAdditionalBuildings.OWNED
			if item.get("group") != "additional_buildings" or item.get("name") not in types or hero.get("type") != "hero" or hero.get("owner") != link.local_player:
				world.close()
				link.abort("Invalid strategic building visit notice.")
				return
			var visit := {"bonus": int(cue[4])} if cue.size() == 5 else {}
			site_notices.append(ELAdditionalBuildings.visit_notice(profile, hero, item, visit))
			continue
		if cue.size() == 2:
			if item.get("group") != "resource_cuts" or item.alive:
				world.close()
				link.abort("Invalid strategic resource pile notice.")
				return
			var amounts := ELResources.read_node(profile.id, ELXml.child(item.node, "resources"))
			site_notices.append({"kind": "resources_collected", "player": int(cue[1]), "amounts": amounts})
			continue
		if ((item.get("type") not in SHOP_CAPTURE_TYPES and not ELResourceSites.TYPES.has(item.get("group")))
			or not world.players.has(int(cue[1])) or (cue[2] > 0 and not world.players.has(int(cue[2])))):
			world.close()
			link.abort("Invalid strategic capture notice.")
			return
		site_notices.append({"kind": "site_captured", "id": int(cue[0]), "player": int(cue[1]), "previous": int(cue[2])})
	restored.site_notices = site_notices
	_site_cues.clear()
	var recruit: Variant = document.get("recruit", -1)
	if not ELLuaSave._integer(recruit, -1, 0x7fffffff) or (recruit >= 0 and restored.state.object(int(recruit)).get("owner") != link.local_player):
		restored.state.close()
		link.abort("The strategic recruit is invalid.")
		return
	restored.recruit = int(recruit)
	for cue: Array in _summon_cues:
		if restored.state.object(int(cue[0])).get("type") != "hero":
			restored.state.close()
			link.abort("The strategic summon is invalid.")
			return
	restored.summons = _summon_cues.duplicate()
	_summon_cues.clear()
	var visit: Variant = document.get("shop", [])
	var remote: Variant = document.get("remote_shop")
	if not _valid_shop_visit(restored.director, visit, false) or not _valid_shop_visit(restored.director, remote, true):
		restored.state.close()
		link.abort("The strategic shop visits are invalid.")
		return
	_active_shop = [] if visit.is_empty() else [int(visit[0]), int(visit[1]), link.local_player]
	if remote.is_empty(): _remote_shops.erase(link.local_player)
	else: _remote_shops[link.local_player] = [int(remote[0]), int(remote[1])]
	if observes_battle() and _observer_note_until > 0:
		_observer_note_until = Time.get_ticks_msec() + OBSERVED_RESULT_MS
	_clear_battle()
	var same_planning: bool = (director != null and director.state.day == _receiving_day
		and director.strategy.is_empty() and restored.director.strategy.is_empty())
	restored.strategic_refresh = same_planning
	if same_planning: _keep_planning_routes(restored.state)
	director = restored.director
	turn_committed = not director.strategy.is_empty() or (same_planning and turn_committed)
	var id := int(document.battle)
	if ((director.encounter != null) != (id > 0) or (id > 0 and not relay.attach(id, director.encounter.battle, false,
		_side_of(link.remote_player), _side_of(link.local_player), int(_setup.combat_seconds)))):
		director.state.close()
		director = null
		link.abort("The strategic battle does not match its checkpoint.")
		return
	if _management.has("wait_revision") and _receiving_revision >= int(_management.wait_revision):
		_complete_management(_receiving_revision <= int(_management.get("replay_through", -1)), "")
	_show_world(restored)

func _keep_planning_routes(next: ELAdventureSession) -> void:
	for actor: Dictionary in director.state.objects.values():
		if actor.type != "hero" or not actor.alive or actor.owner != link.local_player: continue
		var current := next.object(actor.uid)
		# A cast can recall or hold a hero and clear its existing orders.
		if (current.get("alive", false) and current.get("owner") == link.local_player
			and current.x == actor.x and current.y == actor.y and not ELGlobalSpells.held(current)
			and not ELGlobalSpells.hero_has(current, ELGlobalSpells.WARRIOR)):
			current.strategy_order = actor.get("strategy_order", {}).duplicate()

func _pickup_notices(world: ELAdventureSession, pickups: Variant) -> Variant:
	if pickups is not Array or pickups.size() > world.objects.size(): return null
	var notices: Array[Dictionary] = []
	for pair: Variant in pickups:
		if pair is not Array or pair.size() != 2 or not ELLuaSave._integer(pair[0], 0, 0x7fffffff) or not ELLuaSave._integer(pair[1], 0, 0x7fffffff): return null
		var hero := world.object(int(pair[0]))
		var item := world.object(int(pair[1]))
		if hero.get("owner") != link.local_player or not ELMapPickups.is_pickup(item) or item.alive: return null
		notices.append(ELMapPickups.pickup_notice(world, hero, item))
	return notices

func _valid_shop_visit(next: ELAdventureDirector, visit: Variant, remote: bool) -> bool:
	if visit is not Array: return false
	if visit.is_empty(): return true
	if (visit.size() != 2 or not ELLuaSave._integer(visit[0], 0, 0x7fffffff)
		or not ELLuaSave._integer(visit[1], 0, 0x7fffffff)): return false
	if remote:
		if not next.strategy.is_empty(): return false
	elif next.strategy.get("phase") != "use" or int(next.strategy.index) != next.strategy.actors.size():
		return false
	return next.strategy_shop_trade(link.local_player, int(visit[0]), int(visit[1]), remote) != null

func _received_battle(id: int, payload: Array) -> void:
	if id != relay.battle_id or relay.duel == null:
		link.abort("A command arrived for a different strategic battle.")
	elif link.is_host and payload.size() == 2 and payload[0] == "ready" and not _guest_battle_ready and payload[1] == relay.digest():
		_guest_battle_ready = true
		_start_battle_if_ready()
	elif not link.is_host and payload == ["go"] and _own_battle_ready and not battle_started:
		_battle_began()
	elif not battle_started or not relay.receive(id, payload):
		link.abort("The strategic battle command was refused.")

func _start_battle_if_ready() -> void:
	if battle_started or not (_own_battle_ready and _guest_battle_ready): return
	if link.send_battle(relay.battle_id, ["go"]):
		_battle_deadline = 0
		_battle_began()
	else: link.abort("The strategic battle could not start.")

func observes_battle() -> bool:
	return relay.duel != null and relay.local_side < 0

func observer_battle_note() -> String:
	return _observer_note if _observer_note_until == 0 or Time.get_ticks_msec() < _observer_note_until else ""

func _battle_began() -> void:
	battle_started = true
	_observer_note_until = 0
	_observer_note = _observer_text("T_ADV_INFO_START_BATTLE", "Battle starts: %s") if observes_battle() else ""

func _observer_text(key: String, fallback: String) -> String:
	var state := director.state
	var name := ELFirstScenario.player_name(state, link.remote_player).strip_edges()
	return ELFirstScenario.text(state, key, fallback).strip_edges().replace("%s", name)

func _tick_battle(delta: float) -> void:
	relay.poll(_presentation_idle())
	if not observes_battle(): return
	if relay.result_confirmed():
		if _observer_note_until == 0:
			_observer_note = _observer_text("T_ADV_INFO_END_BATTLE", "Battle ends: %s")
			_observer_note_until = Time.get_ticks_msec() + OBSERVED_RESULT_MS
		if link.is_host and _finished and not finish_battle():
			link.abort("The strategic battle could not be settled.")
	elif link.is_host:
		_observer_ai_clock += delta
		if _observer_ai_clock >= 0.85:
			_observer_ai_clock = 0.0
			relay.step_neutral_ai()

func finish_battle() -> bool:
	if not link.is_host or not _finished: return false
	_clear_battle()
	return director.finish_encounter()

func _clear_battle() -> void:
	relay.detach()
	battle_started = false
	_own_battle_ready = false
	_guest_battle_ready = false
	_finished = false
	_battle_deadline = 0
	_observer_ai_clock = 0.0
