extends SceneTree
## Headless check of second-game map feedback (issues #145-#147, #149, #161):
## - every magic bridge piece (TerrObj SpecEffect 111-118) in sight runs its
##   colour's pier/abutment effect at its figure, turned with it, and a
##   hidden piece has none;
## - every additional building with a row Effect (altars, sacred places)
##   glows from the start, also out of sight in explored fog;
## - a fort with a garrison is ringed by the twelve Intercept5x5 guard-zone
##   pieces on the 5x5 square's edge until the garrison leaves;
## - a resource pile the human player's hero takes puts T_TAKE_PLUHA with the
##   amount and the resource on the message line, which keeps it 5 s and fades
##   it over 0.5 s; another player's pile adds nothing;
## - scripted camera moves fly: every 64 ms the look-at point covers
##   0.25 x AutoScrollAcceleration of the way left; the "Instant" commands
##   jump. Mouse edge panning can interrupt a flight.
##
##   godot --headless --path game --script ../tools/second_map_feedback_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped. Saves the map writes are put back as they were.

const MAP := "e2mission12_52"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _map_part()
	print("SECOND MAP FEEDBACK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _map_part() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: the second game's files could not be mounted")
		return
	# The chapter map with bridges, a fort and resource piles, from its campaign.
	var row := {}
	for campaign_id: String in ["Green", "Red", "Blue", "Black"]:
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if row.is_empty() and str(scenario.file_name).to_lower() == MAP:
				row = scenario.duplicate()
				row.campaign = campaign_id
				var progress := ELSecondCampaign.for_chapter(profile, campaign_id, row, campaign.scenarios.find(scenario) + 1)
				if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
	if row.is_empty():
		print("SKIP: no %s chapter" % MAP)
		return
	var saves := _backup(ELSaveSlots.folder("el2"))
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built, "the %s map builds: %s" % [MAP, view.error])
	if built:
		var curtain := view.ui.get_node_or_null("MissionFade") as ColorRect
		check(curtain != null and curtain.color == Color.BLACK, "#176: a new mission starts behind a black fade")
		await _wait_for_fade(view)
		await create_timer(view.director.script_tick() * 2.0).timeout
		var state := view.state
		ELFog.reveal_for_console(state, 1, true)
		await frames(3)
		_bridges(view, profile)
		await _altars(view, profile)
		await _garrison(view)
		_messages(view, profile)
		await _change_effect_message(view, profile)
		await _camera(view)
		_pickup_transition(view)
		_fog_region(view.world)
		_actor_facing(view)
		await _new_map_reports(view)
	view.queue_free()
	await frames(2)
	await _mine_depletion(profile, settings)
	await _opening_and_rewards(profile, settings)
	await _runestones(profile, settings)
	_restore(ELSaveSlots.folder("el2"), saves)

func _wait_for_fade(view: ELAdventureView) -> void:
	if view._mission_fade != null: await view._mission_fade.tree_exited

func _space(pressed := true, echo := false) -> void:
	_dialogue_key(KEY_SPACE, pressed, echo)

func _dialogue_key(code: Key, pressed := true, echo := false) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = pressed
	key.echo = echo
	root.push_input(key)

func _move_pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func _experience_tooltip(view: ELAdventureView) -> void:
	var hud := view.second_hud
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	await create_timer(delay + 0.1).timeout
	check(hud.experience_tip.visible and hud.experience_tip.get_rect().end.y < hud.experience_bar.position.y,
		"#226: hovering during the opening fade shows the XP tooltip above the bar after the dialogue")
	view.open_options()
	await frames(2)
	check(not hud.experience_tip.visible, "#226: Options hides the XP tooltip even if the pointer does not move")
	view.close_options()
	_move_pointer(Vector2(400, 350))
	root.notify_mouse_exited()

func _opening_and_rewards(profile: ELProfile, settings: ELSettings) -> void:
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, {"file_name": "e2mission11"}, settings, 1)
	check(built, "#206: the Vitals map builds for the opening test")
	if built:
		var state := view.state
		var calls := {"steps": 0}
		state.vm.bind("Hook_Wake", func(_args: Array) -> Array: return [])
		state.vm.bind("Hook_OnStep", func(_args: Array) -> Array:
			calls.steps += 1
			if calls.steps == 1: state._native(["Opening line"], "ExMessageBoxStandard")
			return [])
		await frames(2)
		root.notify_mouse_entered()
		var bar := view.second_hud.experience_bar
		_move_pointer(bar.get_global_transform_with_canvas() * (bar.size * 0.5))
		_space()
		await create_timer(0.3).timeout
		_space(true, true)
		check(view._mission_fade != null and calls.steps == 0 and view.director._clock == 0.0
			and not view.second_dialogue.visible, "#206: the mission clock and opening script wait throughout the fade")
		await _wait_for_fade(view)
		await create_timer(view.director.script_tick() * 2.0).timeout
		_space(true, true)
		check(view._mission_fade == null and calls.steps == 1 and view.second_dialogue.visible
			and not view.director.dialogue.is_empty(), "#206: the opening appears after the fade and a held key cannot dismiss it")
		_space(false)
		_space()
		_space(false)
		check(view.director.dialogue.is_empty(), "#206: a fresh press answers the opening dialog")
		await _experience_tooltip(view)
		_reward_hotkeys(view)
		await _battle_rewards(view, profile)
	view.queue_free()
	await frames(2)

func _reward_hotkeys(view: ELAdventureView) -> void:
	# An open notice owns its confirmation before a focused control behind it.
	var behind := Button.new()
	view.ui.add_child(behind)
	var presses := [0]
	behind.pressed.connect(func(): presses[0] += 1)
	for report: Dictionary in [
		{"key": "T_MB_LOOT_MONSTER_OR_HERO_1", "loot": true},
		{"key": "T_MB_RECEIVE_LOOT", "loot": [{"kind": "spell", "card": "GRSN"}]}]:
		for code: Key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			behind.grab_focus()
			view.director.presentation.emit(report.merged({"kind": "building_message", "hero": -1, "building": -1,
				"text": view.state.map.profile.text(report.key)}))
			var opened: bool = view.building_message != null and view.building_message.data.key == report.key
			_dialogue_key(code)
			_dialogue_key(code, false)
			check(opened and view.building_message == null, "#214: %s closes %s" % [OS.get_keycode_string(code), report.key])
			if view.building_message != null: view._close_building_message()
	check(presses[0] == 0, "#214: reward keys never activate a focused button behind the report")
	behind.queue_free()

func _battle_rewards(view: ELAdventureView, profile: ELProfile) -> void:
	var state := view.state
	var hero := state.object(state.main_hero)
	var opponent := {}
	for item: Dictionary in state.objects.values():
		if item.type == "monster" and item.alive and item.visible and int(item.owner) != state.current_player:
			opponent = item
			break
	if hero.is_empty() or opponent.is_empty():
		check(false, "#207: the chapter has a hero and a neutral opponent")
		return
	# An ordinary level still queues the skill choice, without the stars.
	hero.experience = ELHeroProgression.threshold(profile, 3) - 1
	view._on_encounter_finishing()
	state.add_experience(int(hero.uid), 1)
	view._on_encounter_finished(int(hero.uid))
	check(int(hero.level) == 3 and view._reward_cues.is_empty() and view._battle_level_hero == int(hero.uid),
		"#234: an ordinary level-up keeps the skill choice without the appearance cue")
	var level := int(hero.level)
	hero.experience = ELHeroProgression.threshold(profile, level + 1) - 1
	var encounter := ELAdventureEncounter.new()
	if not encounter.prepare(state, int(hero.uid), int(opponent.uid)) or encounter.battle == null:
		check(false, "#207: the encounter can be prepared: " + encounter.error)
		return
	state.vm.bind("Hook_OnBattleFinishing", func(_args: Array) -> Array:
		state._native([], "ExStartLootMessage")
		state._native(["GRSN"], "ExAddLootMessageSpell")
		state._native([], "ExSendLootMessage")
		return [1.0])
	view.director.encounter = encounter
	view.set_suspended(true)
	encounter.battle.heroes[1].health = 0
	encounter.battle._check_winner()
	check(view.director.finish_encounter() and int(hero.level) > level and view.building_messages.size() == 2,
		"#207: the win awards a level and queues the XP and loot reports")
	check(view.building_message == null and not view.effects.effects.has(ELAdventureView.REWARD_EFFECT),
		"#207: the reward animation and dialogs wait while the map is hidden")
	view.set_suspended(false)
	var effects_seen := {}
	var until := Time.get_ticks_msec() + 7000
	while view.building_message == null and Time.get_ticks_msec() < until:
		var effect: Dictionary = view.effects.effects.get(ELAdventureView.REWARD_EFFECT, {})
		if not effect.is_empty(): effects_seen[effect.entry.file] = true
		await process_frame
	check(effects_seen.has(ELAdventureView.LEVEL_EFFECT) and effects_seen.has(ELAdventureView.LOOT_EFFECT)
		and not view.effects.effects.has(ELAdventureView.REWARD_EFFECT), "#207: both original reward effects play before any dialog")
	check(view.audio.played.has("Magic/GlobalCast.wav") and view.audio.played.has("Adventure/stars1.wav"), "#207: the reward cues play their original sounds")
	if view.building_message == null:
		check(false, "#207: the reward dialogs open after the effects")
		return
	check(view.building_message.data.key == "T_MB_LOOT_MONSTER_OR_HERO_1", "#207: the XP report opens first")
	_space()
	_space(true, true)
	check(view.building_message == null and view.skills == null and not view._can_act(), "#207: the reports are separated by an input gap")
	await create_timer(ELAdventureView.REWARD_DIALOG_GAP + 0.15).timeout
	_space(true, true)
	check(view.building_message != null and view.building_message.data.key == "T_MB_RECEIVE_LOOT", "#207: holding Space cannot dismiss the next report")
	_space(false)
	_space()
	_space(false)
	check(view.building_message == null and view.skills == null, "#207: the skill dialog also waits after the loot report closes")
	await create_timer(ELAdventureView.REWARD_DIALOG_GAP + 0.15).timeout
	check(view.skills is ELSecondLevelUpView, "#207: the level-up choice follows the battle rewards")

func _actor_facing(view: ELAdventureView) -> void:
	var state := view.state
	var world := view.world
	var placed_angles := {}
	for item: Dictionary in state.objects.values():
		if not item.get("type") in ["hero", "monster"] or not world.actors.has(item.uid): continue
		placed_angles[int(item.rotation)] = world.object_yaw(item)
	check(placed_angles.size() == 4 and range(4).all(func(quarter: int) -> bool:
		return is_equal_approx(wrapf(float(placed_angles.get(quarter * 4, INF)) + quarter * PI / 2.0, -PI, PI), 0.0)),
		"the second game's units start at the four headings authored in the map")
	var hero := state.object(view._hero_id())
	var id := int(hero.uid)
	var before: ELModel = world.actors[id]
	var old_rotation := int(hero.rotation)
	world.orient_actor(id, Vector2.UP + Vector2.RIGHT)
	var heading := world.object_yaw(hero)
	hero.ship = not hero.ship
	state.event.emit({"kind": "shape_changed", "id": id})
	check(world.actors[id] != before and is_equal_approx(world.object_yaw(hero), heading), "the hero keeps its facing when its land or ship model replaces the other")
	state._native([id, old_rotation], "ExSetRotateMirror")
	check(is_equal_approx(wrapf(world.object_yaw(hero) + float((old_rotation >> 2) & 3) * PI / 2.0, -PI, PI), 0.0),
		"the script can restore the hero's placed direction even when the stored rotation is already the same")
	hero.ship = not hero.ship
	state.event.emit({"kind": "shape_changed", "id": id})

func _bridges(view: ELAdventureView, profile: ELProfile) -> void:
	var state := view.state
	var rows := profile.table("TerrObj")
	var pieces: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("group") == "terrain_objects" and int(rows.get(item.name, {}).get("SpecEffect", 0)) in range(111, 119): pieces.append(item)
	check(not pieces.is_empty(), "the map has magic bridge pieces (%d)" % pieces.size())
	var effects := view.effects
	var wrong: Array = []
	var names := {}
	for item: Dictionary in pieces:
		var name := "spec:%d" % int(item.uid)
		var expected := str(ELAdventureEffects.SPEC_EFFECTS[int(rows[item.name].SpecEffect)]) + ".pfx"
		if not item.get("visible", true): continue
		names[expected] = true
		if not effects.effects.has(name) or str(effects.effects[name].entry.file) != expected:
			wrong.append("%s@%d,%d" % [item.name, item.x, item.y])
			continue
		var center := ELAdventureGrid.center(item, rows[item.name]) * ELAdventureTerrain.CELL
		var node: Node3D = effects.effects[name].node
		if node.position.distance_to(Vector3(center.x, 0, -center.y)) > 0.01 or not is_equal_approx(node.rotation.y, -float((int(item.rotation) >> 2) & 3) * PI / 2.0):
			wrong.append("%s placed at %s" % [item.name, node.position])
	check(wrong.is_empty(), "each bridge piece in sight runs its effect at its figure: %s (%s)" % [str(wrong), ", ".join(names.keys())])
	check(range(111, 119).all(func(kind: int) -> bool: return profile.archives.pfx.has(ELArchive.key(str(ELAdventureEffects.SPEC_EFFECTS[kind]) + ".pfx"))), "the eight pier and abutment effects exist")
	var piece: Dictionary = pieces[0]
	piece.visible = false
	state.event.emit({"kind": "object_changed", "id": piece.uid})
	check(not effects.effects.has("spec:%d" % int(piece.uid)), "a hidden bridge piece stops its effect")
	piece.visible = true
	state.event.emit({"kind": "object_changed", "id": piece.uid})
	check(effects.effects.has("spec:%d" % int(piece.uid)), "and shown again it starts it")

## Every additional building whose row names an Effect glows from the start
## (the chapter's Nature Shrine E2Green8 and Source of Life included), also in
## explored fog out of sight, as its figure is still drawn there.
func _altars(view: ELAdventureView, profile: ELProfile) -> void:
	var state := view.state
	var effects := view.effects
	var glowing: Array = []
	var dark: Array = []
	for item: Dictionary in state.objects.values():
		var file := ELAdventureEffects.building_effect(profile, item)
		if file.is_empty() or not item.get("alive", true) or not item.get("visible", true): continue
		var name := "shrine:%d" % int(item.uid)
		if effects.effects.has(name) and str(effects.effects[name].entry.file) == file: glowing.append(item.name)
		else: dark.append("%s@%d,%d" % [item.name, item.x, item.y])
	check(glowing.has("E2Green8") and glowing.has("SourceOfLife") and dark.is_empty(), "every building with a row Effect glows: %s, none without: %s" % [str(glowing), str(dark)])
	var altar := {}
	for item: Dictionary in state.objects.values():
		if item.get("name") == "E2Green8": altar = item
	if altar.is_empty(): return
	# Out of sight in explored fog: the figure stays drawn, and so does its glow.
	ELFog.reveal_for_console(state, 1, false)
	var seen: PackedByteArray = state.fog.get("visible", PackedByteArray())
	for y in range(int(altar.y) - 3, int(altar.y) + 4):
		for x in range(int(altar.x) - 3, int(altar.x) + 4):
			var index := y * state.map.width + x
			if x < 0 or y < 0 or x >= state.map.width or y >= state.map.height: continue
			state.explored[index] |= ELFog.bit(1)
			if index < seen.size(): seen[index] &= ~ELFog.bit(1)
	state.fog.visible = seen
	state.fog.revision = ELFog.revision(state) + 1
	await frames(2)
	var remembered := ELFog.object_state(state, 1, altar) == ELFog.REMEMBERED
	check(remembered and effects.effects.has("shrine:%d" % int(altar.uid)), "out of sight in explored fog the Nature Shrine keeps its glow (remembered: %s)" % remembered)
	ELFog.reveal_for_console(state, 1, true)
	await frames(2)

func _garrison(view: ELAdventureView) -> void:
	var state := view.state
	var fort := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "fort" and item.get("alive", false): fort = item
	var hero := state.object(state.main_hero)
	check(not fort.is_empty() and not hero.is_empty(), "the map has a fort and a main hero")
	if fort.is_empty() or hero.is_empty(): return
	var ring := func() -> Dictionary:
		var found := {}
		for name: String in view.effects.effects:
			if name.begins_with("ring:%d:" % int(fort.uid)): found[str(view.effects.effects[name].entry.file)] = view.effects.effects[name].node.position
		return found
	if int(fort.garrison) >= 0: ELForts.leave(state, int(fort.garrison))
	await frames(2)
	check(ring.call().is_empty(), "an empty fort has no guard-zone ring")
	ELForts.occupy(state, hero, fort)
	await frames(2)
	var pieces: Dictionary = ring.call()
	check(pieces.size() == 12 and pieces.has("Intercept5x5_00.pfx") and pieces.has("Intercept5x5_11.pfx"), "an occupied fort is ringed by the twelve Intercept5x5 pieces (%d)" % pieces.size())
	# Piece 0 sits at the fort's y + 2, piece 6 at y - 2, piece 3 at x + 2, piece 9 at x - 2.
	var expect := {"Intercept5x5_00.pfx": Vector2i(0, 2), "Intercept5x5_06.pfx": Vector2i(0, -2), "Intercept5x5_03.pfx": Vector2i(2, 0), "Intercept5x5_09.pfx": Vector2i(-2, 0)}
	var placed := true
	for file: String in expect:
		var cell: Vector2i = Vector2i(int(fort.x), int(fort.y)) + expect[file]
		if not pieces.has(file) or (pieces[file] as Vector3).distance_to(ELAdventureScene.world_position(float(cell.x), float(cell.y))) > 0.01: placed = false
	check(placed, "each piece stands on its ring cell")
	# An owned fort flies its flag (the fort figure's own raise / wave clips).
	var figure: ELModel = view.world.object_models.get(int(fort.uid))
	check(int(fort.get("owner", -1)) >= 1 and figure != null and figure.clip in ["utap", "cidleintap"] and bool(figure.get_meta("flag_up", false)), "an owned fort raises its flag (owner %s, clip %s)" % [fort.get("owner", -1), figure.clip if figure != null else "none"])
	if figure != null:
		view.world.fort_flag(figure, false)
		check(figure.clip == "uuntap" and not bool(figure.get_meta("flag_up", true)), "a fort losing its owner lowers the flag")
		view.world.fort_flag(figure, true)
	ELForts.leave(state, int(hero.uid))
	await frames(2)
	check(ring.call().is_empty(), "and the ring goes when the garrison leaves")

func _messages(view: ELAdventureView, profile: ELProfile) -> void:
	var hud := view.second_hud
	check(hud != null and hud.has_method("add_message"), "the second-game panel has a message line")
	if hud == null or not hud.has_method("add_message"): return
	hud.messages.clear()
	var state := view.state
	var line := profile.text("T_TAKE_PLUHA").strip_edges().replace("%d", "3")
	state.event.emit({"kind": "resources_collected", "id": -1, "player": 2, "amounts": {"Herbs": 0, "Gems": 3, "Flames": 0}})
	check(hud.messages.is_empty(), "another player's pile adds no line")
	state.event.emit({"kind": "resources_collected", "id": -1, "player": 1, "amounts": {"Herbs": 0, "Gems": 3, "Flames": 0}})
	check(hud.message_texts() == [line] and hud.messages[0].resource == "Gems", "the human player's pile adds «%s» with its resource: %s" % [line, str(hud.message_texts())])
	hud.add_message("second")
	hud.advance_messages(4.9)
	check(hud.messages.size() == 2 and hud.messages[0].fade < 0.0, "the line stays for 5 s")
	hud.advance_messages(0.2)
	hud.advance_messages(0.3)
	check(hud.messages.size() == 2 and hud.messages[0].fade > 0.0, "then it fades")
	hud.advance_messages(0.25)
	check(hud.message_texts() == ["second"] and hud.messages[0].age == 0.0, "after 0.5 s it is gone, and the next line only now starts ageing")
	hud.messages.clear()

## #159: a specialization shrine's (or beacon's) message opens once the
## hero's change effect (Bereserk.pfx, 30 ticks of the command queue) has
## played, not over it; the map is held meanwhile.
func _change_effect_message(view: ELAdventureView, profile: ELProfile) -> void:
	var state := view.state
	var hero := state.object(view._hero_id())
	check(not hero.is_empty() and ELFog.shown(state, 1, hero), "the player has a hero in sight")
	if hero.is_empty(): return
	var text := profile.text("BldngMsg1Specialization").replace("%s", "X")
	# As ELSecondBuildings.use: the effect event, then the message.
	var start := Time.get_ticks_msec()
	state.event.emit({"kind": "hero_change_effect", "id": hero.uid})
	view.director.presentation.emit({"kind": "building_message", "hero": hero.uid, "building": -1, "title": "", "text": text, "resources": [], "skill": "", "key": "BldngMsg1Specialization"})
	await frames(2)
	var name := "hero_change:%d" % int(hero.uid)
	check(view.effects.effects.has(name) and view.building_message == null and view.paused, "the shrine's message waits while the change effect plays, the map held")
	while view.building_message == null and Time.get_ticks_msec() - start < 15000: await process_frame
	var waited := (Time.get_ticks_msec() - start) / 1000.0
	check(view.building_message != null and waited > 1.7 and not view.effects.effects.has(name), "then it opens, the effect over (%.2f s)" % waited)
	if view.building_message != null: view._close_building_message()
	await frames(2)
	check(not view.paused, "closing it frees the map")
	# After a battle: the specialization's box waits for the commands queued
	# before it (here a script wait of 0.6 s).
	# The chapter's opening scene is let run out first.
	var opening := Time.get_ticks_msec()
	while Time.get_ticks_msec() - opening < 30000:
		if view.director._map_idle(): break
		if not view.director.dialogue.is_empty(): view.director.acknowledge("OK")
		await frames(2)
	check(view.director._map_idle(), "the chapter's opening commands have run")
	view.director.action_wait = 0.6
	state.learn_specialization(int(hero.uid), _unowned_spec(state, profile, hero))
	await frames(2)
	check(view.building_message == null and view.director.action_wait > 0.0, "a specialization learned after a battle waits for the map's commands")
	start = Time.get_ticks_msec()
	while view.building_message == null and Time.get_ticks_msec() - start < 3000: await process_frame
	var d := view.director
	check(view.building_message != null and view.director.action_wait <= 0.0, "then its box opens (%.2f s; idle %s: wait %.2f, commands %d, dialogue %s, outcome %s, exclusive %s, encounter %s, travel %s, paused %s)" % [(Time.get_ticks_msec() - start) / 1000.0, d._map_idle(), d.action_wait, state.commands.size(), not d.dialogue.is_empty(), state.outcome, state.exclusive, d.encounter != null, d.travel, view.paused])
	if view.building_message != null: view._close_building_message()
	await frames(2)

static func _unowned_spec(state: ELAdventureSession, profile: ELProfile, hero: Dictionary) -> String:
	for code: String in profile.table("HeroesSpecs"):
		if ELSpecs.valid(profile, code) and code != "NONE" and not state.specializations(hero).has(code): return code
	return ""

func _mine_depletion(profile: ELProfile, settings: ELSettings) -> void:
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, {"file_name": "e2mission11"}, settings, 1)
	check(built, "the opening Vitals map builds: " + view.error)
	if built: _settle_last_mine_payment(view)
	view.queue_free()
	await frames(2)

func _pickup_transition(view: ELAdventureView) -> void:
	var state := view.state
	var world := view.world
	var picked_ids: Array[int] = []
	for item: Dictionary in state.objects.values():
		if item.group != "resource_cuts" or not item.alive or not ELFog.shown(state, 1, item): continue
		var id: int = item.uid
		# Collect while the pile is still fading in, as when approaching at speed.
		world._fog_level[id] = 0.0
		world._fading[id] = 1.0
		var picked := state.collect_resources(view._hero_id(), id)
		check(picked and not item.alive and world._retiring_pickups.has(id), "the resource is collected immediately and its visible pile animates out")
		picked_ids.append(id)
		world._process(ELAdventureScene.PICKUP_FADE / 2.0)
		if picked_ids.size() == 2: break
	check(picked_ids.size() == 2, "the chapter has two visible resource piles to collect")
	var grid := view.director.grid
	var after := grid.blockers.duplicate()
	grid.rebuild(state.objects)
	check(grid.blockers == after, "collecting the piles updates their blockers exactly as a full grid rebuild")
	world._process(ELAdventureScene.PICKUP_FADE)
	world._process(1.0 / 60.0)
	for id: int in picked_ids:
		check(not world._retiring_pickups.has(id) and not world._fading.has(id) and not world._fog_presence.get(id, true),
			"#218: a collected pile stays hidden when a second pickup overlaps its animation")

func _fog_region(world: ELAdventureScene) -> void:
	var tiles := world.fog_tiles()
	var old := world.fog_corners(tiles)
	var cell := Vector2i(5, 5)
	var at := cell.y * world.map.width + cell.x
	tiles[at] = 255 - tiles[at]
	var updated := world._update_fog_corners(tiles, old, Rect2i(cell, Vector2i(2, 2)))
	check(updated == world.fog_corners(tiles), "updating only the affected fog corners matches a full rebuild")
	var state := world.fog_session
	check(state != null, "the campaign scene keeps the session for its fog updates")
	if state == null: return
	ELFog.reveal_for_console(state, 1, false)
	world.sync_fog()
	check(world._fog_tiles == world.fog_tiles() and world.fog_to == world.fog_corners(), "turning fog back on refreshes all affected tiles")
	var previous := world.fog_to.duplicate()
	world.fog_since = INF
	ELFog.reveal_for_console(state, 1, true)
	world.sync_fog()
	check(world._fog_tiles == world.fog_tiles() and world.fog_to == world.fog_corners() and world.fog_from == previous, "a fog update keeps the previous corner opacity for the fade")

func _runestones(profile: ELProfile, settings: ELSettings) -> void:
	var row := {"file_name": "e2mission13"}
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	view.set_process(false)
	check(built, "#210: the Vitals map with both runestone models builds")
	if not built:
		view.queue_free()
		return
	var state := view.state
	ELFog.reveal_for_console(state, 1, true)
	var tested := {}
	var open_poses := {}
	for gate: Dictionary in state.objects.values():
		if not ELSecondGates.is_gate(gate) or not gate.visible: continue
		var family := ELSecondGates.base(gate)
		if tested.has(family): continue
		tested[family] = true
		var id := int(gate.uid)
		var model: ELModel = view.world.object_models.get(id)
		var part_name := "gate01" if family == "Runestone1" else "gate03_displacement4"
		var part: MeshInstance3D = model.parts.get(part_name) if model != null else null
		check(part != null and model.clip == "uclose" and not model.playing, "#210: %s starts in its closed pose" % family)
		if part == null: continue
		var closed_pose := part.transform
		var origin := Vector2i(gate.x, gate.y)
		var grid := view.director.grid
		var covered: Array = grid.footprints[id].cells
		state._native([float(id)], "ExOpenGate")
		check(model.visible and model.clip == "uinstant" and model.playing, "#210: %s stays visible and plays its opening animation" % family)
		model._process(1.0)
		check(model.visible and not model.playing and not part.transform.is_equal_approx(closed_pose), "#210: %s holds the open pose" % family)
		var open_cells := covered.filter(func(offset: Vector2i) -> bool: return grid.passability(origin + offset, false, false) >= 0)
		check(not open_cells.is_empty(), "#210: %s opens a passage" % family)
		open_poses[id] = {"part": part_name, "pose": part.transform}
		state._native([float(id)], "ExCloseGate")
		check(model.visible and model.clip == "uclose" and model.playing, "#210: %s plays its closing animation" % family)
		view.world.set_animate_objects(false)
		check(not model.playing and part.transform.is_equal_approx(closed_pose) and open_cells.all(
			func(offset: Vector2i) -> bool: return grid.passability(origin + offset, false, false) < 0),
			"#210: %s shuts the passage and settles when animation is disabled" % family)
		state._native([float(id)], "ExOpenGate")
		check(not model.playing and part.transform.is_equal_approx(open_poses[id].pose), "#210: %s opens immediately with object animation off" % family)
		view.world.set_animate_objects(true)
		state._native([float(id)], "ExCloseGate")
		gate.visible = false
		state.event.emit({"kind": "object_changed", "id": id})
		state._native([float(id)], "ExOpenGate")
		check(not model.visible, "#210: %s respects scripted hiding" % family)
		gate.visible = true
		state.event.emit({"kind": "object_changed", "id": id})
		check(model.visible and not model.playing and part.transform.is_equal_approx(open_poses[id].pose),
			"#210: %s returns in the latest pose when shown again" % family)
	check(open_poses.size() == 2, "#210: both original gate models are covered")
	var codec := ELAdventureSave.new()
	var saved := codec.encode(view.director, view.camera_state())
	var restored := codec.decode(JSON.parse_string(JSON.stringify(saved)), {"el2": profile})
	_talk_facing(view)
	view.queue_free()
	await frames(2)
	check(not restored.is_empty(), "#210: the checkpoint with opened runestones can be loaded (%s)" % codec.error)
	if restored.is_empty(): return
	var loaded := ELAdventureView.new()
	root.add_child(loaded)
	built = loaded.build(profile, row, settings, 1, restored)
	check(built, "#210: the checkpoint's map builds")
	if built:
		ELFog.reveal_for_console(loaded.state, 1, true)
		for id: int in open_poses:
			var item := loaded.state.object(id)
			loaded.world.fog_object(item)
			var model: ELModel = loaded.world.object_models.get(id)
			var expected: Dictionary = open_poses[id]
			check(item.get("opened", false) and model != null and model.visible and not model.playing
				and model.parts[expected.part].transform.is_equal_approx(expected.pose), "#210: the loaded %s starts in the open pose" % item.name)
	loaded.queue_free()
	await frames(2)

## Green chapter 3's real pre-use hooks queue these lines and still allow
## ordinary use. The participants should already face each other.
func _talk_facing(view: ELAdventureView) -> void:
	var state := view.state
	state.step()
	var heroes: ELLuaVM.Table = state.vm.globals.get("Heroes")
	check(heroes != null, "#224: the Vitals chapter has its conversation script")
	if heroes == null: return
	heroes.values.VHead.values.State = "DonePrisoner1"
	heroes.values.VGuardEast.values.State = "OutOfGate"
	heroes.values.Prisoner02.values.State = "InCity"
	var actor := state.object(state.main_hero)
	for speaker: Array in [["VGuardEast", "MV_M13_S17_P01_FV_EASTGUARD_13"], ["Prisoner02", "MV_M13_S37_P01_FV_PRISONER2_13"]]:
		state.commands.clear()
		var target := state.object(heroes.values[speaker[0]].values.Id)
		actor.x = target.x
		actor.y = target.y - 1
		view.world.update_object(actor)
		view.world.orient_actor(int(actor.uid), Vector2.RIGHT)
		view.world.orient_actor(int(target.uid), Vector2.RIGHT)
		view.director.use_object(int(actor.uid), int(target.uid))
		var speaks := state.commands.any(func(command: Dictionary) -> bool:
			return command.kind == "Text" and command.arguments[1] == speaker[1])
		var facing := is_equal_approx(cos(view.world.object_yaw(actor)), -1.0) and is_equal_approx(cos(view.world.object_yaw(target)), 1.0)
		check(speaks and facing, "#224: the player and %s face each other for the reported dialogue" % str(speaker[0]))

func _settle_last_mine_payment(view: ELAdventureView) -> void:
	var state := view.state
	var player := state.current_player
	var mine := {}
	for site: Dictionary in state.objects.values():
		if site.get("group") == "mines" and site.name == "Mine.Root.Green":
			mine = site
			break
	check(not mine.is_empty(), "the opening Vitals map has a Mandrake Garden")
	if mine.is_empty(): return
	mine.owner = player
	mine.mine_remaining = 1
	var herbs: int = state.players[player].resources.Herbs
	ELResourceSites.settle_income(state, true)
	check(state.players[player].resources.Herbs == herbs + 5, "the final Mandrake Garden payment credits five herbs")
	check(mine.mine_remaining == 0 and ELResourceSites.income(state, player).Herbs == 0, "the garden stops producing after its final payment")
	check(view.building_message == null and view.building_messages.is_empty(), "mine depletion opens and queues no popup")

func _camera(view: ELAdventureView) -> void:
	var state := view.state
	view.following = -1
	view.state.camera_locked = false
	var start := view.target
	var goal := ELAdventureScene.world_position(float(state.map.width) * 0.5, float(state.map.height) * 0.5)
	if goal.distance_to(start) < 10.0: goal = ELAdventureScene.world_position(2.0, 2.0)
	check(is_equal_approx(view.scroll_rate, 0.125), "the look-at point covers 0.25 x AutoScrollAcceleration 0.5 per tick (%.3f)" % view.scroll_rate)
	view._present({"kind": "CameraToPos", "arguments": [(goal.x / ELAdventureTerrain.CELL) - 0.5, (-goal.z / ELAdventureTerrain.CELL) - 0.5]})
	check(view.target == start and view.camera_goal() == goal, "a scripted camera move does not jump")
	view._glide(0.064)
	var expected := start + (goal - start) * view.scroll_rate
	check(view.target.distance_to(expected) < 0.001, "one 64 ms tick covers an eighth of the way")
	for i in 400: view._glide(0.064)
	check(view.target == goal and not view.scroll_gliding, "the flight ends on its point")
	var other := ELAdventureScene.world_position(4.0, 4.0)
	view._state_event({"kind": "ExCameraScrollToPos", "arguments": [4.0, 4.0], "instant": true})
	check(view.target == other and not view.scroll_gliding, "an Instant scroll jumps")
	view._state_event({"kind": "ExCameraScrollToPos", "arguments": [6.0, 6.0]})
	check(view.target == other and view.scroll_gliding, "a plain script scroll flies")
	view.touch_pan(Vector2(100, 100), Vector2(120, 100))
	check(not view.scroll_gliding, "the player's own pan stops a flight")
	var size := root.get_visible_rect().size
	view._pointer_on_map = true
	view._pointer = Vector2(size.x - 1.0, 0.0)
	view.open_options()
	check(view.second_hud.menu.visible and view.edge_direction() == Vector2i.ZERO, "the open Escape menu blocks mouse panning")
	view.close_options()
	for i in 60:
		if not view._cursor_modal() and not state.exclusive and state.commands.is_empty(): break
		if not view.director.dialogue.is_empty(): view.director.acknowledge()
		await process_frame
	check(view.edge_direction() == Vector2i(1, -1), "the top-right edge pans diagonally")
	view._pointer = Vector2(size.x * 0.5, size.y - 1.0)
	check(view.edge_direction() == Vector2i(0, 1), "the bottom edge pans")
	view._pointer = Vector2(0.0, size.y * 0.5)
	view._scroll_to(goal)
	start = view.target
	var yaw := view.yaw
	view._update_edge(ELAdventureView.EDGE_TICK)
	var left := Vector3.LEFT.rotated(Vector3.UP, yaw)
	check((view.target - start).dot(left) > 0.0 and view.yaw == yaw and not view.scroll_gliding,
		"the left edge moves across the map without turning and interrupts a flight")
	view._pointer_on_map = false
	check(view.edge_direction() == Vector2i.ZERO, "a pointer over the interface does not pan")
	view._pointer_on_map = true
	state.camera_locked = true
	check(view.edge_direction() == Vector2i.ZERO, "a locked camera ignores mouse edges")
	state.camera_locked = false
	view._pointer_on_map = false

func _new_map_reports(view: ELAdventureView) -> void:
	var state := view.state
	var director := view.director
	var grid := director.grid
	var hero := state.object(state.main_hero)
	var id := int(hero.uid)
	var from := Vector2i(hero.x, hero.y)
	var to := from
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var point := from + offset
		if grid.passability(point, bool(hero.get("ship", false))) >= 0:
			to = point
			break
	check(from != to, "#173: the hero has a passable neighboring tile")
	if from != to:
		ELFog.reveal_for_console(state, 1, false)
		var bit := ELFog.bit(1)
		var order_cell := to.y * state.map.width + to.x
		var old_known := state.explored[order_cell]
		state.explored[order_cell] &= ~bit
		check(not ELFog.targetable(state, 1, to) and director.request_move(id, to), "#173: a ground order is accepted even where the cursor still shows cancel")
		if not director.movement.is_empty(): director._complete_movement(false)
		state.explored[order_cell] = old_known

		var seen: PackedByteArray = state.fog.visible.duplicate()
		var old_seen: PackedByteArray = seen.duplicate()
		seen[from.y * state.map.width + from.x] &= ~bit
		seen[order_cell] |= bit
		state.fog.visible = seen
		state.fog.revision = ELFog.revision(state) + 1
		view.world.move_actor(id, Vector2(from).lerp(Vector2(to), 0.75), true, 12.0, true)
		view.world.sync_fog()
		check(view.world.actors[id].visible, "#178: a fog refresh keeps a figure visible on the tile it is crossing")
		state.fog.visible = old_seen
		ELFog.reveal_for_console(state, 1, true)
		view.world.move_actor(id, Vector2(from), false)

	var blocked := {}
	var destination := Vector2i.ZERO
	for uid: int in grid.occupied:
		if not state.hostile(hero, state.object(uid)): continue
		destination = grid.occupied[uid]
		blocked = director._ground_route_to_enemy(hero, from, destination)
		if not blocked.is_empty() and blocked.path.size() > 1: break
	var ordered: bool = not blocked.is_empty() and blocked.path.size() > 1 and director.request_move(id, destination)
	check(ordered and director.movement.get("use") == blocked.target, "#173: an enemy blocking a ground route becomes the attack target")
	if not director.movement.is_empty(): director._complete_movement(false)

	var focus := view.target + Vector3(4, 0, 4)
	view._scroll_to(focus)
	view._present({"kind": "dialogue", "dialogue": {"actor": id, "text": "Test line", "text_id": ""}})
	check(not view.second_dialogue.visible and not view._pending_speech.is_empty(), "#175: the next line waits while the camera is in flight")
	var stones := state.objects.values().filter(ELSecondGates.is_warding)
	if not stones.is_empty():
		var stone: Dictionary = stones[0]
		var picked := ELSecondGates.use(director, hero, stone)
		var opened: bool = view.building_message != null and view.building_message.data.building == stone.uid
		_dialogue_key(KEY_ENTER)
		_dialogue_key(KEY_ENTER, false)
		check(picked and opened and view.building_message == null and not view._pending_speech.is_empty(),
			"#214: Enter dismisses the warding-stone notice while the next script line is still waiting")
		if view.building_message != null: view._close_building_message()
	else: check(false, "#214: the chapter has its warding stone")
	view._glide(10.0)
	await frames(2)
	check(view.second_dialogue.visible and view._pending_speech.is_empty(), "#175: the dialogue opens when the camera reaches the speaker")
	view._present({"kind": "dialogue_closed"})

	hero.skill_points = 1
	ELHeroSkills.prepare(state.map.profile, hero)
	view._open_skills(id)
	if view.skills is ELSecondLevelUpView:
		var dialog := view.skills as ELSecondLevelUpView
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		view._unhandled_input(escape)
		check(view.skills == dialog and dialog.offers.item_count > 0, "#180: Escape keeps the pending level-up dialog open")
		var font_cell := int(view.second_hud._controls.LUHeader1.get("FontSize", 18))
		check(dialog.heading.get_theme_font_size("font_size") == ELFrontMenu.cell_em(font_cell), "#180: the level-up title uses the original font cell height")
		view._close_skills()
	else:
		check(false, "#180: a level-up dialog opens")

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if kept.has(file):
			if FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
