## Modified for the EL1 Naval Worlds release, 18 November 2026.
class_name ELAdventureView
extends Node3D
var strategic_session: ELStrategicSession
## Called with 0..1 as `build` goes on (the chapter loading screen's bar).
var loading_progress := Callable()
signal leave_requested
signal campaigns_requested
signal encounter_requested(hero: int, opponent: int)
## F9 / F8: resume the quick save (ELSaveSlots.quick_path).
signal resume_requested
## A save chosen on the in-game load list (ELSaveSlots row).
signal slot_requested(row: Dictionary)
signal chapter_requested(scenario: Dictionary)
## Second game: the next chapter's global-map screen (ELSecondCampaign progress).
signal campaign_map_requested(progress: Dictionary)
var state: ELAdventureSession
var director: ELAdventureDirector
var world: ELAdventureScene
## Ground rings under the hovered object and the selected hero.
var rings: ELSelectionRing
var camera: Camera3D
var ui: Control
var remake_overlay: Control
var _remake_menu: PanelContainer
var _remake_picker: Control
var title: Label
var hero_info: Label
var notice: Label
var _observer_battle_note := ""
var dialogue_panel: Control
## Catches clicks while a script message box sits over a modal window.
var dialogue_blocker: Control
## Second game: ExBlinkElement frames over the InventoryScreen.
var inventory_blinks: Control
const BlinkFrames := preload("res://src/render/second_blink_frames.gd")
var dialogue_name: Label
var dialogue_text: RichTextLabel
var dialogue_portrait: TextureRect
var accept: BaseButton
var decline: BaseButton
## Second game: the script boxes on the original TextDialog / MessageBox art.
var second_dialogue: ELSecondDialogueBox
var _pending_speech: Dictionary = {}
const MISSION_FADE_SECONDS := 2.0
## These shared maps and the interlude choose their opening scene in the
## first step hook. Their story commands still run on the mission clock.
const SCRIPTED_OPENING_SCENES := {"maps/e2mission32": "e2mission24_32", "maps/e2mission34": "e2mission34_44_54", "maps/e2mission50": "e2mission50"}
var _mission_fade: ColorRect
var _held_dialogue_keys := {}
var route: MeshInstance3D
var _route_owner := -1
var _route_fog_revision := -1
var target := Vector3.ZERO
## First game: the original's perspective map camera, set up when a map
## loads: the angle fixed at 45 degrees, the distance 25-50 starting at 50
## (position = target - forward x distance), drawn with a pi/4 fov across a
## 4:3 view (the map's projection overrides the camera object's own pi/3.5).
## The standing rotation (map's west at the top) matches the original's
## mission openings.
const FIRST_FOV_4_3 := PI / 4.0
const FIRST_YAW := PI * 0.5
const FIRST_ZOOM := 50.0
const FIRST_PITCH := PI / 4.0
const FIRST_ZOOM_LIMITS := Vector2(25, 50)
var yaw := FIRST_YAW
var pitch := FIRST_PITCH
var zoom := FIRST_ZOOM
## Camera angle range (radians above the horizon); the first game's is fixed.
var pitch_limits := Vector2(FIRST_PITCH, FIRST_PITCH)
## Second game: the original's perspective map camera (camera object
## defaults: fov pi/3.5 across a 4:3 view; position = target - forward x zoom),
## at a standing distance and angle measured from original footage. While a
## speaker box is up the original moves in to a closer, lower view and eases
## back after it (an opening line framed at 15 / 0.70 rad, about 20 / 0.80
## on the way back, standing at 22 / 0.92).
const SECOND_FOV_4_3 := PI / 3.5
const SECOND_ZOOM := 22.0
const SECOND_YAW := 0.0
const SECOND_PITCH := 0.92
const SECOND_TEXT_ZOOM := 15.0
const SECOND_TEXT_PITCH := 0.70
## The standing distance and angle kept while a speaker box holds the close
## view ({} otherwise), and the distance/angle the camera eases to (x < 0: none).
var text_view: Dictionary = {}
var view_goal := Vector2(-1, -1)
var _script_lens := false
## Scripted camera turns ease as in the original: each 64 ms tick moves the
## view a sixth of the remaining angle, the shorter way round, and it settles
## once that step is under 0.001 rad. INF when no turn is pending.
const TURN_RATE := 1.0 / 6.0
const TURN_TICK := 0.064
var yaw_goal := INF
var zoom_limits := Vector2(16, 100)
var following := -1
var script_camera_attached := true
## The player moved the view away from the hero; it stays there until the
## player centres the hero or orders a move.
var view_moved := false
var dragging := false
var error := ""
var paused := false
var console_open := false
var settings: ELSettings
var _art: ELAdventureArt
var audio: ELAdventureAudio
## Second game: script particle effects (weather, scenery and cutscene effects).
var effects: ELAdventureEffects
## Building sounds and terrain ambience; first game also blazons and building
## effects, second game also map figures' footsteps.
var presentation: ELFirstMapPresentation
## ELSpellbookView, or (first game) ELFirstBookView.
var spellbook: Control
## The open spellbook when it is the plain or second-game screen. Keeping this
## typed member also keeps the script load order that frees cleanly at exit.
var plain_spellbook: ELSpellbookView
var skills: ELHeroSkillsView
var global_spells: ELGlobalSpellsView
var diplomacy: ELDiplomacyView
var global_spell_waiting := false
var skill_button: Button
var day_button: BaseButton
var _turn_clock: ELFirstClock
var hero_selector: OptionButton
var cancel_button: Button
## Remake-only helper parts over the original HUD (the readout box, shortcut
## buttons the original panels already cover, the controls hint); shown only
## with the remake setting "helper_overlay".
var helper_parts: Array[Control] = []
var helper_hint := ""
## The last remake readout of a map event or refused order (see _remark).
var remark := ""
var selected_hero := -1
var mana_readout: Dictionary = {}
var shop: ELSpellShopView
## Component portal book selection: one slot sideways, a row of five up or down.
const RUNE_SHOP_KEYS := {KEY_LEFT: -1, KEY_UP: -5, KEY_RIGHT: 1, KEY_DOWN: 5}
var rune_shop: ELRuneShopView
var first_shop: ELFirstSpellShopView
var hero_screen: ELHeroScreenView
## First game: the player's heroes that gained a level, in order; the
## HeroScreen opens for each once the map is idle (_first_level_up).
var first_level_ups: Array[int] = []
var building_screen: ELBuildingScreenView
var building_message: ELBuildingMessageView
var building_messages: Array[Dictionary] = []
const REWARD_DIALOG_GAP := 0.3
const REWARD_EFFECT := "battle_reward"
const LOOT_EFFECT := "Loot.pfx"
const LEVEL_EFFECT := "Bereserk.pfx"
## The original queues the loot cue and the hero change cue for 30 map ticks
## (ExSendLootMessage at 0x69bdc9, CHero::PlayChangeEffect at 0x66a661).
const REWARD_CUE_TICKS := 30
var _finishing_battle := false
var _encounter_loot: Array[Dictionary] = []
var _reward_cues: Array[Dictionary] = []
var _reward_wait := 0.0
var _battle_level_hero := -1
## Second game: hero uid -> the msec time its change effect (shrine, beacon)
## ends; its building message waits for it (#159).
var _change_effects: Dictionary = {}
## Building messages held back while a change effect plays.
var _message_holds := 0
var deferred_encounter: Dictionary = {}
## First game: a shop or resource-site screen, or the outcome window, waiting
## for the map notice in front of it (the original opens them after its
## MessageBox).
var deferred_shop: Dictionary = {}
var result_waiting := false
var leave_button: BaseButton
## Mission-end picture (WinLose) and its layer; `result_shown` stays true once
## the outcome was presented. Second game: the chapter-end kind ("finished",
## "campaign", "next" or "lost") and the progress it leads to.
var win_lose: ELWinLoseScreen
var win_lose_layer: CanvasLayer
var result_shown := false
var result_kind := ""
var result_progress: Dictionary = {}
## Ending movie layer (campaign finals) and whether it was already shown.
var movie_layer: CanvasLayer
var movie: ELMoviePlayer
var _ending_shown := false
var hud: ELAdventureHud
## Second-game strategic panels (AdvPanelLB/RB) and Esc menu.
var second_hud: ELSecondAdventureHud
var notebook: ELSecondNotebookView
## Second-game map hover tooltip (ELSecondMapTooltips): timing, the last
## cursor position and whether it reached the map rather than a panel.
var map_tip := ELSecondMapTooltips.Timing.new()
var _tip_point := Vector2(-1, -1)
var _tip_on_map := false
var _tip_moved := false
var _tip_clock := 0.0
var _tip_camera := ""
var _tip_camera_clock := 0.0
var _tip_content: Dictionary = {}
## Second game: a right press shows the tooltip; travelling past the drag
## threshold turns it into a camera drag.
var _right_down := false
var _right_origin := Vector2.ZERO
## Original cursors (ELCursors): last pointer position, whether it reached
## the map, re-pick throttle and how long a script has held the map.
var _pointer := Vector2(-1, -1)
var _pointer_on_map := false
## Edge camera: the pointer pans at a screen edge. Ctrl turns and tilts.
## The velocities ease towards their targets on the original 64 ms camera
## step and stop at once when the pointer leaves the edge.
const EDGE_TICK := 0.064
const EDGE_PAN := 2.0 / 0.064
const EDGE_TURN := 0.2 / 0.064
const EDGE_TILT := 0.1 / 0.064
var edge_enabled := true
var edge_cursor := ""
var _edge_pan := Vector2.ZERO
var _edge_turn := 0.0
var _edge_tilt := 0.0
var _mouse_inside := true
var _cursor_clock := 0.0
var _cursor_moved := false
var _script_busy := -1.0
## The cursor this view asked for last, and its inputs (for checks).
var cursor_name := ""
var cursor_context: Dictionary = {}
## Front-end screens hosted over the map (ELFrontMenu.open_hosted): the second
## game's Encyclopaedia from the Esc menu, the first game's Hall of Fame after a
## won single mission or campaign final.
var extras: ELFrontMenu
var extras_layer: CanvasLayer
var _save_preview_pending := false
var _after_extras := Callable()
## Hall of Fame table a won mission wrote ("scenario", "campaign" or "").
var hall_record := ""
## First game: the contextual tutorial panel (ELFirstTutorialPanel).
var tutorial_panel: ELFirstTutorialPanel
## Queued first-game battles open the original pre-battle panel first.
var precombat_preview := true
var pending_encounter: Array = []
## Second game: the pre-battle panel and the LoseBattle screen.
var second_precombat: ELSecondPrecombatView
var lose_battle: ELSecondLoseBattleView

func _enter_tree() -> void:
	add_to_group("touch_camera")

func build(profile: ELProfile, scenario: Dictionary, preferences: ELSettings, difficulty := 0, restored: Dictionary = {}) -> bool:
	settings = preferences
	var solo_first := profile.id == "el1" and strategic_session == null
	# Building or restoring a map shows the wait cursor until the map picks again.
	wait_cursor(profile)
	var map := ELAdventureMap.new()
	var opening_events: Array[Dictionary] = []
	if restored.is_empty():
		var map_seed := 212
		if scenario.has("random_map"):
			if profile.id != "el1" or strategic_session != null or not scenario.random_map is Dictionary:
				return _fail("Random maps require a local Etherlords I game.")
			var generator := ELFirstRandomMap.new()
			map = generator.generate(profile, scenario.random_map)
			if map == null: return _fail(generator.error)
			map_seed = ELFirstRandomMap.seed_for_config(generator.config)
		else:
			if not map.load_map(profile, str(scenario.file_name)): return _fail(map.error)
		_loading(0.15)
		state = ELAdventureSession.new()
		# The scene initialization hooks can emit a direct box or wait before
		# the director exists. Deliver them once the opening can be presented.
		var capture := func(data: Dictionary) -> void:
			if data.kind in ["message_box", "script_wait"]: opening_events.append(data)
		if profile.id == "el2": state.event.connect(capture)
		if not state.start(map, difficulty, map_seed, str(scenario.get("script", "")), int(str(scenario.get("player", "1"))), scenario.has("number"), solo_first): return _fail(state.error)
		if profile.id == "el2": state.event.disconnect(capture)
		_loading(0.25)
		state.tutorial = bool(scenario.get("tutorial", false))
		director = ELAdventureDirector.new()
		if not director.build(state): return _fail(director.error)
		_loading(0.4)
	else:
		state = restored.state
		state.random_skill_offers = solo_first
		director = restored.director
		map = state.map
	# The game's computer players' strength: kept by a save, brought by the
	# chapter row, or the difficulty's (ELAIChoice).
	ELAIChoice.adopt(state, scenario, settings)
	if scenario.has("header"): map.title = profile.text(str(scenario.header))
	elif profile.id == "el2":
		var metadata := ELCampaign.find_scenario(profile, map.id, state.script_name)
		if metadata.has("header"): map.title = profile.text(str(metadata.header))
	state.event.connect(_state_event)
	director.presentation.connect(_present)
	if profile.id == "el2":
		director.encounter_finishing.connect(_on_encounter_finishing)
		director.encounter_finished.connect(_on_encounter_finished)
	# ExIsDesktopModalChild: any window or message box over the map.
	state.desktop_modal = func() -> bool: return paused or extras_open() or not director.dialogue.is_empty() or director._shopping()
	_art = ELAdventureArt.new(map)
	world = ELAdventureScene.new()
	world.naval_source = naval_source
	add_child(world)
	if not world.build(map, state): return _fail("; ".join(world.errors))
	_loading(0.75)
	rings = ELSelectionRing.new()
	world.add_child(rings)
	if not rings.setup(profile): rings.textures.clear()
	camera = Camera3D.new()
	add_child(camera)
	camera.far = 800.0
	# Both games: perspective, the original's horizontal fov at 4:3 held as
	# the vertical one so a wider window shows more at the sides.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = rad_to_deg(2.0 * atan(tan((SECOND_FOV_4_3 if profile.id == "el2" else FIRST_FOV_4_3) * 0.5) * 0.75))
	camera.near = 1.0
	zoom_limits = FIRST_ZOOM_LIMITS
	if profile.id == "el2":
		pitch_limits = Vector2(0.5, 1.35)
		zoom = SECOND_ZOOM
		yaw = SECOND_YAW
		pitch = SECOND_PITCH
		zoom_limits = Vector2(8, 100)
	camera.current = true
	var hero := state.object(_hero_id())
	target = ELAdventureScene.world_position(hero.get("x", map.width * 0.5), hero.get("y", map.height * 0.5))
	following = _hero_id()
	_update_camera()
	_build_ui()
	if strategic_session != null: strategic_session.management_changed.connect(_refresh_hero_info)
	_refresh_hero_info()
	audio = ELAdventureAudio.new()
	add_child(audio)
	audio.build(profile, preferences)
	apply_settings()
	_loading(0.85)
	effects = ELAdventureEffects.new()
	world.add_child(effects)
	if profile.id == "el2": effects.rain_changed.connect(world.terrain.set_water_rain)
	effects.build(profile, preferences, state)
	if profile.id == "el2":
		scroll_rate = SCROLL_RATE * scroll_acceleration(profile)
		audio.listener = target
		audio.restore(state)
		effects.prepare(BATTLE_DOME_EFFECT)
		effects.prepare(BATTLE_DEFEAT_EFFECT)
		effects.prepare(LOOT_EFFECT)
		effects.prepare(LEVEL_EFFECT)
		ELAudio.sound(profile, BATTLE_DOME_SOUND)
		# Building sounds, terrain ambience and footsteps (no blazons).
		_build_presentation()
	elif profile.id == "el1":
		audio.start_first(state)
		if dome_source != null:
			effects.prepare(BATTLE_DOME_EFFECT, dome_source)
			ELAudio.sound(dome_source, BATTLE_DOME_SOUND)
		_build_presentation()
	route = MeshInstance3D.new()
	add_child(route)
	if not restored.is_empty():
		var saved: Dictionary = restored.camera
		# A view saved for the other projection (an earlier orthographic map)
		# keeps the standing view instead.
		if bool(saved.get("perspective", false)) == (camera.projection == Camera3D.PROJECTION_PERSPECTIVE):
			var turned := float(saved.get("yaw", yaw))
			if is_finite(turned): yaw = fposmod(turned, TAU)
			pitch = clampf(float(saved.get("pitch", pitch)), pitch_limits.x, pitch_limits.y)
			zoom = clampf(float(saved.get("zoom", zoom)), zoom_limits.x, zoom_limits.y)
		following = int(saved.get("following", following))
		script_camera_attached = bool(saved.get("script_camera_attached", true))
		selected_hero = int(saved.get("selected_hero", state.main_hero))
		_refresh_roster()
		var point: Variant = saved.get("target")
		if point is Array and point.size() == 3: target = Vector3(float(point[0]), float(point[1]), float(point[2]))
		if not director.dialogue.is_empty():
			_present({"kind": "dialogue", "dialogue": director.dialogue})
			if audio.voice.stream != null: audio.voice.seek(float(saved.get("voice_position", 0)))
		if not director.movement.is_empty():
			_draw_route(director.movement.path, director.movement.id)
			var at: int = director.movement.index
			director.fast_mode = bool(settings.values.get("adventure_fast", false)) if settings != null else false
			var id: int = director.movement.id
			var point_on_path := Vector2(director.movement.path[at]).lerp(Vector2(director.movement.path[at + 1]), director.movement.progress)
			world.move_actor(id, point_on_path, true, director.movement_speed(state.object(id)), director.fast_mode)
		elif profile.id == "el1": _draw_route(ELStrategy.order_path(director, state.object(_hero_id())))
		_stop_following_hidden_hero()
		if not director.travel.is_empty(): _travel_phase(false)
		_update_camera()
	else:
		if profile.id == "el1" and scenario.has("campaign") and scenario.has("number"):
			var progress := {"campaign": str(scenario.campaign), "number": int(str(scenario.number)), "subnumber": int(str(scenario.get("subnumber", "1"))), "branch": int(str(scenario.get("branch", 0))), "score": int(str(scenario.get("score", 0)))}
			for key: String in ELFirstScenario.PROFILE_KEYS:
				if scenario.has(key): progress[key] = scenario[key]
			ELFirstScenario.track(state, progress)
		# The chosen name and blazon become the human player's (campaign and Single).
		if profile.id == "el1" and scenario.get("player_name") is String:
			ELPlayerProfile.apply(state, str(scenario.player_name), int(scenario.get("logo", -1)), int(scenario.get("colour", -1)))
			# The blazons were placed with the map's own picture.
			if presentation != null: presentation.sync()
		ELFirstScenario.opening(director)
		if profile.id == "el2":
			_fade_in_mission()
			if scenario.get(ELSecondCampaign.KEY) is Dictionary:
				var problem := ELSecondCampaign.start_chapter(state, scenario[ELSecondCampaign.KEY])
				if not problem.is_empty(): return _fail(problem)
			for event: Dictionary in opening_events: state.event.emit(event)
			var script := ELArchive.key(state.script_name)
			if SCRIPTED_OPENING_SCENES.get(script) == ELArchive.key(map.id):
				if not director.prepare_opening_scene(): return _fail(director.error)
				target = camera_goal()
				scroll_gliding = false
				if following >= 0 and world.actors.has(following): target = world.actors[following].position
				if yaw_goal != INF:
					yaw = yaw_goal
					yaw_goal = INF
				if view_goal.x > 0 and _script_lens:
					zoom = view_goal.x
					pitch = view_goal.y
					view_goal = Vector2(-1, -1)
			world.enable_fog(state)
			_refresh_hero_info()
			_update_camera()
		# First game: every mission start is saved as T_AUTOSAVE_START_MISSION.
		if profile.id == "el1" and not state.tutorial:
			wait_cursor(profile)
			var failed := ELSaveSlots.write_auto("T_AUTOSAVE_START_MISSION", director, camera_state())
			if not failed.is_empty(): push_warning(failed)
			else: _attach_start_preview.call_deferred()
	if profile.id == "el1": _build_first_tutorial()
	for pickup: Dictionary in restored.get("pickup_notices", []): _present(pickup)
	for message: Dictionary in restored.get("site_notices", []):
		match message.kind:
			"resources_collected": _first_pickup_box(message)
			"site_captured": _first_capture_box(message)
			"building_message": _present(message)
	if strategic_session != null:
		strategic_session.site_notice_open = func() -> bool:
			return (building_message != null and building_message.data.get("site_notice", false)) \
				or building_messages.any(func(message: Dictionary) -> bool: return message.get("site_notice", false))
	if ELGlobalSpells.applies(state):
		global_spell_waiting = ELGlobalSpells.data(state, state.current_player).get("production", {}).get("state", 0) == 2
	if not state.outcome.is_empty(): _show_result()
	_loading(1.0)
	return true

func _exit_tree() -> void:
	if state != null: state.close()

var _hud_clock := 0.0
var _hud_key := Vector2i(-2, -2)

func _process(delta: float) -> void:
	if strategic_session != null and notice != null:
		var battle_note := strategic_session.observer_battle_note()
		if battle_note != _observer_battle_note:
			_observer_battle_note = battle_note
			notice.text = remark if battle_note.is_empty() else battle_note
	if _turn_clock != null:
		_turn_clock.show_seconds(strategic_session.clock_remaining())
	if hud != null and paused and hud.tooltip.visible: hud.tooltip.hide()
	_tick_cursor(delta)
	if second_hud != null: _tick_map_tooltip(delta)
	if director == null or not visible or not error.is_empty() or _mission_fade != null or paused or console_open or extras_open():
		# Second game: the hero readouts follow the state under a message box or
		# window too (a building use pays its points before its message opens).
		if second_hud != null and director != null: _refresh_hero_info()
		return
	if _reward_transition():
		if _step_reward_transition(delta): return
		_show_waiting_map_dialogs()
	elif result_waiting: _show_waiting_map_dialogs()
	# A message waiting for the map's commands (#159) opens once they are done.
	elif not building_messages.is_empty(): _show_building_message()
	if paused: return
	if global_spell_waiting and _can_act():
		_offer_global_spell()
		if global_spells != null: return
	if strategic_session != null:
		var visit := strategic_session.local_shop_visit()
		if not visit.is_empty():
			if not _open_strategy_shop(visit[0], visit[1], true, strategic_session.remote_shop_open(state.current_player)):
				strategic_session.manage_hero(["visit_close"] + visit, func(_reason: String): pass)
			return
	# Notebook entries keep the point the camera looks at.
	state.view_point = Vector2(target.x, -target.z) / ELAdventureTerrain.CELL
	# Options "Accelerated mode": map movement at four times its normal rate.
	director.fast_mode = bool(settings.values.get("adventure_fast", false)) if settings != null else false
	# Remake option: first-game heroes move at once, several times a day (a
	# network game keeps simultaneous orders).
	director.free_movement = bool(settings.values.get("free_movement", true)) if settings != null and strategic_session == null else false
	# The game's "world_ai": 0 Original, 1 Smarter, 2 Living world (ELAIChoice;
	# a network game uses the Options choice).
	ELAIChoice.apply_world(director, settings, strategic_session != null)
	# Remake switch (settings only, off by default): estimated off-screen battles.
	director.battle_estimate = bool(settings.values.get("battle_estimate", false)) if settings != null else false
	if hud != null: hud.free_steps = ELStrategy.free_mode(director)
	if strategic_session == null or strategic_session.link.is_host: director.advance(delta)
	# Free movement: End Day pressed while a hero was still walking ends the
	# day once the move is over (a battle on the way cancels it).
	if _end_day_queued:
		if director.encounter != null or not director.dialogue.is_empty() or not state.outcome.is_empty(): _end_day_queued = false
		elif director.can_move() and director.movement.is_empty():
			_end_day_queued = false
			_end_day()
	_travel_pose()
	if not director.error.is_empty():
		error = director.error
		notice.text = error
	_update_edge(delta)
	if yaw_goal != INF:
		var remaining := wrapf(yaw_goal - yaw, -PI, PI)
		if absf(remaining) * TURN_RATE < 0.001:
			yaw = yaw_goal
			yaw_goal = INF
		else: yaw += remaining * (1.0 - pow(1.0 - TURN_RATE, delta / TURN_TICK))
	if view_goal.x > 0:
		var settled: bool
		if _script_lens:
			zoom = _script_lens_step(zoom, view_goal.x, 0.25, delta)
			pitch = _script_lens_step(pitch, view_goal.y, 1.0 / 3.0, delta)
			settled = zoom == view_goal.x and pitch == view_goal.y
		else:
			var ease := minf(1.0, delta)
			zoom = lerpf(zoom, view_goal.x, ease)
			pitch = lerpf(pitch, view_goal.y, ease)
			settled = absf(zoom - view_goal.x) < 0.02 and absf(pitch - view_goal.y) < 0.002
		if settled:
			zoom = view_goal.x
			pitch = view_goal.y
			view_goal = Vector2(-1, -1)
	_sync_route_fog()
	_stop_following_hidden_hero()
	if following >= 0 and world.actors.has(following):
		scroll_gliding = false
		target = target.lerp(world.actors[following].position, minf(1, delta * 6.0))
	elif not state.camera_locked:
		var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		if direction != Vector2.ZERO: scroll_gliding = false
		var flat := Vector3(direction.x, 0, direction.y).rotated(Vector3.UP, yaw)
		target += flat * delta * zoom * 0.8 * (float(settings.values.get("keyboard_scroll", 1.0)) if settings != null else 1.0)
	if scroll_gliding: _glide(delta)
	if view_moved and following < 0: _clamp_target()
	_update_camera()
	if not _pending_speech.is_empty() and (int(_pending_speech.get("actor", -1)) < 0 or _speaker_in_place()):
		var speech := _pending_speech
		_pending_speech = {}
		_show_second_dialogue(speech)
	_update_rings(delta)
	if audio != null:
		audio.listener = target
		audio.listener_forward = -camera.global_basis.z
	if presentation != null:
		presentation.listener = target
		presentation.listener_forward = -camera.global_basis.z
	# First game: the HUD rescans every map object, so the frame loop
	# refreshes it ten times a second, or at once when the selection or turn
	# changes; map events refresh it directly.
	_hud_clock += delta
	var hud_key := Vector2i(_hero_id(), int(_can_act()))
	if hud == null or _hud_clock >= 0.1 or hud_key != _hud_key:
		_hud_clock = 0.0
		_hud_key = hud_key
		_refresh_hero_info()
	_auto_level_up()
	_first_level_up()

## The original wait cursor while a map is built, loaded or saved (never while
## a battle opponent thinks); the next pick replaces it.
func wait_cursor(profile: ELProfile) -> void:
	ELCursorDriver.request(profile, "wait")
	_cursor_moved = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT: _mouse_inside = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER: _mouse_inside = true

## Edge direction under the pointer: first game all eight directions within
## 1-2 px of the edges, second game left/right within 4 px; (0,0) for none.
func edge_direction() -> Vector2i:
	# A finger resting near an edge must not scroll the map.
	if ELTouchInput.enabled: return Vector2i.ZERO
	if not edge_enabled or not _mouse_inside or _pointer.x < 0 or state == null or state.camera_locked or dragging: return Vector2i.ZERO
	if not visible or paused or _cursor_modal(): return Vector2i.ZERO
	var size := get_viewport().get_visible_rect().size
	if state.map.profile.id == "el2":
		if not _pointer_on_map or Input.get_mouse_button_mask() != 0 or state.exclusive or not state.commands.is_empty(): return Vector2i.ZERO
		var x := -1 if _pointer.x < 4 else (1 if _pointer.x > size.x - 4 else 0)
		var y := -1 if _pointer.y < 4 else (1 if _pointer.y > size.y - 4 else 0)
		return Vector2i(x, y)
	var x := -1 if _pointer.x <= 0 else (1 if _pointer.x >= size.x - 2 else 0)
	var y := -1 if _pointer.y <= 0 else (1 if _pointer.y >= size.y - 2 else 0)
	return Vector2i(x, y)

const EDGE_CURSORS := {Vector2i(0, -1): "scroll_u", Vector2i(1, -1): "scroll_ur", Vector2i(1, 0): "scroll_r", Vector2i(1, 1): "scroll_dr",
	Vector2i(0, 1): "scroll_d", Vector2i(-1, 1): "scroll_dl", Vector2i(-1, 0): "scroll_l", Vector2i(-1, -1): "scroll_ul"}

func _update_edge(delta: float) -> void:
	var direction := edge_direction()
	var named: String = EDGE_CURSORS.get(direction, "")
	if named != edge_cursor:
		edge_cursor = named
		update_cursor()
	var keys := keyboard_motion()
	var zoom_direction := float(keys.get("zoom", 0.0))
	if zoom_direction != 0.0:
		view_goal = Vector2(-1, -1)
		zoom = clampf(zoom - zoom_direction * 2.0 * delta / EDGE_TICK, zoom_limits.x, zoom_limits.y)
	if direction == Vector2i.ZERO and keys.is_empty():
		_edge_pan = Vector2.ZERO
		_edge_turn = 0.0
		_edge_tilt = 0.0
		return
	var values: Dictionary = settings.values if settings != null else {}
	var rotation_speed := float(values.get("mouse_rotation", 1.0))
	var pan_target := Vector2.ZERO
	var turn_target := 0.0
	var tilt_target := 0.0
	if not keys.is_empty():
		pan_target = keys.get("pan", Vector2.ZERO)
		turn_target = float(keys.get("turn", 0.0))
		tilt_target = float(keys.get("tilt", 0.0))
	elif Input.is_key_pressed(KEY_CTRL):
		if state.map.profile.id == "el2" and bool(values.get("invert_rotation", false)): rotation_speed = -rotation_speed
		turn_target = direction.x * EDGE_TURN * rotation_speed
		tilt_target = direction.y * EDGE_TILT
	else:
		pan_target = Vector2(direction) * EDGE_PAN * float(values.get("mouse_scroll", 1.0))
	var steps := delta / EDGE_TICK
	_edge_pan += (pan_target - _edge_pan) * (1.0 - pow(1.0 - 0.2667, steps))
	_edge_turn += (turn_target - _edge_turn) * (1.0 - pow(1.0 - 1.0 / 6.0, steps))
	_edge_tilt += (tilt_target - _edge_tilt) * (1.0 - pow(1.0 - 1.0 / 6.0, steps))
	if _edge_pan != Vector2.ZERO:
		following = -1
		scroll_gliding = false
		view_moved = true
		target += Vector3(_edge_pan.x, 0, _edge_pan.y).rotated(Vector3.UP, yaw) * delta
	# The same turn as dragging towards that edge.
	yaw -= _edge_turn * delta
	if turn_target != 0.0: yaw_goal = INF
	pitch = clampf(pitch + _edge_tilt * delta, pitch_limits.x, pitch_limits.y)

## Held camera keys on the camera tick (original key-down/key-up handlers).
## First game: arrows pan 2*KeyboardScroll units a tick; with Ctrl, Left/Right
## turn 0.2*KeyboardRotation rad a tick (Ctrl+Left the way Ctrl at the right
## edge turns) and Up/Down tilt as Ctrl at the top/bottom edge. Page Up/Down
## zoom. In the second game Up/Down also zoom, while Left/Right turn the map.
func keyboard_motion() -> Dictionary:
	if state == null or state.map == null or director == null or state.camera_locked or not visible or paused or _cursor_modal(): return {}
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus is LineEdit or focus is TextEdit: return {}
	var x := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	var y := float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	var second := state.map.profile.id == "el2"
	if second and state.exclusive: return {}
	var zoom_in := Input.is_physical_key_pressed(KEY_PAGEUP) or (second and Input.is_physical_key_pressed(KEY_UP))
	var zoom_out := Input.is_physical_key_pressed(KEY_PAGEDOWN) or (second and Input.is_physical_key_pressed(KEY_DOWN))
	var zoom_direction := float(zoom_in) - float(zoom_out)
	if x == 0.0 and (second or y == 0.0) and zoom_direction == 0.0: return {}
	var values: Dictionary = settings.values if settings != null else {}
	var rotation_speed := float(values.get("keyboard_rotation", 1.0))
	if second:
		return {"turn": x * EDGE_TURN * rotation_speed * (-1.0 if bool(values.get("invert_rotation", false)) else 1.0), "zoom": zoom_direction}
	if Input.is_key_pressed(KEY_CTRL): return {"turn": -x * EDGE_TURN * rotation_speed, "tilt": y * EDGE_TILT, "zoom": zoom_direction}
	return {"pan": Vector2(x, y) * EDGE_PAN * float(values.get("keyboard_scroll", 1.0)), "zoom": zoom_direction}

## Hover ring on the picked object (not the player's own heroes) and the
## selected hero's ring, in the local player's colour.
func _update_rings(delta: float) -> void:
	if rings == null: return
	if _cursor_modal() or not visible:
		rings.hide_rings()
		return
	rings.colour = ELSelectionRing.colour_index(str(state.players.get(state.current_player, {}).get("color", "")))
	var hover := int(cursor_context.get("picked", -1))
	var item := state.object(hover)
	if item.is_empty() or (item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player): hover = -1
	var selected := _hero_id()
	var hero := state.object(selected)
	if hero.is_empty() or not hero.get("alive", false) or not hero.get("visible", true) or hero.get("fortified", false) or not hero.get("placed", true): selected = -1
	if int(director.travel.get("hero", -1)) == selected: selected = -1
	var hover_place := _ring_place(hover)
	var selected_place := _ring_place(selected)
	rings.show_rings(delta, hover, hover_place[0], hover_place[1], selected, selected_place[0], selected_place[1], selected >= 0 and hero.get("danger_pulse", false))

## Ground point and footprint (cells) of an object for its ring.
func _ring_place(uid: int) -> Array:
	var item := state.object(uid)
	if item.is_empty(): return [Vector3.ZERO, Vector2i.ONE]
	if world.actors.has(uid):
		var at: Vector3 = world.actors[uid].position
		# Moving figures: the first game's view objects all return radius 1.0
		# the second game's heroes keep the default 1.0, while its
		# roaming creatures (CMOBBuilding, built through the static map-object
		# path) get 0.7 × their record size like buildings.
		if state.map.profile.id == "el1" or item.get("type") == "hero": return [Vector3(at.x, 0, at.z), ELSelectionRing.NO_SIZE]
		var figure_row: Dictionary = _art.resolve(item).get("row", {})
		return [Vector3(at.x, 0, at.z), ELAdventureGrid.footprint(figure_row, int(item.get("rotation", 0))).size if not figure_row.is_empty() else Vector2i.ONE]
	var row: Dictionary = _art.resolve(item).get("row", {})
	var centre := ELAdventureGrid.center(item, row)
	return [Vector3(centre.x * ELAdventureTerrain.CELL, 0, -centre.y * ELAdventureTerrain.CELL), ELAdventureGrid.footprint(row, int(item.get("rotation", 0))).size]

func _hero_id() -> int:
	var actor := state.object(selected_hero)
	if state.map.profile.id == "el1" and not actor.is_empty() and actor.alive and actor.owner == state.current_player: return selected_hero
	if state.map.profile.id == "el1" and not state.object(state.main_hero).get("alive", false):
		for candidate: Dictionary in state.objects.values():
			if candidate.type == "hero" and candidate.alive and candidate.owner == state.current_player: return candidate.uid
		return -1
	return state.main_hero

func _refresh_roster() -> void:
	if hud != null: hud.refresh(_hero_id(), mana_readout, _can_act())
	if hero_selector == null: return
	hero_selector.clear()
	for actor: Dictionary in state.objects.values():
		if actor.type != "hero" or not actor.alive or not actor.visible or actor.owner != state.current_player: continue
		hero_selector.add_item(actor.get("title", actor.name))
		var index := hero_selector.item_count - 1
		hero_selector.set_item_metadata(index, actor.uid)
		if actor.uid == _hero_id(): hero_selector.select(index)

func _select_hero(id: int) -> void:
	var actor := state.object(id)
	if paused or not director.can_move() or actor.is_empty() or actor.type != "hero" or not actor.alive or actor.owner != state.current_player: return
	selected_hero = id
	following = id
	view_moved = false
	_refresh_roster()
	var path := ELStrategy.order_path(director, actor)
	_draw_route(path)
	var preview := director.interception.preview(state, actor, path)
	if not preview.is_empty() and not director.interception.enemies(state, actor, preview[-1]).is_empty():
		director.notice = ELInterception.ROUTE_NOTICE
	else: director.notice = ""
	_remark(director.notice)
	_refresh_hero_info()

func focus_recruit(id: int) -> void:
	var actor := state.object(id)
	if actor.get("owner") != state.current_player or not actor.get("alive", false) or not actor.get("visible", false): return
	selected_hero = id
	following = id
	view_moved = false
	_draw_route([])
	_refresh_roster()
	_refresh_hero_info()

## The cast plays its sound on each client. Fog gates the map particles and
## camera, and selection stays with the recruit's own commander.
func present_summon(id: int, code: String) -> void:
	var hero := state.object(id)
	if not hero.get("alive", false) or not hero.get("visible", false): return
	# Spell colour drives the cue even when a mod grants it to another race.
	var colour: String = {"C": "Red", "K": "Blue", "S": "Black", "V": "Green"}[code[1]]
	audio.effect_sound("Magic/Global%sSummon.wav" % colour)
	var owned: bool = hero.owner == state.current_player
	if owned and (selected_hero != id or following != id): focus_recruit(id)
	if not ELFog.shown(state, state.current_player, hero): return
	if owned:
		target = ELAdventureScene.world_position(hero.x, hero.y)
	else:
		_focus_object(id)
	var at := camera_goal()
	var actor: Node3D = world.actors.get(id)
	if is_instance_valid(actor): at = world.to_local(actor.global_position)
	effects.start("summon:%d" % id, {"file": "GlobalSummon%s.pfx" % colour, "x": at.x, "y": -at.z, "z": at.y,
		"tile": Vector2i(hero.x, hero.y), "loops": 0}, 0.0)

## A same-day guest refresh replaces the scene. Keep only the active summon
## sprites and their clocks, independently of the original cast's other cues.
func summon_playback() -> Dictionary:
	var playback := {}
	for name: String in effects.effects:
		if not name.begins_with("summon:"): continue
		var effect: Dictionary = effects.effects[name]
		playback[name] = {"entry": effect.entry, "elapsed": effect.elapsed, "drawn": effect.frame >= 0}
	return playback

func resume_summon_playback(playback: Dictionary) -> void:
	for name: String in playback:
		var cue: Dictionary = playback[name]
		if ELFog.visible(state, state.current_player, cue.entry.tile):
			effects.start(name, cue.entry, cue.elapsed, cue.drawn)

func _can_act() -> bool:
	return _mission_fade == null and not _reward_transition() and not paused and director.can_move() and director.movement.is_empty() and (strategic_session == null or strategic_session.can_plan())

func _refresh_hero_info() -> void:
	var hero := state.object(_hero_id())
	if hud != null:
		_refresh_first_hud(hero)
		return
	if second_hud != null:
		_refresh_second_hud(hero)
		return
	var level := int(hero.get("level", 1))
	var experience := str(ELHeroProgression.effective(hero)) + (" / %d XP" % ELHeroProgression.threshold(state.map.profile, level + 1) if level < ELHeroProgression.MAX_LEVEL else " XP · Maximum level")
	var day_label := "Day %d" % (state.day + 1 if state.map.profile.id == "el2" else state.day)
	if state.map.profile.id == "el2": day_label += "  ·  %d / %d travel" % [hero.get("ap", 0), hero.get("travel_capacity", 8)]
	if state.map.profile.id == "el1": day_label += "  ·  %d / %d movement" % [hero.get("ap", 0), hero.get("strategy_capacity", 0)]
	hero_info.text = "%s  ·  Level %d  ·  %s\n%d health  ·  %d spells  ·  %s\n%s" % [hero.get("title", ""), level, experience, hero.get("health", 0), hero.get("cards", []).size(), day_label, ELResources.describe(state.map.profile.id, state.players.get(state.current_player, {}).get("resources", {}))]
	if skill_button != null: skill_button.text = "Skills%s  [K]" % (" (%d)" % hero.skill_points if int(hero.get("skill_points", 0)) > 0 else "")
	if state.map.profile.id == "el1":
		if mana_readout.is_empty(): mana_readout = ELStrategy.mana_budget(state, state.current_player)
		hero_info.text += "\nEther: %d income · %d/%d upkeep · %d available" % [mana_readout.income, mana_readout.spent, mana_readout.required, mana_readout.available]
		var castle: Dictionary = state.scenario.get("castles", {}).get(state.current_player, {})
		if not castle.is_empty(): hero_info.text += "  ·  Castle %d / %d energy" % [castle.health, castle.max]
	if day_button != null: day_button.disabled = paused or not director.can_move() or not director.movement.is_empty() or (strategic_session != null and not strategic_session.can_plan())
	if hero_selector != null: hero_selector.disabled = paused or not director.can_move()
	if cancel_button != null: cancel_button.disabled = paused or not director.can_move() or hero.get("strategy_order", {}).is_empty()
	if leave_button != null:
		leave_button.visible = hero.get("fortified", false) or int(hero.get("camp", -1)) >= 0
		leave_button.disabled = paused or not director.can_move() or not director.movement.is_empty()
	if hero.get("fortified", false): hero_info.text += "\nGarrisoning %s" % ELForts.title(state.map.profile, state.object(hero.fort))

## First-game HUD: resources, day and roster live in the original panel; the
## compact strip keeps remake-only details (movement, upkeep, experience).
func _refresh_first_hud(hero: Dictionary) -> void:
	var level := int(hero.get("level", 1))
	var experience := str(ELHeroProgression.effective(hero)) + (" / %d XP" % ELHeroProgression.threshold(state.map.profile, level + 1) if level < ELHeroProgression.MAX_LEVEL else " XP · Maximum level")
	if mana_readout.is_empty(): mana_readout = ELStrategy.mana_budget(state, state.current_player)
	hero_info.text = "%s  ·  Level %d  ·  %s\n%d / %d movement  ·  %d health  ·  %d spells\nEther upkeep %d / %d" % [hero.get("title", ""), level, experience, hero.get("ap", 0), hero.get("strategy_capacity", 0), hero.get("health", 0), hero.get("cards", []).size(), mana_readout.spent, mana_readout.required]
	var castle: Dictionary = state.scenario.get("castles", {}).get(state.current_player, {})
	if not castle.is_empty(): hero_info.text += "  ·  Castle %d / %d energy" % [castle.health, castle.max]
	if hero.get("fortified", false): hero_info.text += "\nGarrisoning %s" % ELForts.title(state.map.profile, state.object(hero.fort))
	if int(hero.get("camp", -1)) >= 0: hero_info.text += "\nTraining in the %s  ·  +%d XP each day" % [ELAdditionalBuildings.title(state.map.profile, state.object(hero.camp)).to_lower(), ELAdditionalBuildings.CAMP_EXPERIENCE]
	if skill_button != null: skill_button.text = "Skills%s  [K]" % (" (%d)" % hero.skill_points if int(hero.get("skill_points", 0)) > 0 else "")
	var acting := _can_act()
	if cancel_button != null: cancel_button.disabled = not acting or hero.get("strategy_order", {}).is_empty()
	hud.refresh(_hero_id(), mana_readout, acting)
	if strategic_session != null:
		hud.buttons.Save.disabled = not strategic_session.link.local_authority or not strategic_session.can_save() or paused
		hud.buttons.Load.disabled = not strategic_session.link.local_authority or not acting
		leave_button.disabled = leave_button.disabled or not hero.get("fortified", false)

func _next_hero() -> void:
	if hud.roster.is_empty(): return
	var at := hud.roster.find(_hero_id())
	_select_hero(hud.roster[(at + 1) % hud.roster.size()])

## Starts the battle shown in the pre-battle panel.
func begin_encounter() -> void:
	if pending_encounter.is_empty(): return
	var pair := pending_encounter
	pending_encounter = []
	if hud != null: hud.hide_precombat()
	_close_second_precombat()
	encounter_requested.emit(pair[0], pair[1])

## PreCombatCancel (second game) or the remake's X for a neutral creature
## (first game) declines the battle shown in the panel.
func decline_encounter() -> void:
	if pending_encounter.is_empty(): return
	if director.encounter == null or not director.encounter.declinable(): return
	pending_encounter = []
	if hud != null: hud.hide_precombat()
	_close_second_precombat()
	if not director.decline_encounter(): notice.text = director.error
	_refresh_hero_info()

func _close_second_precombat() -> void:
	_finish_battle_dome()
	if second_precombat == null or not second_precombat.visible: return
	second_precombat.close()
	if second_hud != null: second_hud.show()

func _open_second_precombat(first: int, second: int) -> void:
	# The local side is on the left, its opponent on the right.
	var local := first if int(state.object(first).get("owner", -1)) == 1 else second
	var other := second if local == first else first
	var faces: Array = []
	for id: int in [local, other]:
		var actor := state.object(id)
		# A tunnel guard waits off the map, hidden; its portrait still shows.
		var shown := actor.duplicate()
		shown.visible = true
		faces.append(int(_art.resolve(shown).get("row", {}).get("Face", -1)) if not actor.is_empty() else -1)
	pending_encounter = [first, second]
	# The camera centres between the two sides while the panel is up. A tunnel
	# guard waits off the map, so it counts as standing at its tunnel mouth.
	var spots: Array[Vector3] = []
	for id: int in [first, second]:
		var place := state.object(id)
		if place.has("tunnel_source") and not state.object(place.tunnel_source).is_empty(): place = state.object(place.tunnel_source)
		if place.is_empty() or int(place.get("x", -1)) < 0 or int(place.get("y", -1)) < 0: continue
		if int(place.x) >= state.map.width or int(place.y) >= state.map.height: continue
		spots.append(ELAdventureScene.world_position(place.x, place.y))
	if not spots.is_empty():
		following = -1
		scroll_gliding = false
		target = spots[0] if spots.size() == 1 else (spots[0] + spots[1]) * 0.5
	second_hud.hide()
	second_precombat.open(state, local, other, faces)
	_start_battle_dome(first, second)

## Second game: a battle with a local side raises the ether dome as its
## pre-battle panel opens (the original attack order, for the player's attacks,
## the computer's and interceptions alike; Remote Use has none). The dome
## (sphere.pfx, cycling) stands at the midpoint of the two figures, both of
## which play their Summon clip, and Adventure/CombatDome.wav loops there on
## the effects volume, full within 0 and silent from 32 units. Both end when
## the panel closes: the battle opens or is declined. Presentation only.
## The first game has no dome of its own: with the second game installed and
## the remake's "first_battle_dome" setting on, its pre-battle panel raises
## the second game's dome the same way (`dome_source`, set by the host).
const BATTLE_DOME := "battle_dome"
const BATTLE_DOME_EFFECT := "sphere.pfx"
const BATTLE_DOME_SOUND := "Adventure/CombatDome.wav"
const BATTLE_DOME_FAR := 32.0
const BATTLE_DOME_SUMMON_CODE := 0x018c0000

## First game: the second game's files the borrowed battle dome comes from,
## or null for none.
var dome_source: ELProfile
## Independent of the battle-dome preference: installed EL2 ship appearance.
var naval_source: ELProfile

func _start_battle_dome(first: int, second: int) -> void:
	_finish_battle_dome()
	if effects == null or world == null: return
	var source: ELProfile = dome_source if state.map.profile.id == "el1" else null
	if state.map.profile.id == "el1" and source == null: return
	var points: Array[Vector3] = []
	for id: int in [first, second]:
		var actor: Node3D = world.actors.get(id)
		if is_instance_valid(actor) and actor.is_visible_in_tree(): points.append(world.to_local(actor.global_position))
	var at := target
	if points.size() == 1: at = points[0]
	elif points.size() == 2: at = (points[0] + points[1]) * 0.5
	var entry := {"file": BATTLE_DOME_EFFECT, "x": at.x, "y": -at.z, "z": at.y, "story": true}
	effects.start(BATTLE_DOME, entry, 0.0, false, source)
	if audio != null: audio.start_sound(BATTLE_DOME, {"file": BATTLE_DOME_SOUND, "x": at.x, "y": -at.z, "z": at.y,
		"near": 0.0, "far": BATTLE_DOME_FAR, "loop": true, "effects": true}, source)
	# The original asks each figure for its Summon clip by clip code.
	for id: int in [first, second]:
		var model: ELModel = world.actors.get(id)
		if not is_instance_valid(model): continue
		var clip := auto_fight_clip(model)
		if not clip.is_empty(): world.play_actor_clip(id, clip)

## The clip a figure fights with under the battle dome: its Summon clip (by
## the original's clip code, else "usummon"), else its instant cast clip,
## else its attack clip, the order a hero's gestures fall back in during a
## battle (ELDuel view _cast_clip). Many hero figures have no Summon clip
## (the Vital guards of chapter 11): without the fallback they stood still
## through their fight (#163). "" when the figure has none of them.
static func auto_fight_clip(model: ELModel) -> String:
	var clip := model.clip_for_code(BATTLE_DOME_SUMMON_CODE)
	if not clip.is_empty(): return clip
	for name: String in ["usummon", "uinstant", "uattack"]:
		if model.has_clip(name): return name
	return ""

## Second game: a battle with no local side (ELAdventureDirector.auto_fight).
## The two figures turn to each other, the dome rises between them and both
## play Summon; the director waits for the longer clip. The original shows
## no duel and no death clip: the loser takes BattleDefeat.pfx and
## Adventure/BattleDefeat.wav (one shot, silent from 32 units) and its corpse
## replaces it 7 ticks later.
const BATTLE_DEFEAT_EFFECT := "BattleDefeat.pfx"
const BATTLE_DEFEAT_SOUND := "Adventure/BattleDefeat.wav"

func _show_auto_fight(first: int, second: int) -> void:
	if world == null: return
	# A fight the local player cannot see is not shown (it still takes its time).
	if not _fight_seen(first, second): return
	var ends: Array[Node3D] = []
	for id: int in [first, second]:
		var actor: Node3D = world.actors.get(id)
		if is_instance_valid(actor): ends.append(actor)
	if ends.size() == 2:
		var a := Vector2(ends[0].global_position.x, -ends[0].global_position.z)
		var b := Vector2(ends[1].global_position.x, -ends[1].global_position.z)
		world.orient_actor(first, b - a)
		world.orient_actor(second, a - b)
	_start_battle_dome(first, second)
	# The fight lasts as long as the longer Summon clip of a shown figure.
	var longest := 0.0
	for id: int in [first, second]:
		var model: ELModel = world.actors.get(id)
		if not is_instance_valid(model) or not model.is_visible_in_tree(): continue
		var clip := auto_fight_clip(model)
		if not clip.is_empty(): longest = maxf(longest, model.clip_seconds(clip))
	if longest > 0.0 and not director.auto_fight.is_empty(): director.auto_fight.remaining = longest

func _fight_seen(first: int, second: int) -> bool:
	for id: int in [first, second]:
		var item := state.object(id)
		if not item.is_empty() and ELFog.object_state(state, 1, item) == ELFog.VISIBLE: return true
	return false

func _auto_fight_defeat(loser: int) -> void:
	if not effects.effects.has(BATTLE_DOME): return
	var actor: Node3D = world.actors.get(loser) if world != null else null
	if not is_instance_valid(actor) or not actor.is_visible_in_tree(): return
	var at := world.to_local(actor.global_position)
	if effects != null: effects.start("battle_defeat:%d" % loser, {"file": BATTLE_DEFEAT_EFFECT, "x": at.x, "y": -at.z, "z": at.y, "loops": 0, "story": true}, 0.0)
	if audio != null: audio.start_sound("battle_defeat:%d" % loser, {"file": BATTLE_DEFEAT_SOUND, "x": at.x, "y": -at.z, "z": at.y,
		"near": 0.0, "far": BATTLE_DOME_FAR, "loop": false, "effects": true})

func _finish_battle_dome() -> void:
	if effects != null: effects.finish(BATTLE_DOME)
	if audio != null: audio.cancel_sound(BATTLE_DOME)

func _open_lose_battle() -> void:
	if second_hud == null or lose_battle != null: return
	lose_battle = ELSecondLoseBattleView.new()
	ui.add_child(lose_battle)
	lose_battle.build(second_hud)
	lose_battle.closed.connect(func(): lose_battle = null)

var _end_day_queued := false

func _end_day() -> void:
	if paused or _save_preview_pending: return
	if strategic_session == null and ELStrategy.free_mode(director) and director.strategy.get("free", "") == "act":
		_end_day_queued = true
		_remark("The day ends when this move is over.")
		return
	if strategic_session != null:
		strategic_session.end_turn()
		_refresh_hero_info()
		return
	# First game: the Autosave option saves before the turn ends.
	if state.map.profile.id == "el1" and (settings == null or bool(settings.values.get("autosave", true))) and director.can_move() and director.movement.is_empty():
		wait_cursor(state.map.profile)
		# The map is held still for the capture's frame.
		var preview: Image = null
		if not state.tutorial: preview = await _capture_save_preview()
		var failed := ELSaveSlots.write_auto("T_AUTOSAVE_EOT", director, camera_state(), preview)
		if not failed.is_empty() and not state.tutorial: notice.text = failed
	if not director.end_day(): _remark(director.notice)
	_refresh_hero_info()

func _unhandled_input(event: InputEvent) -> void:
	if console_open or not _pending_speech.is_empty(): return
	var key := event as InputEventKey
	var continue_dialogue := key != null and key.pressed and (
		not key.echo or (key.keycode == KEY_SPACE and director != null and not bool(director.dialogue.get("question", false))))
	var action := ""
	if key != null and key.pressed and not key.echo and state != null and state.map != null:
		action = ELSettings.hotkey_action(settings, state.map.profile.id, "Map", key)
	# The tutorial panel takes every key and click while it is open.
	if tutorial_panel != null and tutorial_panel.handle_input(event): return
	# A script message box over a window is modal: keys answer it.
	if dialogue_blocker != null and dialogue_blocker.visible and director != null and not director.dialogue.is_empty():
		if second_dialogue != null:
			if continue_dialogue:
				var answer := second_dialogue.key_answer(event.keycode)
				if not answer.is_empty(): director.acknowledge(answer)
				if not answer.is_empty() or event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]: get_viewport().set_input_as_handled()
			return
		if continue_dialogue and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			director.acknowledge("CANCEL" if event.keycode == KEY_ESCAPE and bool(director.dialogue.get("question", false)) else "OK")
			get_viewport().set_input_as_handled()
		return
	if hero_screen != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			hero_screen.cancel()
			get_viewport().set_input_as_handled()
		# Enter presses the check button (an open question answers it itself).
		elif _enter(event) and hero_screen.confirm == null:
			_press_check(hero_screen.buttons, ["HeroScrOk", "ExchOK"])
			get_viewport().set_input_as_handled()
		return
	if building_screen != null:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
			_close_building_screen()
			get_viewport().set_input_as_handled()
		return
	if building_message != null:
		if building_message.message_box == null and key != null and key.pressed and key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_close_building_message()
			get_viewport().set_input_as_handled()
		return
	if global_spells != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			global_spells.cancel()
			get_viewport().set_input_as_handled()
		elif _enter(event):
			if global_spells.prompt != null and global_spells.prompt.visible: _press_check(global_spells.prompt_buttons, ["SelectOK"])
			else: _press_check(global_spells.buttons, ["GSOK"])
			get_viewport().set_input_as_handled()
		return
	if diplomacy != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			diplomacy.cancel()
			get_viewport().set_input_as_handled()
		elif _enter(event) and diplomacy.confirm == null and not (diplomacy.trade != null and diplomacy.trade.visible) and not (diplomacy.dialog != null and diplomacy.dialog.visible):
			_press_check(diplomacy.buttons, ["D_OK"])
			get_viewport().set_input_as_handled()
		return
	if first_shop != null or rune_shop != null or shop != null:
		if key != null and key.pressed: _shop_hotkey(key)
		return
	if skills != null:
		if key != null and key.pressed and not key.echo and action.begins_with("skill_offer_") and skills is ELSecondLevelUpView:
			(skills as ELSecondLevelUpView).select_offer(int(action.get_slice("_", 2)) - 1)
			get_viewport().set_input_as_handled()
		elif key != null and key.pressed and (key.keycode == KEY_ESCAPE or action == "skills"):
			if not (skills is ELSecondLevelUpView and skills.offers.item_count > 0): _close_skills()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and skills is ELSecondLevelUpView:
			(skills as ELSecondLevelUpView).press_ok()
			get_viewport().set_input_as_handled()
		return
	if spellbook != null:
		if key != null and key.pressed and (key.keycode == KEY_ESCAPE or action == "inventory"):
			_close_spellbook()
			get_viewport().set_input_as_handled()
		return
	if second_hud != null and second_hud.menu.visible:
		if action == "map_remake_menu" and not extras_open() and not ELWikiScreen.is_open():
			_open_remake_from_pause()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_options()
			get_viewport().set_input_as_handled()
		return
	if notebook != null:
		if key != null and key.pressed and (key.keycode == KEY_ESCAPE or action == "notebook"):
			notebook.close()
			get_viewport().set_input_as_handled()
		return
	if lose_battle != null:
		if event is InputEventKey and event.pressed and not event.echo: lose_battle.dismiss()
		if event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if remake_overlay != null and remake_overlay.is_visible_in_tree():
		if key != null and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or action == "map_remake_menu"):
			close_remake_menu()
			get_viewport().set_input_as_handled()
		return
	if director == null or paused: return
	if second_precombat != null and second_precombat.visible:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			begin_encounter()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			decline_encounter()
			get_viewport().set_input_as_handled()
		return
	if hud != null and hud.precombat.visible:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			begin_encounter()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and hud.cancel_button != null and hud.cancel_button.visible:
			decline_encounter()
			get_viewport().set_input_as_handled()
		return
	# Second game: the open script box takes its keys first (Enter/Esc/Space).
	if second_dialogue != null and continue_dialogue and not director.dialogue.is_empty():
		var answer := second_dialogue.key_answer(event.keycode)
		if not answer.is_empty(): director.acknowledge(answer)
		if not answer.is_empty() or event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed:
		if not action.is_empty():
			get_viewport().set_input_as_handled()
			match action:
				"end_day":
					if not _cursor_modal(): _end_day()
				"map_remake_menu": _open_remake_menu()
				"inventory": _open_spellbook(-1)
				"skills": _open_skills()
				"global_spells":
					if ELGlobalSpells.applies(state): open_global_spells()
				"notebook":
					if director.dialogue.is_empty() and second_hud != null: open_notebook()
				"cancel_order": _cancel_map_order()
				"map_save": quick_save()
				"map_load": ask_quick_load()
				"center_hero": _centre_hero()
		elif event.keycode == KEY_ESCAPE and second_hud != null and director.dialogue.is_empty():
			open_options()
			get_viewport().set_input_as_handled()
		# First game: Esc opens the Options screen (the tutorial calls it the
		# <Esc> menu), like the Options column's wrench.
		elif event.keycode == KEY_ESCAPE and hud != null and director.dialogue.is_empty() and not event.echo:
			open_original_options()
			get_viewport().set_input_as_handled()
		elif continue_dialogue and event.keycode == KEY_SPACE and not director.dialogue.is_empty():
			director.acknowledge()
			get_viewport().set_input_as_handled()
		# First game: H opens the tutorial; Home centres the hero.
		elif event.keycode == KEY_H and tutorial_panel != null: tutorial_panel.open_history()
		elif event.keycode == KEY_H and state.map.profile.id == "el1": _centre_hero()
		elif event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
			following = -1
			view_moved = true
	if not director.dialogue.is_empty(): return
	if event is InputEventMouseMotion:
		_pointer_on_map = hud == null or hud.map_rect().has_point(event.position)
		if second_hud != null: _tip_on_map = true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and second_hud != null:
			if event.pressed: _second_right_press(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed and not state.camera_locked
			# First game: a right click on an own hero cancels its order
			# (TUT_HERO_CLICK); a drag only turns the camera. The map info
			# panel shows only while the right button is held (original
			# capture), not on hover.
			if event.pressed:
				_right_origin = event.position
				if hud != null: hover(event.position)
			else:
				if hud != null: hud.show_tooltip(-1, {}, Vector2.ZERO)
				if hud != null and event.position.distance_to(_right_origin) <= ELSecondMapTooltips.DRAG_THRESHOLD:
					# Free movement: a right click stops the walking hero (#171).
					if strategic_session == null and director.stop_free_walk(): _refresh_hero_info()
					else: _cancel_order_at(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			view_goal = Vector2(-1, -1)
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), zoom_limits.x, zoom_limits.y)
			if second_hud != null:
				map_tip.clear()
				second_hud.hide_map_tooltip()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if hit != null and hud != null and ELHeroExchange.applies(state) and (event.ctrl_pressed or event.double_click) and _hero_click(Vector2i(floori(hit.x / 2.0), floori(-hit.z / 2.0)), event.ctrl_pressed): return
			if hit != null and hud != null and event.double_click and not event.ctrl_pressed and castle_double_click(event.position, hit): return
			if hit != null:
				var corpse := _corpse_under_pointer(event.position) if second_hud != null else -1
				var body := state.object(corpse)
				# First game: the click uses what the cursor shows, also a
				# castle tower or figure drawn over the ground behind it.
				var shown := _object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, event.position) if hud != null else -1
				# Second game: the click uses the figure the cursor shows (its
				# reach around the figure, ELSecondMapTooltips.object_at), not
				# the ground tile under the pointer: a click off a creature's
				# middle walked to that tile instead of attacking, by a route
				# that depended on the side clicked (#155).
				if second_hud != null and corpse < 0: shown = second_click_figure(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL)
				var picked := state.object(shown)
				if body.get("enabled", false):
					_click_ground(Vector2i(body.x, body.y), corpse)
				elif picked.get("enabled", false):
					_click_ground(Vector2i(picked.x, picked.y), shown)
				else:
					_click_ground(Vector2i(floori(hit.x / 2.0), floori(-hit.z / 2.0)))
	elif event is InputEventMouseMotion and second_hud != null and _right_down and not dragging:
		if not state.camera_locked and event.position.distance_to(_right_origin) > ELSecondMapTooltips.DRAG_THRESHOLD:
			dragging = true
			map_tip.release()
			second_hud.hide_map_tooltip()
	elif event is InputEventMouseMotion and dragging:
		# Options: mouse rotation speed and (second game) inverted rotation.
		var turn := float(settings.values.get("mouse_rotation", 1.0)) if settings != null else 1.0
		if settings != null and bool(settings.values.get("invert_rotation", false)): turn = -turn
		yaw -= event.relative.x * 0.006 * turn
		yaw_goal = INF
		view_goal = Vector2(-1, -1)
		pitch = clampf(pitch + event.relative.y * 0.004, pitch_limits.x, pitch_limits.y)
		# A held right button keeps the info panel at the cursor until it drags.
		if hud != null:
			if event.position.distance_to(_right_origin) <= ELSecondMapTooltips.DRAG_THRESHOLD: hover(event.position)
			else: hud.show_tooltip(-1, {}, Vector2.ZERO)
	elif event is InputEventMouseMotion and hud != null and hud.tooltip.visible: hud.show_tooltip(-1, {}, Vector2.ZERO)

static func _enter(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]

## Enter on a first-game panel: its check button, when shown and enabled.
static func _press_check(buttons: Dictionary, controls: Array) -> void:
	for control: String in controls:
		var button: BaseButton = buttons.get(control)
		if button == null or not is_instance_valid(button) or not button.is_visible_in_tree(): continue
		if not button.disabled: button.pressed.emit()
		return

func _shop_hotkey(key: InputEventKey) -> void:
	if key.keycode == KEY_ESCAPE:
		if first_shop != null: first_shop.cancel_trade()
		elif rune_shop != null: rune_shop.cancel_trade()
		else: shop.cancel_trade()
	elif rune_shop != null and key.keycode in RUNE_SHOP_KEYS:
		rune_shop.move_selection(RUNE_SHOP_KEYS[key.keycode])
	elif shop == null and not key.echo:
		var action := ELSettings.hotkey_action(settings, state.map.profile.id, "Shops", key)
		match action:
			"shop_confirm":
				if first_shop != null: first_shop.accept()
				else: rune_shop.accept()
			"shop_buy":
				if first_shop != null: first_shop.buy()
				elif rune_shop != null: rune_shop.buy()
			"shop_undo":
				if first_shop != null: first_shop.retrieve()
				elif rune_shop != null: rune_shop.retrieve()
			_: return
	else: return
	get_viewport().set_input_as_handled()

## Second game: every cursor move is seen here, before the panels take it;
## _unhandled_input marks the moves that reached the map. A right release
## anywhere ends the press.
func _input(event: InputEvent) -> void:
	var blocked := _mission_fade != null or (not paused and _reward_transition())
	var key := event as InputEventKey
	if key != null:
		if not key.pressed: _held_dialogue_keys.erase(key.keycode)
		elif blocked or _reward_dialog_open(): _held_dialogue_keys[key.keycode] = true
		if key.pressed and key.echo and _held_dialogue_keys.has(key.keycode):
			get_viewport().set_input_as_handled()
			return
	if blocked:
		get_viewport().set_input_as_handled()
		return
	# A map notice owns its confirmation keys before focused controls or a
	# script line waiting to be shown. A script box already over it takes priority.
	if key != null and not console_open and building_message != null and not dialogue_blocker.visible:
		var box := building_message.message_box
		if box != null and box.is_visible_in_tree():
			var answer := box.key_answer(key.keycode)
			if not answer.is_empty():
				get_viewport().set_input_as_handled()
				if key.pressed and not key.echo: box.answered.emit(answer)
				return
	if event is InputEventMouseMotion:
		_pointer = event.position
		_pointer_on_map = false
		_cursor_moved = true
	# First game: a right release over a window or menu (Esc opened one while
	# the button was held) still ends the camera drag and the info panel,
	# or the view would keep turning and the panel stay on screen.
	if hud != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		dragging = false
		hud.show_tooltip(-1, {}, Vector2.ZERO)
	if second_hud == null: return
	if event is InputEventMouseMotion:
		_tip_point = event.position
		_tip_on_map = false
		_tip_moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and _right_down:
		_right_down = false
		_cursor_moved = true
		dragging = false
		map_tip.release()
		second_hud.hide_map_tooltip()

func _second_right_press(at: Vector2) -> void:
	_right_down = true
	_cursor_moved = true
	_right_origin = at
	dragging = false
	_tip_point = at
	_tip_on_map = true
	if _map_tooltip_blocked(): return
	map_tip.update(_map_tip_pick(), 0.0, true)
	map_tip.press()
	_tip_content = {}
	_show_map_tip()

## Panels, dialogs, menus, scripted messages and pauses close the map tooltip.
func _map_tooltip_blocked() -> bool:
	return director == null or state == null or paused or not error.is_empty() or extras_open() or not director.dialogue.is_empty() \
		or hero_screen != null or building_screen != null or building_message != null or global_spells != null or diplomacy != null \
		or first_shop != null or rune_shop != null or shop != null or skills != null or spellbook != null or notebook != null \
		or second_hud.menu.visible or result_shown

## The object under the last map cursor position, or -1.
func _map_tip_pick() -> int:
	if not _tip_on_map or _tip_point.x < 0: return -1
	var corpse := _corpse_under_pointer(_tip_point)
	if corpse >= 0: return corpse
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(_tip_point), camera.project_ray_normal(_tip_point))
	if hit == null: return -1
	return ELSecondMapTooltips.object_at(state, Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL)

## Updates come from cursor moves (at most ten a second) and, while the
## camera moves, five times a second; between them the timers run.
func _tick_map_tooltip(delta: float) -> void:
	if _map_tooltip_blocked():
		if map_tip.subject >= 0 or second_hud.map_tooltip.visible:
			map_tip.reset()
			_right_down = false
			second_hud.hide_map_tooltip()
		return
	map_tip.hover = bool(settings.values.get("map_tooltips", true)) if settings != null else true
	var updated := false
	_tip_clock += delta
	if _tip_moved and _tip_clock >= ELSecondMapTooltips.MOVE_INTERVAL:
		updated = true
		_tip_moved = false
		_tip_clock = 0.0
	var view_signature := "%s/%.4f/%.4f/%.3f" % [target, yaw, pitch, zoom]
	if view_signature != _tip_camera:
		_tip_camera = view_signature
		_tip_camera_clock += delta
		if _tip_camera_clock >= ELSecondMapTooltips.CAMERA_INTERVAL:
			updated = true
			_tip_camera_clock = 0.0
	else: _tip_camera_clock = 0.0
	var id := map_tip.subject
	if updated or (id >= 0 and not ELSecondMapTooltips.pickable(state, state.object(id))): id = _map_tip_pick()
	if id != map_tip.subject: _tip_content = {}
	map_tip.update(id, delta, updated)
	if map_tip.shown:
		if updated: _tip_content = {}
		_show_map_tip()
	elif second_hud.map_tooltip.visible:
		_tip_content = {}
		second_hud.hide_map_tooltip()

func _show_map_tip() -> void:
	if not map_tip.shown:
		second_hud.hide_map_tooltip()
		return
	if _tip_content.is_empty():
		var item := state.object(map_tip.subject)
		_tip_content = ELSecondMapTooltips.describe(state, item, ELSecondMapTooltips.row_for(_art, item))
	second_hud.show_map_tooltip(map_tip.subject, _tip_content, _tip_point)

## Original action cursor for the pointer, re-picked at most ten times a
## second (the original's mouse-move throttle) and when the map changes.
func _tick_cursor(delta: float) -> void:
	# A battle over the suspended map owns the cursor.
	if state == null or director == null or not visible: return
	var second := state.map.profile.id == "el2"
	if second and (state.exclusive or not state.commands.is_empty()):
		_script_busy = maxf(_script_busy, 0.0) + delta
	else: _script_busy = -1.0
	_cursor_clock += delta
	if _cursor_clock < ELSecondMapTooltips.MOVE_INTERVAL and not _cursor_moved: return
	_cursor_clock = 0.0
	_cursor_moved = false
	update_cursor()

## Picks the cursor for the last pointer position and requests it.
func update_cursor() -> void:
	if state == null or director == null or camera == null: return
	var second := state.map.profile.id == "el2"
	var context := {"hero": _hero_id(), "picked": -1, "tile": Vector2i(-1, -1), "on_map": _pointer_on_map and _pointer.x >= 0,
		"in_bounds": false, "modal": _cursor_modal(), "right_held": second and _right_down, "busy_time": _script_busy,
		"previous": cursor_name if not cursor_name.is_empty() else "default", "local_turn": director.can_move()}
	if context.on_map and not context.modal:
		var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(_pointer), camera.project_ray_normal(_pointer))
		if hit != null:
			var point := Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL
			context.tile = Vector2i(floori(point.x), floori(point.y))
			context.in_bounds = context.tile.x >= 0 and context.tile.y >= 0 and context.tile.x < state.map.width and context.tile.y < state.map.height
			if second:
				context.picked = _corpse_under_pointer(_pointer)
				if context.picked >= 0:
					var corpse := state.object(context.picked)
					context.tile = Vector2i(corpse.x, corpse.y)
					context.in_bounds = true
				elif context.in_bounds: context.picked = ELSecondMapTooltips.object_at(state, point, true)
			else:
				# A tall figure near the map edge is drawn over ground
				# beyond it: the pick then gives the cursor its tile.
				context.picked = _object_at(point, _pointer)
				var shown := state.object(context.picked)
				if not context.in_bounds and not shown.is_empty():
					context.tile = Vector2i(shown.x, shown.y)
					context.in_bounds = true
	cursor_context = context
	cursor_name = ELCursors.second_adventure(state, director, context) if second else ELCursors.first_adventure(state, director, context)
	if not edge_cursor.is_empty() and not context.modal: cursor_name = edge_cursor
	ELCursorDriver.request(state.map.profile, cursor_name)

## Windows, panels and message boxes over the map show the default cursor.
func _cursor_modal() -> bool:
	return _mission_fade != null or _reward_transition() or paused or console_open or not error.is_empty() or extras_open() or not director.dialogue.is_empty() \
		or hero_screen != null or building_screen != null or building_message != null or global_spells != null or diplomacy != null \
		or first_shop != null or rune_shop != null or shop != null or skills != null or spellbook != null or notebook != null \
		or (second_hud != null and second_hud.menu.visible) or result_shown \
		or (hud != null and hud.precombat.visible) or (second_precombat != null and second_precombat.visible) or lose_battle != null

## Original map tooltip for the castle, hero or creature under the cursor.
func hover(at: Vector2) -> void:
	var id := -1
	if hud.map_rect().has_point(at):
		var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
		if hit != null: id = _object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, at)
	var item := state.object(id)
	hud.show_tooltip(id, hud.describe(item, _art.resolve(item).get("row", {})) if not item.is_empty() else {}, at)

## First-game building groups with their own map tooltip (and use cursor).
const FIRST_SITE_GROUPS := ["mines", "mana_nodes", "forts", "laboratories", "factories", "resource_cuts"]

## Standing figures extend above their tile, so actors accept points slightly
## behind them; buildings use their footprint. With the pointer's screen
## position, the camera ray also picks the visible body of a figure or a tall
## building (a castle tower drawn over the ground behind it).
func _object_at(point: Vector2, screen := Vector2(-1, -1)) -> int:
	var best := -1
	var distance := INF
	var building := -1
	var building_depth := INF
	var origin := Vector3.ZERO
	var normal := Vector3.ZERO
	if screen.x >= 0 and camera != null and world != null:
		origin = world.to_local(camera.project_ray_origin(screen))
		normal = world.global_basis.inverse() * camera.project_ray_normal(screen)
	# This runs on every pointer move: the cheap position tests come first,
	# the fog and kind lookups only for objects under the pointer.
	var first := state.map.profile.id == "el1"
	var footprints: Dictionary = director.grid.footprints
	# First game: the figure's wide reach (its body above neighbouring
	# cells) gives way to an object whose own cell is under the pointer, so
	# a pickup next to the hero can still be clicked (#79).
	var own_cell := false
	# A figure's reach runs away from the camera (its body is drawn over the
	# ground behind it), whichever way the view is turned.
	var behind := Vector2(0.0, 1.0)
	if normal != Vector3.ZERO and Vector2(normal.x, -normal.z).length() > 0.01: behind = Vector2(normal.x, -normal.z).normalized()
	# Depth along the camera ray to the picked figure's drawn body, when the
	# pointer is over it (INF when only its reach on the ground matched).
	var body_depth := INF
	for id: int in state.objects:
		var item: Dictionary = state.objects[id]
		if not item.alive or not item.visible or not item.get("placed", true) or item.get("fortified", false): continue
		var kind: Variant = item.get("type")
		if kind == "hero" or kind == "monster":
			var offset := point - Vector2(float(item.x) + 0.5, float(item.y) + 0.5)
			var near := offset.length()
			if near >= distance: continue
			var along := offset.dot(behind)
			var hit := absf(offset.cross(behind)) < 0.9 and along > -0.9 and along < 2.2
			# The drawn body, with some slack, so a figure takes a click
			# anywhere on it, not only near its middle.
			var depth := INF
			if normal != Vector3.ZERO and near < 16.0:
				var crossing: Variant = _pick_box(id, Rect2(float(item.x) + 0.15, float(item.y) + 0.15, 0.7, 0.7), 1.6).grow(FIGURE_SLACK).intersects_ray(origin, normal)
				if crossing != null: depth = origin.distance_to(crossing)
			if (hit or depth < INF) and not _fogged(item):
				best = id
				distance = near
				body_depth = depth
				own_cell = Rect2(item.x, item.y, 1, 1).has_point(point)
		elif best < 0 or (first and not own_cell and building_depth >= 0.0):
			var size: Vector2i = footprints.get(id, {}).get("size", Vector2i.ONE)
			var cells := Rect2(item.x, item.y, size.x, size.y)
			# With a figure already found, only an object's own cells count.
			if best >= 0 and not cells.has_point(point): continue
			# The footprint under the pointer wins; otherwise the nearest
			# building body the camera ray passes through.
			var depth := INF
			if cells.has_point(point): depth = -1.0
			elif normal != Vector3.ZERO and cells.grow(16.0).has_point(point):
				var crossing: Variant = _pick_box(id, cells, 0.0).intersects_ray(origin, normal)
				if crossing != null: depth = origin.distance_to(crossing)
			if depth >= building_depth: continue
			var group := str(item.get("group", ""))
			if not (ELFirstScenario.is_castle(item) or (first and group in FIRST_SITE_GROUPS) or (ELMapPickups.is_pickup(item) and (first or group == "artefacts")) or (group == "additional_buildings" and first and not ELAdditionalBuildings.title(state.map.profile, item).is_empty())): continue
			if _fogged(item): continue
			building = id
			building_depth = depth
	# The object on the ground behind a figure wins (#79), unless the pointer
	# is over the figure's body and that body is drawn in front of it.
	if first and best >= 0 and not own_cell and building >= 0 and building_depth < 0.0:
		if body_depth == INF: return building
		var size: Vector2i = footprints.get(building, {}).get("size", Vector2i.ONE)
		var item: Dictionary = state.objects[building]
		var crossing: Variant = _pick_box(building, Rect2(item.x, item.y, size.x, size.y), 0.0).intersects_ray(origin, normal)
		if crossing != null and origin.distance_to(crossing) < body_depth: return building
	return best if best >= 0 else building

## Second game: the hero or creature a left click at `point` (map cells)
## acts on, the one the cursor shows (ELSecondMapTooltips.object_at, the
## figure's reach); -1 for none or the hero giving the order (#155).
func second_click_figure(point: Vector2) -> int:
	var figure := ELSecondMapTooltips.object_at(state, point, true)
	return figure if state.object(figure).get("type") in ["hero", "monster"] and figure != _hero_id() else -1

## Slack (world units) around a figure's drawn body for picking it.
const FIGURE_SLACK := 0.35

## Box the camera ray tests for an object: its footprint `cells` (map
## cells), `fallback` cells tall, merged with its drawn figure. Buildings keep
## theirs; moving figures are measured where they stand.
var _pick_boxes: Dictionary = {}
func _pick_box(id: int, cells: Rect2, fallback: float) -> AABB:
	if _pick_boxes.has(id) and not world.actors.has(id): return _pick_boxes[id]
	var cell := ELAdventureTerrain.CELL
	var box := AABB(Vector3(cells.position.x * cell, 0.0, -cells.end.y * cell), Vector3(cells.size.x * cell, fallback * cell, cells.size.y * cell))
	var drawn := world.object_bounds(id)
	if drawn.has_volume(): box = box.merge(drawn)
	_pick_boxes[id] = box
	return box

## Objects the local player cannot see under the first-game fog are not picked.
func _fogged(item: Dictionary) -> bool:
	return ELFog.active(state, state.current_player) and not ELFog.shown(state, state.current_player, item)

func _corpse_under_pointer(at: Vector2) -> int:
	var id := world.corpse_at(camera.project_ray_origin(at), camera.project_ray_normal(at))
	return id if ELSecondMapTooltips.pickable(state, state.object(id)) else -1

func _click_ground(tile: Vector2i, use_id := -1) -> void:
	var second := state.map.profile.id == "el2"
	var hero_id := _hero_id()
	for id: int in state.objects if use_id < 0 else []:
		var item: Dictionary = state.objects[id]
		var corpse: bool = second and item.type == "corpse"
		if id == hero_id or not (item.alive or corpse) or not item.visible or not item.enabled or not item.get("placed", true) or item.get("fortified", false) or item.group == "terrain_objects" or _fogged(item): continue
		var size: Vector2i = director.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
		if Rect2i(item.x, item.y, size.x, size.y).has_point(tile):
			if use_id < 0 or corpse: use_id = id
			if not second or corpse: break
	var site := state.object(use_id)
	if state.map.profile.id == "el1" and not site.is_empty() and site.type == "hero" and site.owner == state.current_player:
		_select_hero(use_id)
		if tutorial_panel != null: tutorial_panel.map_click(site, false)
		return
	# An own mine or ether node takes no order and opens nothing (EL1
	# EL2 move-and-use has no action for it). An own fort is used
	# like any fort: entered when empty, left by its own garrison (EL2).
	if not site.is_empty() and ELResourceSites.TYPES.has(site.group) and site.owner == state.current_player: return
	if site.get("type") in ["el1_spell_shop", "rune_shop"] and _open_strategy_shop(hero_id, use_id): return
	var ordered := director.request_move(_hero_id(), tile, use_id) if strategic_session == null else strategic_session.move(_hero_id(), tile, use_id)
	if not ordered: _remark(director.notice)
	else:
		_remark(director.notice)
		# Second game: a move order brings the view back to the hero unless the
		# player is moving the view at the same moment (#28). First game: the
		# order only plans the route (carried out at night, or on the second
		# choice with free movement), and the view stays on the destination
		# the player picked (#170); the hero's walk itself is followed.
		if not _panning_view() and second_hud != null:
			following = _hero_id()
			view_moved = false
	if tutorial_panel != null and _hero_id() >= 0: tutorial_panel.map_click(site, ordered)

func _cancel_map_order(hero := -1) -> void:
	var id := _hero_id() if hero < 0 else hero
	if strategic_session != null: strategic_session.cancel(id)
	else: director.cancel_order(id)

## The player is panning the view right now: a pan key held or the pointer
## scrolling at the screen edge.
func _panning_view() -> bool:
	if _edge_pan != Vector2.ZERO: return true
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if Input.is_physical_key_pressed(key): return true
	return false

func _centre_hero() -> void:
	following = _hero_id()
	view_moved = false

## Touch gestures (remake addition): the same camera limits as the mouse.
func touch_camera_ready() -> bool:
	return visible and camera != null and director != null and state != null and not _cursor_modal() \
		and not (hud != null and hud.precombat.visible) and not (second_precombat != null and second_precombat.visible)

## One finger moves the ground under it.
func touch_pan(from: Vector2, to: Vector2) -> void:
	if state.camera_locked: return
	var ground := Plane(Vector3.UP, 0)
	var a: Variant = ground.intersects_ray(camera.project_ray_origin(from), camera.project_ray_normal(from))
	var b: Variant = ground.intersects_ray(camera.project_ray_origin(to), camera.project_ray_normal(to))
	if a == null or b == null: return
	following = -1
	scroll_gliding = false
	view_moved = true
	target += (a as Vector3) - (b as Vector3)
	_clamp_target()
	_hide_touch_tip()
	_update_camera()

## The view's centre stays over the map (scrolling stops at its edges).
func _clamp_target() -> void:
	var low := ELAdventureScene.world_position(-0.5, float(state.map.height) - 0.5)
	var high := ELAdventureScene.world_position(float(state.map.width) - 0.5, -0.5)
	target.x = clampf(target.x, low.x, high.x)
	target.z = clampf(target.z, low.z, high.z)

func touch_orbit(turn: float, tilt: float) -> void:
	if state.camera_locked: return
	yaw += turn
	if turn != 0.0: yaw_goal = INF
	view_goal = Vector2(-1, -1)
	pitch = clampf(pitch + tilt, pitch_limits.x, pitch_limits.y)
	_hide_touch_tip()
	_update_camera()

func touch_zoom(factor: float) -> void:
	view_goal = Vector2(-1, -1)
	zoom = clampf(zoom / factor, zoom_limits.x, zoom_limits.y)
	_hide_touch_tip()
	_update_camera()

func touch_bar_keys() -> Array:
	var keys := [["Save", KEY_F5], ["Load", KEY_F9]]
	if tutorial_panel != null: keys.append(["Tutorial", KEY_H])
	return keys

func _hide_touch_tip() -> void:
	if second_hud != null:
		map_tip.clear()
		second_hud.hide_map_tooltip()
	elif hud != null: hud.show_tooltip(-1, {}, Vector2.ZERO)

func _update_camera() -> void:
	if camera == null: return
	# Kept within one turn: endless turning must not grow the saved angle.
	yaw = fposmod(yaw, TAU)
	camera.size = zoom
	# Orthographic: far back, `zoom` units tall; perspective: `zoom` away.
	var reach := zoom if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 80.0
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * reach
	camera.look_at(target)
	state.camera_zoom = view_goal.x if _script_lens and view_goal.x > 0 else zoom
	state.camera_rotation = rad_to_deg(yaw)
	state.camera_pitch = -rad_to_deg(pitch)
	state.camera_scroll = Vector2(target.x / ELAdventureTerrain.CELL - 0.5, -target.z / ELAdventureTerrain.CELL - 0.5)
	if hud != null: hud.set_view(target, yaw)

func _present(data: Dictionary) -> void:
	match data.kind:
		"spell_shop": _open_shop()
		"rune_shop", "el1_spell_shop":
			if global_spells != null: _close_global_spells()
			if building_message != null or _reward_transition():
				deferred_shop = data
				return
			if data.kind == "rune_shop": _open_rune_shop()
			else: _open_first_shop()
		"actor_moving": world.move_actor(data.id, data.position, data.moving, director.movement_speed(state.object(data.id)), director.fast_mode)
		"orient": world.orient_actor(data.id, data.direction)
		"route":
			if strategic_session != null and state.object(data.id).get("owner") != state.current_player: return
			# Night moves: the view goes with heroes the local player can see,
			# never into the fog after an unseen one.
			if not director.strategy.is_empty():
				if ELFog.shown(state, state.current_player, state.object(data.id)): following = data.id
			# Second game: the view goes with the main hero on a scripted walk,
			# as after the e2mission11 gate greeting (original captures).
			elif script_camera_attached and state.map.profile.id == "el2" and int(data.id) == state.main_hero and director.movement.get("queued", false) and not data.path.is_empty(): following = data.id
			_draw_route(data.path, data.id)
		"strategy_phase":
			if data.phase == "planning":
				following = _hero_id()
				_draw_route(ELStrategy.order_path(director, state.object(_hero_id())))
				var hint := "Choose a destination, then choose it again to move; end the day when your heroes are done." if ELStrategy.free_mode(director) else "Plan your heroes' orders, then end the turn."
				_remark(director.notice if not director.notice.is_empty() else hint)
			elif director.strategy.get("free", "") == "act": _remark("Moving…")
			elif director.strategy.get("free", "") == "ai": _remark("Other players are moving…")
			else: _remark("Resolving " + str(data.phase) + "…")
			_refresh_hero_info()
		"dialogue":
			var speech: Dictionary = data.dialogue
			if state.map.profile.id == "el2" and camera != null and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
				if text_view.is_empty(): text_view = {"zoom": zoom if view_goal.x < 0 else view_goal.x, "pitch": pitch if view_goal.x < 0 else view_goal.y}
				view_goal = Vector2(SECOND_TEXT_ZOOM, SECOND_TEXT_PITCH)
				_script_lens = false
			if second_dialogue != null:
				if _mission_fade == null and not _reward_transition() and (int(speech.get("actor", -1)) < 0 or _speaker_in_place()): _show_second_dialogue(speech)
				else: _pending_speech = speech
				return
			dialogue_name.text = speech.title
			dialogue_text.text = speech.text
			(accept as Button).text = "Yes" if speech.question else "Continue  [Space]"
			decline.visible = speech.question
			# Script boxes without a speaker (-1) have no portrait.
			var art := _art.resolve(state.object(speech.actor)) if not state.object(speech.actor).is_empty() else {}
			var face := int(art.get("row", {}).get("Face", -1))
			dialogue_portrait.texture = state.map.profile.portrait(face) if face >= 0 else null
			dialogue_panel.show()
			_place_dialogue(speech)
			audio.speak(speech.text_id)
			accept.grab_focus()
		"dialogue_closed":
			_pending_speech = {}
			if not text_view.is_empty():
				view_goal = Vector2(float(text_view.zoom), float(text_view.pitch))
				text_view = {}
				_script_lens = false
				# Lines answered before the view moved leave nothing to ease back.
				if absf(zoom - view_goal.x) < 0.01 and absf(pitch - view_goal.y) < 0.001: view_goal = Vector2(-1, -1)
			dialogue_panel.hide()
			if second_dialogue != null: second_dialogue.hide()
			_dock_dialogue()
			audio.voice.stop()
			audio.voice.stream = null
		"CameraToObject":
			var id := int(data.arguments[0])
			_focus_object(id)
			# An attached main-hero focus returns control from a cutscene.
			if script_camera_attached and id >= 0 and id == state.main_hero:
				following = id
				view_moved = false
		"CameraToPos": _scroll_to(ELAdventureScene.world_position(float(data.arguments[0]), float(data.arguments[1])))
		"CameraAttach":
			var was_attached := script_camera_attached
			script_camera_attached = ELAdventureSession._truthy_flag(data.arguments[0])
			if not script_camera_attached:
				following = -1
			elif not was_attached and world.actors.has(state.main_hero):
				# The tutorial mirror focuses the hero before attaching the camera.
				var hero := state.object(state.main_hero)
				if not hero.is_empty() and camera_goal() == ELAdventureScene.world_position(hero.x, hero.y):
					following = state.main_hero
					view_moved = false
		"CameraRotate": yaw_goal = deg_to_rad(float(data.arguments[0]))
		"CameraRotateToObject", "CameraRotateToPos":
			# The angle runs from the main hero's cell to the object or cell,
			# not from the camera's point (: ExGetMainHeroID
			# position, then -atan2(dx, dy); a missing hero reads as (-1,-1)).
			var point := Vector2.ZERO
			if data.kind == "CameraRotateToObject":
				var item := state.object(data.arguments[0])
				if item.is_empty(): return
				point = Vector2(float(item.x), float(item.y))
			else: point = Vector2(float(data.arguments[0]), float(data.arguments[1]))
			var hero := state.object(state.main_hero)
			var from := Vector2(float(hero.get("x", -1)), float(hero.get("y", -1)))
			yaw_goal = atan2(-(point.x - from.x), point.y - from.y)
		"encounter":
			if building_message != null or _reward_transition():
				# The building's message is read before the battle it announces.
				deferred_encounter = data
				return
			if hud != null and precombat_preview and strategic_session == null:
				var number := 1
				var total := 1
				if director.strategy.get("phase") == "combat":
					number = int(director.strategy.index)
					total = director.strategy.combats.size()
				pending_encounter = [data.hero, data.opponent]
				# The view centres between the two sides, as for the second
				# game's panel (not left on the last hero that moved).
				var ends: Array[Vector3] = []
				for id: int in [int(data.hero), int(data.opponent)]:
					var side := state.object(id)
					if not side.is_empty() and side.get("placed", true) and int(side.get("x", -1)) >= 0: ends.append(ELAdventureScene.world_position(side.x, side.y))
				if not ends.is_empty() and not state.camera_locked:
					following = -1
					target = (ends[0] + ends[-1]) * 0.5
				# First game: the original orders show the original panel alone,
				# whose battle cannot be declined; free movement shows the
				# check mark and the cross (player report #137).
				var choice := ELStrategy.free_mode(director)
				hud.show_precombat(data.hero, data.opponent, number, total, choice and director.encounter != null and director.encounter.declinable(), choice)
				if dome_source != null:
					_start_battle_dome(int(data.hero), int(data.opponent))
					# The dome rises at the centre of the view; the panel moves
					# down out of its way.
					if effects != null and effects.effects.has(BATTLE_DOME): hud.lower_precombat()
			elif second_precombat != null and precombat_preview and not data.get("remote_use", false): _open_second_precombat(data.hero, data.opponent)
			else: encounter_requested.emit(data.hero, data.opponent)
		"lose_battle": _open_lose_battle()
		"auto_fight": _show_auto_fight(int(data.hero), int(data.opponent))
		"auto_fight_defeat":
			for loser: int in data.losers: _auto_fight_defeat(loser)
		"auto_fight_end": _finish_battle_dome()
		"travel_phase": _travel_phase()
		"travel_finished":
			if effects != null: effects.finish("portal_travel")
			var model: ELModel = world.actors.get(int(data.hero))
			if model != null:
				if model.has_meta("portal_hidden"): model.remove_meta("portal_hidden")
				model.set_opacity(1.0)
				world.fog_object(state.object(data.hero))
		"teleport", "tunnel", "dock":
			if ELFirstNaval.enabled(state.map) and data.kind == "dock":
				# First-game selection is not always the original main hero.
				# Other ships boarding must not steal the player's camera.
				if int(data.hero) == _hero_id(): _draw_route(ELStrategy.order_path(director, state.object(_hero_id())))
			else:
				if not director.travel.is_empty(): _face_travel_exit()
				if data.hero == state.main_hero and world.actors.has(state.main_hero):
					following = _hero_id()
					target = world.actors[state.main_hero].position
					_draw_route([])
		"use_object":
			var item := state.object(data.target)
			_remark(item.get("title", state.map.profile.text(str(_art.resolve(item).get("row", {}).get("ELKName", item.name)))))
		# Script and engine failures, and battles the remake cannot start, stay
		# visible; refused orders are remake readouts.
		"error": notice.text = data.text
		"notice":
			if data.text == ELAdventureDirector.BATTLE_REFUSED: notice.text = data.text
			else: _remark(data.text)
		"building_message":
			_remark(data.text)
			_queue_building_message(data)

## A portal hides its traveller until the receiver's effect has finished.
## At a dock the departing figure fades before the switch to the new model.
func _travel_pose() -> void:
	var travel := director.travel
	if travel.is_empty(): return
	var model: ELModel = world.actors.get(int(travel.hero))
	if model == null: return
	if travel.kind == "teleport":
		model.set_meta("portal_hidden", true)
		model.hide()
	elif not travel.arrived: model.set_opacity(clampf(float(travel.remaining) / ELAdventureDirector.DOCK_FADE_SECONDS, 0.0, 1.0))

func _travel_phase(play_sound := true) -> void:
	var travel := director.travel
	_travel_pose()
	if not play_sound and travel.arrived: _face_travel_exit()
	if travel.kind != "teleport" or effects == null: return
	effects.finish("portal_travel")
	if float(travel.remaining) <= 0.0: return
	var portal := state.object(travel.target if travel.arrived else travel.source)
	if portal.is_empty(): portal = state.object(travel.hero)
	var center := ELAdventureGrid.center(portal, _art.resolve(portal).get("row", {})) * ELAdventureTerrain.CELL
	var at := {"x": center.x, "y": center.y, "z": 0.0}
	effects.start("portal_travel", at.merged({"file": "teleport.pfx"}), ELAdventureDirector.PORTAL_SECONDS - float(travel.remaining), true)
	if play_sound and audio != null:
		if travel.arrived: audio.listener = target
		audio.start_sound("portal_travel", at.merged({"file": "Adventure/teleport.wav", "near": 30.0, "far": 60.0}))

func _face_travel_exit() -> void:
	var travel := director.travel
	var destination := state.object(travel.target)
	if destination.is_empty(): return
	var center := ELAdventureGrid.center(destination, _art.resolve(destination).get("row", {}))
	var away := Vector2(float(travel.x) + 0.5, float(travel.y) + 0.5) - center
	if absf(away.x) > absf(away.y): away.y = 0.0
	else: away.x = 0.0
	world.orient_actor(int(travel.hero), away)

## The first colourless drain of a hero's day (any owner) plays the dying
## particle and the white-zone sound once where the hero is drawn at that
## moment. The particle does not follow the hero, is not a script effect and is
## not saved; the sound is positional (full within 8 units, silent past 16).
func colorless_drain(uid: int) -> void:
	var hero := state.object(uid)
	if hero.is_empty() or world == null: return
	var at := ELAdventureScene.world_position(float(hero.get("x", 0)), float(hero.get("y", 0)))
	var actor: Variant = world.actors.get(uid)
	if actor is Node3D and is_instance_valid(actor): at = world.to_local((actor as Node3D).global_position)
	var entry := {"file": "Dying.pfx", "x": at.x, "y": -at.z, "z": at.y}
	var name := "colorless_drain:%d" % uid
	if effects != null: effects.start(name, entry, 0.0)
	if audio != null: audio.start_sound(name, entry.merged({"file": "Adventure/whitezonehb.wav", "near": 8.0, "far": 16.0, "loop": false}, true))

## Second game, after a specialization
## shrine or a beacon: Bereserk.pfx once where the hero stands and
## Adventure\stars1.wav placed there (near 1, far 32). Not saved.
func hero_change_effect(uid: int) -> void:
	var hero := state.object(uid)
	if hero.is_empty() or world == null or not ELFog.shown(state, 1, hero): return
	var at := _hero_effect_position(hero)
	var entry := {"file": LEVEL_EFFECT, "x": at.x, "y": -at.z, "z": at.y, "loops": 0}
	var name := "hero_change:%d" % uid
	if effects != null: effects.start(name, entry, 0.0)
	if audio != null: audio.start_sound(name, entry.merged({"file": "Adventure/stars1.wav", "near": 1.0, "far": 32.0, "loop": false, "effects": true}, true))
	_change_effects[uid] = Time.get_ticks_msec() + int(CHANGE_EFFECT_SECONDS * 1000.0)

func _hero_effect_position(hero: Dictionary) -> Vector3:
	var actor: ELModel = world.actors.get(int(hero.uid))
	if is_instance_valid(actor): return world.to_local(actor.global_position)
	return ELAdventureScene.world_position(float(hero.x), float(hero.y))

## CHero::PlayChangeEffect (Etherlords2.exe 0x66a661) queues the effect, its
## sound, a 30-tick wait (15 ticks a second: the 61 frames of Bereserk.pfx)
## and their end on the adventure command queue; the shrine's or beacon's
## message box is queued after them (e.g. 0x4c6c31-0x4c6c8b), so it opens
## once the effect has played (#159; it opened at once over it).
const CHANGE_EFFECT_SECONDS := 30.0 / 15.0

## A building message for a hero whose change effect is playing waits for it
## (the map held meanwhile, as under the original command queue).
func _hold_for_change_effect(data: Dictionary) -> bool:
	var until := int(_change_effects.get(int(data.get("hero", -1)), 0))
	_change_effects.erase(int(data.get("hero", -1)))
	var left := (until - Time.get_ticks_msec()) / 1000.0
	if second_hud == null or left <= 0.0: return false
	_message_holds += 1
	paused = true
	dragging = false
	get_tree().create_timer(left).timeout.connect(func() -> void:
		if not is_inside_tree(): return
		_message_holds -= 1
		if effects != null: effects.finish("hero_change:%d" % int(data.hero))
		if building_message == null and _message_holds == 0: paused = false
		_show_building_message())
	return true

## First game, CDestroyMainTower start: the hero turns to the
## castle and plays its attack clip (code); the
## hero colour's GlobalXDMG.pfx and magic\GlobalXDamage.wav play at the castle
## (black for any other colour). Not saved.
const CASTLE_ATTACK_CODE := 0x1cc0000
func present_castle_assault(hero_id: int, player: int) -> void:
	var hero := state.object(hero_id)
	var castle := ELFirstScenario.castle_object(state, player)
	if hero.is_empty() or castle.is_empty() or world == null or (_fogged(hero) and _fogged(castle)): return
	var size: Vector2i = director.grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE)
	var middle := Vector2(float(castle.x) + size.x * 0.5, float(castle.y) + size.y * 0.5)
	world.orient_actor(hero_id, middle - Vector2(float(hero.x) + 0.5, float(hero.y) + 0.5))
	world.play_actor_code(hero_id, CASTLE_ATTACK_CODE)
	var colour := ELFirstSpellShop.hero_color(state.map.profile, hero)
	if colour not in ["Red", "Green", "Blue"]: colour = "Black"
	var at := ELAdventureScene.world_position(middle.x - 0.5, middle.y - 0.5)
	var entry := {"file": "Global%sDMG.pfx" % colour, "x": at.x, "y": -at.z, "z": at.y, "loops": 0}
	var name := "castle_assault:%d" % hero_id
	if effects != null: effects.start(name, entry, 0.0)
	if audio != null: audio.effect_sound("Magic/Global%sDamage.wav" % colour)

func _state_event(data: Dictionary) -> void:
	if data.kind == "exploration_changed" and bool(data.get("clear", false)) and world != null:
		world.snap_fog = true
	if data.kind in ["day_changed", "site_captured", "object_changed", "object_killed", "object_created", "skill_learned", "experience_gained"]: mana_readout = {}
	if world == null: return
	if audio != null: audio.script_event(data)
	if data.kind == "colorless_drain": colorless_drain(int(data.id))
	if data.kind == "hero_change_effect": hero_change_effect(int(data.id))
	if data.kind == "castle_assaulted": present_castle_assault(int(data.hero), int(data.player))
	if effects != null:
		effects.script_event(data)
		if data.kind == "script_effect_orient": effects.orient(str(data.name), world.object_yaw(state.object(int(data.id))))
	match data.kind:
		"resources_changed", "day_changed":
			if hero_info != null: _refresh_hero_info()
		"global_spells_changed":
			mana_readout = {}
			if global_spells != null: global_spells.refresh()
		"diplomacy_changed":
			if diplomacy != null: diplomacy.refresh()
		"show_inventory": _open_spellbook(int(data.id))
		"blink": if second_hud != null: second_hud.set_blink(str(data.element), bool(data.on))
		"inventory_changed":
			if spellbook != null and int(data.id) == int(spellbook.get("hero_id")): spellbook.call("refresh")
		"global_spell_ready":
			if int(data.player) == state.current_player: _offer_global_spell()
		"hero_placed":
			if data.get("recruited", false): focus_recruit(int(data.id))
		"summon_cast":
			present_summon(int(data.id), str(data.spell))
		"specialization_learned":
			# The original reports a learned specialisation in a message box.
			_remark(data.text)
			# Second game: ExGiveNewSpecialization only marks the specialization
			# on the command queue; the battle's end queues its message box
			# after the commands queued before it (Etherlords2.exe 0x67042f-
			# 0x670563), so it opens once they have run (#159).
			_queue_building_message({"kind": "building_message", "hero": data.id, "building": -1, "title": "", "text": data.text, "resources": [], "skill": "", "key": "",
				"wait_idle": second_hud != null})
		"site_captured":
			_remark("Captured " + ELResourceSites.title(state.map.profile, state.object(data.id)))
			_first_capture_box(data)
			_second_capture_box(data)
		"fort_entered":
			var hero := state.object(data.hero)
			if hero.owner == state.current_player: _remark("%s entered the %s." % [hero.get("title", hero.name), ELForts.title(state.map.profile, state.object(data.id)).to_lower()])
		"mine_depleted":
			if state.object(data.id).owner == state.current_player:
				_remark(ELResourceSites.title(state.map.profile, state.object(data.id)) + " is depleted.")
		"site_income":
			if data.player == state.current_player: _remark("Mine production · " + ELResources.describe(state.map.profile.id, data.amounts, false))
		"barrier_changed":
			# A first-game runestone sounds as its stones move away (instant.wav).
			if data.opened and presentation != null and world.first_barrier(state.object(data.id)): presentation.building_used(int(data.id), "instant")
		"object_changed", "object_killed", "object_created", "shape_changed", "fort_captured":
			var item := state.object(data.id)
			if state.map.profile.id == "el2" and data.get("pickup", false) and world.retire_pickup(int(data.id)): return
			world.update_object(item, bool(data.get("apply_facing", false)))
			world.fog_object(item)
			if state.map.profile.id == "el1" or item.get("type") == "hero": _refresh_roster()
		"ExCameraScrollToObject": _focus_object(int(data.arguments[0]), data.get("instant", false))
		"ExCameraScrollToPos": _scroll_to(ELAdventureScene.world_position(float(data.arguments[0]), float(data.arguments[1])), data.get("instant", false))
		"ExCameraRotate": yaw_goal = deg_to_rad(float(data.arguments[0]))
		"hero_animation": world.play_actor_clip(int(data.id), str(data.clip))
		"ExCameraZoom":
			var distance := clampf(float(data.arguments[0]), zoom_limits.x, zoom_limits.y)
			_set_script_lens(distance, -1.0, data.arguments.size() > 1 and float(data.arguments[1]) != -1.0)
		"ExCameraPitch":
			var angle := clampf(-deg_to_rad(float(data.arguments[0])), pitch_limits.x, pitch_limits.y)
			_set_script_lens(-1.0, angle, data.arguments.size() > 1 and float(data.arguments[1]) != -1.0)
		"mission_finished":
			_remark(data.get("text", "Mission complete" if data.outcome == "win" else "Mission lost"))
			hall_record = str(data.get("hall_of_fame", ""))
			_show_result()
		"resources_collected":
			if state.map.profile.id == "el1" and int(data.player) != state.current_player: return
			_remark("Collected " + ELResources.describe(state.map.profile.id, data.amounts, false))
			_first_pickup_box(data)
			_second_pickup_line(data)
		"shop_captured":
			_first_capture_box(data)
		"experience_gained":
			_note_first_level_up(data)
			if int(state.object(data.id).get("owner", -1)) != state.current_player: return
			if _finishing_battle and int(data.levels) > 0:
				_queue_reward_cue(int(data.id), false)
				if int(data.id) == state.main_hero: _battle_level_hero = int(data.id)
			var gained := "%d experience gained" % data.amount
			if data.levels > 0: gained += " · Reached level %d" % state.object(data.id).level
			_remark(gained)
		"loot":
			var rewards: Array[String] = []
			var artifacts: Array[String] = []
			for item: Dictionary in data.items:
				if item.kind == "spell": rewards.append(state.map.profile.text(str(state.map.profile.table("CombatSpells").get(item.card, {}).get("Name", item.card))))
				elif item.kind == "artifact": artifacts.append(ELMapPickups.artifact_title(state.map.profile, str(item.name)))
			var lines: Array[String] = []
			if not rewards.is_empty(): lines.append("Spells received: " + ", ".join(rewards))
			if not artifacts.is_empty(): lines.append("Artifacts received: " + ", ".join(artifacts))
			_remark(" · ".join(lines) if not lines.is_empty() else "No spells found.")
			_second_loot_box(data)

## Mission end: the original WinLose picture over everything (also over a
## running duel). Nothing is shown in text; the score goes to the campaign and
## the Hall of Fame. A map notice in front of it is answered first.
func _show_result() -> void:
	if ui == null or result_shown: return
	if building_message != null or _mission_fade != null or _reward_transition():
		result_waiting = true
		return
	result_shown = true
	if state.map.profile.id == "el2" and state.outcome == "win" and ELSecondCampaign.is_interlude(ELSecondCampaign.progress(state)):
		_second_chapter_end.call_deferred()
		return
	# The second game's win/lose screen silences the map theme (music mode 1);
	# the first game keeps it playing.
	if state.map.profile.id == "el2" and audio != null: audio.cut_music()
	win_lose_layer = CanvasLayer.new()
	win_lose_layer.layer = 19
	add_child(win_lose_layer)
	win_lose = ELWinLoseScreen.new()
	win_lose.name = "WinLose"
	win_lose_layer.add_child(win_lose)
	var local: Dictionary = state.players.get(state.current_player, {})
	win_lose.setup(state.map.profile, state.outcome == "win", str(local.get("color", "")))
	win_lose.closed.connect(_close_result, CONNECT_ONE_SHOT)
	win_lose.grab_focus()

## After the picture: the first game goes to
## the next chapter's (or the same chapter's) campaign info screen, the branch
## choice, or after the final the outtro movie and the campaign Hall of Fame;
## a single map goes to the scenario Hall of Fame (won) or the main menu. The
## second game ends the chapter (autosave, the next global map), or after the
## last campaign plays the outtro and shows the main menu and the credits; a
## lost chapter, a single map or the tutorial return to the menus.
func _close_result() -> void:
	if win_lose_layer != null:
		win_lose_layer.queue_free()
		win_lose_layer = null
		win_lose = null
	if state == null: return
	if state.map.profile.id == "el2" and not ELSecondCampaign.progress(state).is_empty():
		_second_chapter_end()
		return
	var result := ELFirstScenario.chapter_result(state) if state.map.profile.id == "el1" else {}
	if not result.is_empty() and not (bool(result.get("won", false)) and bool(result.get("final", false))):
		var next: Array = result.get("next", [])
		# The game's computer players' strength goes on with it (ELAIChoice).
		next = ELAIChoice.carry_rows(state, next)
		if next.size() == 2:
			chapter_requested.emit({"campaign": str(next[0].get("campaign", "")), "branch_choices": next})
			return
		if next.size() == 1:
			chapter_requested.emit(next[0])
			return
	_leave_after_result()

## The ending movie, then the Hall of Fame of a recorded win, then the menu.
func _leave_after_result() -> void:
	var ending := ending_movie()
	if not ending.is_empty() and not _ending_shown:
		_ending_shown = true
		if audio != null: audio.cut_music()
		play_movie(ending, _leave_after_result)
		return
	if not hall_record.is_empty() and open_extras("hall_of_fame", false, func(): leave_requested.emit(), hall_record):
		if audio != null: audio.cut_music()
		return
	# The second game's finished meta-campaign: the credits after the outtro
	# (opens CCreditsScreenA6).
	if result_kind == "finished" and open_extras("credits", false, func(): leave_requested.emit()):
		return
	leave_requested.emit()

## The movie that closing this outcome window plays, {} for none: the first
## game's won campaign final shows `outtro<n>.bik` for the colour of player 1
## (the final chapter's only player); the second game's finished meta-campaign
## shows `outtro.bik`.
func ending_movie() -> Dictionary:
	if state == null or state.outcome != "win": return {}
	var profile := state.map.profile
	if profile.id == "el1":
		var result := ELFirstScenario.chapter_result(state)
		if result.is_empty() or not bool(result.get("final", false)): return {}
		var owner: Dictionary = state.players.get(1, state.players.get(state.current_player, {}))
		return ELMoviePlayer.first_ending(profile, str(owner.get("color", "")))
	if result_kind == "finished":
		return ELMoviePlayer.item(profile, "Movies\\outtro.bik")
	return {}

## Plays one full-screen movie over the map, then runs `after`.
func play_movie(entry: Dictionary, after: Callable) -> void:
	if movie_layer == null:
		movie_layer = CanvasLayer.new()
		movie_layer.layer = 20
		add_child(movie_layer)
		movie = ELMoviePlayer.new()
		movie_layer.add_child(movie)
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	movie_layer.show()
	movie.finished.connect(func():
		movie_layer.hide()
		after.call(), CONNECT_ONE_SHOT)
	movie.play(entry)

## Shows one front-end screen over the map; `after` runs when it is left.
## `over_game` keeps the map visible around the panel (a dialog over the
## running game); otherwise the screen is opaque (the game has ended).
func open_extras(target: String, over_game: bool, after := Callable(), kind := "") -> bool:
	if not _extras_ready(): return false
	_after_extras = after
	dragging = false
	if hud != null: hud.show_tooltip(-1, {}, Vector2.ZERO)
	extras.open_hosted(target, over_game, kind)
	extras_layer.show()
	extras.show()
	return true

func _extras_ready() -> bool:
	if extras != null: return true
	var profile := state.map.profile
	if not ELFrontMenu.supports(profile): return false
	extras_layer = CanvasLayer.new()
	extras_layer.layer = 2
	add_child(extras_layer)
	extras = ELFrontMenu.new()
	extras_layer.add_child(extras)
	if not extras.build({profile.id: profile}, profile.id):
		extras_layer.queue_free()
		extras_layer = null
		extras = null
		return false
	extras.hosted_closed.connect(_close_extras)
	extras.slot_chosen.connect(func(row: Dictionary): slot_requested.emit(row))
	extras.console_captures = _quick_load_again
	return true

## The quick-load question takes a second F8 (or F9) as OK, as the
## original's T_MB_LOAD_GAME box does.
func _quick_load_again(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or extras == null or extras.duel_ui == null or not extras.duel_ui.message_open() or extras.duel_ui.message != _quick_load_box:
		return false
	if ELSettings.hotkey_action(settings, state.map.profile.id, "Map", key) != "map_load": return false
	var ok: BaseButton = extras.buttons.get("MBOK")
	if ok == null or not is_instance_valid(ok): return false
	_quick_load_box = null
	get_viewport().set_input_as_handled()
	ok.pressed.emit()
	return true

## The original Options screen over the map (EL1 Options column wrench, EL2
## Esc menu Options). Its Save / Load / Main menu / Quit run once it closed;
## the second game's Esc menu stays open beneath it.
func open_original_options() -> void:
	if not _extras_ready():
		notice.text = "The original Options art is unavailable."
		return
	extras.settings = settings
	extras.options_ui.adventure_load_allowed = _can_load_in_place()
	# First game: GOInfo opens the running mission's objectives.
	extras.mission_texts = ELFirstObjectivesScreen.mission_texts(state.map) if state != null and ELFirstObjectivesScreen.supports(state.map.profile) else {}
	if not extras.settings_previewed.is_connected(preview_volumes): extras.settings_previewed.connect(preview_volumes)
	var tutorial_was_enabled := bool(settings.values.get("show_tutorial", true))
	open_extras("options", true, _original_options_closed.bind(tutorial_was_enabled), "adventure")

func _original_options_closed(tutorial_was_enabled: bool) -> void:
	apply_settings()
	match extras.options_ui.last_command:
		"GOSave": open_save_screen()
		"GOLoad": open_load_screen()
		"GOMenu": leave_requested.emit()
		"GOQuit": ELAudio.quiet_quit(get_tree())
		_:
			if tutorial_panel != null and not tutorial_was_enabled and bool(settings.values.get("show_tutorial", true)):
				tutorial_panel.resume()

## Options changed: the map takes the new values at once.
func apply_settings() -> void:
	if settings == null: return
	_remake_key_hint()
	preview_volumes(settings.values)
	var weather := bool(settings.values.get("weather", true))
	var enhanced_water := bool(settings.values.get("enhanced_water", false))
	if effects != null:
		if effects.enabled != weather: effects.set_enabled(weather)
		effects.set_water_ripples(enhanced_water)
	if world != null: world.set_animate_objects(bool(settings.values.get("animated_objects", true)))
	if world != null: world.set_animate_fog(bool(settings.values.get("fog_animations", true)))
	ELEffectLook.use(settings.values)
	if world != null: ELEffectLook.sync(world.environment)
	if world != null: world.set_blob_shadows(bool(settings.values.get("shadows", true)))
	if world != null and world.terrain != null:
		world.terrain.set_detail(bool(settings.values.get("terrain_detail", false)))
		world.terrain.set_water(enhanced_water)
	if world != null and world.sun != null: world.sun.shadow_blur = 2.5 if settings.values.get("soft_shadows", false) else 1.5
	if presentation != null: presentation.apply(settings.values)
	_apply_helper_overlay()

## Remake readouts of map events and refused orders. The original shows these
## in its message boxes, by the cancel cursor or not at all, so the status line
## repeats them only with the helper overlay; `remark` keeps the last one.
func _remark(text: String) -> void:
	remark = text
	# Without the original HUD art the status line is the only readout.
	if notice != null and _observer_battle_note.is_empty() and (strategic_session != null or helper_overlay() or (hud == null and second_hud == null)): notice.text = text

## Second game: the scripted loot report (ExSendLootMessage /
## ExSendNoLootMessage) in the message box: T_MB_RECEIVE_LOOT over one line
## per spell and artifact, or T_MB_RECEIVE_NO_LOOT. The original shows the
## items as pictures with names.
func _second_loot_box(data: Dictionary) -> void:
	if state.map.profile.id != "el2" or second_hud == null: return
	var profile := state.map.profile
	var items: Array = data.get("items", [])
	var key := "T_MB_RECEIVE_NO_LOOT" if data.get("none", false) else "T_MB_RECEIVE_LOOT"
	var lines: Array[String] = [profile.text(key).strip_edges()]
	for item: Variant in items:
		if not item is Dictionary: continue
		if item.get("kind") == "spell": lines.append(profile.text(str(profile.table("CombatSpells").get(str(item.get("card", "")), {}).get("Name", item.get("card", "")))))
		elif item.get("kind") == "artifact": lines.append(ELMapPickups.artifact_title(profile, str(item.get("name", ""))))
	var message := {"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": "\n".join(PackedStringArray(lines)), "resources": [], "skill": "", "key": key, "battle_reward": true}
	# Received loot uses the Messages panel: the title, then a picture and a name per item.
	if not data.get("none", false):
		message.text = lines[0]
		message.loot = items.duplicate(true)
		if not items.is_empty(): _queue_reward_cue(-1 if _finishing_battle else state.main_hero, true)
	# Battle scripts can report their loot before the director has reported
	# the XP. Collect it until both can be presented together on the map.
	if _finishing_battle: _encounter_loot.append(message)
	else: _queue_building_message.call_deferred(message)

func _queue_building_message(message: Dictionary) -> void:
	if ui == null: return
	if _finishing_battle: message = message.merged({"battle_reward": true}, true)
	building_messages.append(message)
	if _hold_for_change_effect(message): return
	_show_building_message()

func _on_encounter_finishing() -> void:
	_finishing_battle = true

func _on_encounter_finished(winner: int) -> void:
	_finishing_battle = false
	building_messages.append_array(_encounter_loot)
	_encounter_loot.clear()
	var victor := state.object(winner)
	for cue: Dictionary in _reward_cues:
		if int(cue.hero) < 0: cue.hero = winner if int(victor.get("owner", -1)) == state.current_player else state.main_hero
	if visible: _show_waiting_map_dialogs()

func _queue_reward_cue(hero: int, loot: bool) -> void:
	var cue := {"hero": hero, "loot": loot}
	if not _reward_cues.has(cue): _reward_cues.append(cue)

func _reward_transition() -> bool:
	return _finishing_battle or not _reward_cues.is_empty() or _reward_wait > 0.0

func _reward_dialog_open() -> bool:
	return (building_message != null and building_message.data.get("battle_reward", false)) \
		or (skills != null and skills.hero_id == _battle_level_hero)

func _step_reward_transition(delta: float) -> bool:
	_reward_wait = maxf(0.0, _reward_wait - delta)
	if _reward_wait > 0.0: return true
	if effects != null: effects.finish(REWARD_EFFECT)
	if audio != null: audio.cancel_sound(REWARD_EFFECT)
	while not _reward_cues.is_empty() and _reward_wait == 0.0: _play_reward_cue(_reward_cues.pop_front())
	return _reward_wait > 0.0

func _play_reward_cue(cue: Dictionary) -> void:
	var hero := state.object(cue.hero)
	if hero.is_empty() or not hero.get("alive", false): return
	var at := _hero_effect_position(hero)
	if not state.camera_locked and not camera.is_position_in_frustum(world.to_global(at)): _scroll_to(at, true)
	var loot := bool(cue.loot)
	var entry := {"file": LOOT_EFFECT if loot else LEVEL_EFFECT, "x": at.x, "y": -at.z, "z": at.y, "loops": 0}
	if effects != null: effects.start(REWARD_EFFECT, entry, 0.0, true)
	if audio != null:
		audio.listener = target
		audio.start_sound(REWARD_EFFECT, entry.merged({"file": "Magic/GlobalCast.wav" if loot else "Adventure/stars1.wav",
			"near": 1.0, "far": 8.0 if loot else 32.0, "effects": true}, true))
	_reward_wait = REWARD_CUE_TICKS * director.script_tick()

## Remake setting "helper_overlay" (default off).
func helper_overlay() -> bool:
	return settings != null and bool(settings.values.get("helper_overlay", false))

func _apply_helper_overlay() -> void:
	var shown := helper_overlay()
	for part: Control in helper_parts:
		if is_instance_valid(part): part.visible = shown
	if notice != null and (notice.text.is_empty() or notice.text == helper_hint):
		notice.text = helper_hint if shown or (hud == null and second_hud == null) else ""

## An original text, or the remake fallback when the key has no text.
func _text_or(key: String, fallback: String) -> String:
	var value := state.map.profile.text(key)
	return fallback if value.is_empty() or value == key else value

func _build_presentation() -> void:
	presentation = ELFirstMapPresentation.new()
	# Second game: the building idle particles (BuildingsPFX) go to the map's
	# own effects; the first game's presentation makes its own.
	if state.map.profile.id == "el2": presentation.effects = effects
	world.add_child(presentation)
	presentation.listener = target
	presentation.build(state.map.profile, settings, state, world, camera)

func preview_volumes(values: Dictionary) -> void:
	if presentation != null: presentation.apply(values)
	if audio != null: audio.apply_volumes(values)

func extras_open() -> bool:
	return extras != null and extras.is_visible_in_tree()

func _close_extras() -> void:
	extras.hide()
	extras_layer.hide()
	var after := _after_extras
	_after_extras = Callable()
	if after.is_valid(): after.call()

## Second-game chapter end: a won chapter records the carried
## block and the next row, the progress is autosaved, and the next chapter's
## global map follows; after the last campaign the outtro, then the menu and
## the credits. A lost chapter returns to the main menu; the saved
## progress still starts that chapter.
func _second_chapter_end() -> void:
	var progress := ELSecondCampaign.progress(state).duplicate(true)
	# The game's computer players' strength goes on with it (ELAIChoice).
	ELAIChoice.carry_progress(state, progress)
	var profile := state.map.profile
	result_kind = "lost"
	if state.outcome == "win":
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, str(progress.get("current", ""))):
			error = campaign.error
			leave_requested.emit()
			return
		progress = ELSecondCampaign.normalized(progress)
		var campaign_id := str(progress.current)
		progress.hall_points += ELHallOfFame.WIN_POINTS * (int(progress.difficulty) + 1)
		result_kind = ELSecondCampaign.complete_chapter(progress, ELSecondCampaign.capture(state), campaign.scenarios.size())
		if result_kind in ["campaign", "finished"]:
			ELHallOfFame.record_second_campaign(state, campaign_id, int(progress.hall_points), str(progress.hall_run))
			progress.hall_points = 0
		if result_kind != "finished" and not ELSecondCampaign.write(ELSecondCampaign.AUTOSAVE, progress):
			push_warning("The campaign progress could not be autosaved.")
	result_progress = progress
	if result_kind in ["lost", "finished"] or ELSecondCampaign.chapter(profile, progress).is_empty():
		_leave_after_result()
		return
	campaign_map_requested.emit(progress)

func _focus_object(id: int, instant := false) -> void:
	var item := state.object(id)
	if item.is_empty(): return
	_scroll_to(ELAdventureScene.world_position(item.x, item.y), instant)

func _speaker_in_place() -> bool:
	var destination := camera_goal()
	if following >= 0 and world.actors.has(following): destination = world.actors[following].position
	return target.distance_squared_to(destination) <= 0.25 * 0.25

func _show_second_dialogue(speech: Dictionary) -> void:
	second_dialogue.present(speech, state)
	accept = second_dialogue.accept
	decline = second_dialogue.decline
	_place_dialogue(speech)
	if not speech.get("direct", false): world.speak_actor(int(speech.get("actor", -1)))
	audio.speak(speech.text_id)

func _fade_in_mission() -> void:
	var curtain := ColorRect.new()
	_mission_fade = curtain
	curtain.name = "MissionFade"
	curtain.color = Color.BLACK
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.z_index = 1
	ui.add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade := curtain.create_tween()
	fade.tween_property(curtain, "color:a", 0.0, MISSION_FADE_SECONDS)
	fade.tween_callback(func() -> void:
		curtain.hide()
		curtain.queue_free()
		_mission_fade = null)

## Second game: the camera's look-at point flies to a new point. Every 64 ms
## it covers SCROLL_RATE x AutoScrollAcceleration (settings.ini, shipped 0.5)
## of the way left, and it stops when that step is shorter than 0.001; the
## "Instant" script commands jump. The first game's views jump.
const SCROLL_TICK := 0.064
const SCROLL_RATE := 0.25
const SCROLL_STOP := 0.001
var scroll_goal := Vector3.ZERO
var scroll_gliding := false
var scroll_rate := SCROLL_RATE * 0.5

func _scroll_to(point: Vector3, instant := false) -> void:
	following = -1
	scroll_gliding = false
	if instant or state == null or state.map.profile.id != "el2":
		target = point
		# A jump can happen while the map's camera update is paused.
		if state != null: _update_camera()
	else:
		scroll_goal = point
		scroll_gliding = true

## Where the camera is going (its look-at point once a flight ends).
func camera_goal() -> Vector3:
	return scroll_goal if scroll_gliding else target

func _glide(delta: float) -> void:
	var rest := scroll_goal - target
	if rest.length() * scroll_rate < SCROLL_STOP:
		target = scroll_goal
		scroll_gliding = false
		return
	target += rest * (1.0 - pow(1.0 - scroll_rate, delta / SCROLL_TICK))

## AutoScrollAcceleration from the game's settings.ini ([Camera Settings]);
## the shipped 0.5 when it is missing, and the original ignores values <= 0.
static func scroll_acceleration(source: ELProfile) -> float:
	var path := source.file("settings.ini") if source != null else ""
	if path.is_empty() or not FileAccess.file_exists(path): return 0.5
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("AutoScrollAcceleration="): continue
		var value := line.get_slice("=", 1).strip_edges()
		return value.to_float() if value.is_valid_float() and value.to_float() > 0.0 else 1.0
	return 0.5

## Guard zones end a drawn route in the first game, and for player 1's heroes
## in the second (route preview).
func _zones_stop(actor: Dictionary) -> bool:
	return state.map.profile.id == "el1" or state.map.profile.id == "el2" and int(actor.get("owner", -1)) == 1

## First-game route marker colours, by the owner's map colour (Path00..03).
const ROUTE_COLOURS := ["Black", "Red", "Blue", "Green"]

func _draw_route(path: Array, actor_id := -1) -> void:
	if route == null: return
	# Second game: a move order shows no route. Its marker figures
	# (telapa1/telapa2) name TerrainObjects Path/Finish textures that the
	# game's data does not contain, so nothing is drawn while the hero walks;
	# a line here only lay under the walking figure (and stopped short of
	# guard zones the hero then walked through).
	if state.map.profile.id == "el2":
		route.mesh = null
		return
	route.mesh = null
	for mark: Node in route.get_children():
		route.remove_child(mark)
		mark.queue_free()
	var actor := state.object(_hero_id() if actor_id < 0 else actor_id)
	_route_owner = int(actor.get("owner", state.current_player))
	_route_fog_revision = -1
	if _zones_stop(actor): path = director.interception.preview(state, actor, path)
	if path.size() < 2: return
	# First game: the original marks the route with figures, not lines: a
	# telapa1 square on each step and telapa2 (square and four arrows) at the
	# end, in the owner's colour (TerrainObjects Path0N / Finish0N) while the
	# day's movement points last, NoPath / NoFinish beyond.
	var colour := ROUTE_COLOURS.find(str(state.players.get(_route_owner, {}).get("color", "")))
	var remaining := int(actor.get("ap", 0))
	for index in range(1, path.size()):
		remaining -= ELFirstNaval.step_cost(director.grid, path[index - 1], path[index], false) if ELFirstNaval.enabled(state.map) else director.grid.passability(path[index])
		var within := not (director.strategy.is_empty() and remaining < 0) and colour >= 0
		var last := index == path.size() - 1
		var texture := ("Finish%02d" if last else "Path%02d") % colour if within else ("NoFinish" if last else "NoPath")
		var mark := ELModel.new()
		route.add_child(mark)
		if not mark.build(state.map.profile, "telapa2" if last else "telapa1", "TerrainObjects/" + texture):
			mark.queue_free()
			continue
		if mark.has_clip("uidle"): mark.play("uidle")
		var cell: Vector2i = path[index]
		mark.set_meta("route_cell", cell)
		mark.position = ELAdventureScene.world_position(cell.x, cell.y) + Vector3(0, 0.02, 0)
		for part: MeshInstance3D in mark.parts.values(): part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_route_fog()

func _sync_route_fog() -> void:
	if route == null or _route_owner == state.current_player or _route_fog_revision == ELFog.revision(state): return
	_route_fog_revision = ELFog.revision(state)
	for mark: ELModel in route.get_children():
		if mark.has_meta("route_cell"): mark.visible = ELFog.visible(state, state.current_player, mark.get_meta("route_cell"))

func _stop_following_hidden_hero() -> void:
	if state.map.profile.id != "el1" or following < 0 or director.strategy.is_empty(): return
	var actor := state.object(following)
	if int(actor.get("owner", state.current_player)) != state.current_player and not ELFog.shown(state, state.current_player, actor):
		following = -1

## `scripted` is ExShowInventory: the script opens the main hero's inventory
## whatever the player is doing.
func _open_spellbook(scripted_hero := -1) -> void:
	if strategic_session != null and not strategic_session.can_plan(): return
	if spellbook != null or paused: return
	if scripted_hero < 0 and (not director.can_move() or not director.movement.is_empty()):
		_remark("Finish the current action before opening the spellbook.")
		return
	var shown := scripted_hero if scripted_hero >= 0 else _hero_id()
	var hero := state.object(shown)
	if hero.is_empty() or not hero.alive: return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.8)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Second game: the original InventoryScreen (ELSecondInventoryView).
	# First game: the book and reserve on the original laboratory panel.
	if hud != null and state.map.profile.id == "el1":
		scrim.color = Color(0, 0, 0, 0.55)
		hud.show_tooltip(-1, {}, Vector2.ZERO)
		var first := ELFirstBookView.new()
		first.strategic_session = strategic_session
		scrim.add_child(first)
		first.build_book(director, hud, shown)
		first.closed.connect(_close_spellbook)
		spellbook = first
		return
	var plain: ELSpellbookView = ELSecondInventoryView.make(second_hud) if second_hud != null else ELSpellbookView.new()
	spellbook = plain
	plain_spellbook = plain
	plain.strategic_session = strategic_session
	scrim.add_child(plain)
	plain.build(state, shown)
	plain.closed.connect(_close_spellbook)
	if spellbook is ELSecondInventoryView:
		inventory_blinks = BlinkFrames.new()
		inventory_blinks.state = state
		var screen: ELSecondInventoryView = spellbook
		screen.hotkey_settings = settings
		inventory_blinks.origin = func() -> Vector2: return screen._offset
		screen.canvas.add_child(inventory_blinks)
	# Second game: Hook_OnDialogOpen("Inventory") once the bag opens from the
	# panel button or I; its result is ignored.
	if scripted_hero < 0 and state.map.profile.id == "el2" and not state.hook("Hook_OnDialogOpen", ["Inventory"]): notice.text = state.error

## Script boxes stay above every window. Over a modal window (inventory, shop,
## notebook) the box is modal and centred on the screen, moved by the
## ExMessageBoxStandard (dx, dy) offset.
func _place_dialogue(speech: Dictionary) -> void:
	var over_window := paused
	dialogue_blocker.visible = over_window
	if over_window:
		dialogue_blocker.move_to_front()
		if spellbook != null: spellbook.set_process_unhandled_key_input(false)
	dialogue_panel.move_to_front()
	# Second game: the original boxes place themselves (TextDialog lower-middle,
	# MessageBox centred and moved by the script's offset).
	if second_dialogue != null:
		second_dialogue.layout()
		return
	if not over_window: return
	# A box without a speaker drops the empty portrait column over a window.
	dialogue_portrait.visible = dialogue_portrait.texture != null
	# Like the original standard box, the centred box fits its whole text.
	dialogue_text.fit_content = true
	var factor := ui.size.y / 768.0
	var shift: Array = speech.get("offset", [0.0, 0.0])
	var half := Vector2(minf(ui.size.x - 32.0, 640.0 * factor), maxf(225.0, dialogue_panel.get_combined_minimum_size().y)) * 0.5
	var centre := Vector2(float(shift[0]), float(shift[1])) * factor
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER)
	# A longer text grows the box about its centre.
	dialogue_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialogue_panel.offset_left = centre.x - half.x
	dialogue_panel.offset_right = centre.x + half.x
	dialogue_panel.offset_top = centre.y - half.y
	dialogue_panel.offset_bottom = centre.y + half.y

## Back to the dialogue strip above the panels.
func _dock_dialogue() -> void:
	if dialogue_blocker != null: dialogue_blocker.hide()
	if spellbook != null: spellbook.set_process_unhandled_key_input(true)
	if second_dialogue != null: return
	dialogue_portrait.visible = true
	dialogue_text.fit_content = false
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.grow_horizontal = Control.GROW_DIRECTION_END
	dialogue_panel.grow_vertical = Control.GROW_DIRECTION_END
	dialogue_panel.offset_left = 24
	dialogue_panel.offset_right = -24
	dialogue_panel.offset_top = -245
	dialogue_panel.offset_bottom = -20
	if second_hud != null: _fit_second_layout()
	elif hud != null: _fit_first_layout()

func _close_spellbook() -> void:
	if spellbook == null: return
	inventory_blinks = null
	spellbook.get_parent().queue_free()
	spellbook = null
	plain_spellbook = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## Second game: the level-up dialog opens by itself for the local player's
## main hero once the map is idle and a skill choice waits (queues the
## level-up action, whose run shows it with victory.wav).
func _auto_level_up() -> void:
	if second_hud == null or skills != null or paused or _reward_transition() or state.map.profile.id != "el2": return
	if not director.can_move() or not director.movement.is_empty() or not pending_encounter.is_empty() or not building_messages.is_empty(): return
	var hero := state.object(state.main_hero)
	if hero.is_empty() or not hero.get("alive", false) or int(hero.get("owner", -1)) != state.current_player or int(hero.get("skill_points", 0)) <= 0: return
	if ELHeroSkills.prepare(state.map.profile, hero).is_empty(): return
	_open_skills(state.main_hero)
	if skills != null and audio != null: audio.effect_sound("Adventure/victory.wav")

## First game: a level gained by one of the player's heroes (in a battle, a
## building or a script). The original only shows the tutorial's LEVEL_UP
## hint and leaves the choice to the HeroScreen; the remake also opens that
## screen, with its level-up offers, once the map is idle.
func _note_first_level_up(data: Dictionary) -> void:
	if state.map.profile.id != "el1" or hud == null or int(data.get("levels", 0)) <= 0: return
	var id := int(data.get("id", -1))
	var owner := int(state.object(id).get("owner", -1))
	if owner < 0 or not director.is_strategy_human(owner) or first_level_ups.has(id): return
	first_level_ups.append(id)

## Opens the HeroScreen for the next hero waiting with a skill to choose,
## after the battle result, messages and tutorial hints over the map. Once
## per level gained: closing it without a choice keeps the offers for the
## HeroScreen, as in the original.
func _first_level_up() -> void:
	if first_level_ups.is_empty() or hud == null or not _can_act() or _cursor_modal() or not pending_encounter.is_empty() or not building_messages.is_empty(): return
	if tutorial_panel != null and tutorial_panel.visible: return
	var id: int = first_level_ups.pop_front()
	var hero := state.object(id)
	if hero.is_empty() or not hero.get("alive", false) or int(hero.get("owner", -1)) != state.current_player: return
	var offers: Array = hero.get("skill_offers", [])
	if int(hero.get("skill_points", 0)) <= 0 or offers.is_empty(): return
	open_hero_screen(id)

func _open_skills(for_hero := -1) -> void:
	if strategic_session != null and not strategic_session.can_plan(): return
	if skills != null or paused: return
	if not director.can_move() or not director.movement.is_empty():
		_remark("Finish the current action before opening skills.")
		return
	var shown := for_hero if for_hero >= 0 else _hero_id()
	var hero := state.object(shown)
	if hero.is_empty() or not hero.alive: return
	ELHeroSkills.prepare(state.map.profile, hero)
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.8)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	if second_hud != null:
		# The second game's level-up dialog sits over the map without a shade.
		scrim.color = Color(0, 0, 0, 0)
		var dialog := ELSecondLevelUpView.new()
		dialog.hud = second_hud
		skills = dialog
	else:
		skills = ELHeroSkillsView.new()
	skills.strategic_session = strategic_session
	scrim.add_child(skills)
	skills.build(state, shown)
	skills.closed.connect(_close_skills)

## First-game global spells screen; `prompt` opens the finished spell's prompt.
func open_global_spells(prompt := false) -> void:
	if strategic_session != null and not strategic_session.can_plan(): return
	if global_spells != null:
		if prompt: global_spells.open_prompt()
		return
	if paused or hud == null or not ELGlobalSpells.applies(state) or not state.players.has(state.current_player): return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	global_spells = ELGlobalSpellsView.new()
	global_spells.hud = hud
	global_spells.strategic_session = strategic_session
	scrim.add_child(global_spells)
	global_spells.build(state, state.current_player)
	global_spells.closed.connect(_close_global_spells)
	global_spells.hero_requested.connect(_hero_over_global_spells)
	_refresh_hero_info()
	if prompt: global_spells.open_prompt()

## First-game Diplomacy screen (DiplomacyMode).
func open_diplomacy() -> void:
	if strategic_session != null and not strategic_session.can_plan(): return
	if diplomacy != null or paused or hud == null or not ELDiplomacy.applies(state) or not state.players.has(state.current_player): return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	diplomacy = ELDiplomacyView.new()
	diplomacy.hud = hud
	diplomacy.strategic_session = strategic_session
	scrim.add_child(diplomacy)
	diplomacy.build(state, state.current_player)
	diplomacy.closed.connect(_close_diplomacy)
	_refresh_hero_info()
	tutorial_event("OPEN_DIPLOMACY_SCREEN")

func _close_diplomacy() -> void:
	if diplomacy == null: return
	diplomacy.get_parent().queue_free()
	diplomacy = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

func _close_global_spells() -> void:
	if global_spells == null: return
	global_spells.get_parent().queue_free()
	global_spells = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	mana_readout = {}
	_refresh_hero_info()
	if global_spell_waiting: _offer_global_spell()

func _timed_turn_ended() -> void:
	global_spell_waiting = false
	_close_global_spells()
	_close_diplomacy()
	_close_first_shop()
	_close_rune_shop()
	_close_hero_screen()
	_close_building_screen()
	_close_skills()
	_close_spellbook()
	if extras_open():
		_after_extras = Callable()
		_close_extras()
	_refresh_hero_info()

func _show_takeover_notice(text: String) -> void:
	var ready: bool = ELGlobalSpells.data(state, state.current_player).get("production", {}).get("state") == 2
	if first_shop == null and rune_shop == null: _timed_turn_ended()
	global_spell_waiting = ready
	_queue_building_message({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": text, "resources": [], "skill": "", "key": "", "box": "first"})

## A click on a spell in the adventure panel's list orders it without extra
## ether; a spell finished at once asks for its targets.
func _order_global_spell(code: String) -> void:
	if paused or not _can_act(): return
	if strategic_session != null:
		strategic_session.manage_hero(["global_produce", code, 0], _remark)
		return
	ELGlobalSpells.produce(state, state.current_player, code)

## A finished spell asks to be applied once the map is free of other windows.
func _offer_global_spell() -> void:
	global_spell_waiting = true
	if global_spells != null:
		global_spell_waiting = false
		global_spells.refresh()
		global_spells.open_prompt()
		return
	if paused or building_message != null or not director.strategy.is_empty() or (strategic_session != null and not strategic_session.can_plan()): return
	global_spell_waiting = false
	open_global_spells(true)

func _close_skills() -> void:
	if skills == null: return
	if skills.hero_id == _battle_level_hero:
		_battle_level_hero = -1
		_reward_wait = REWARD_DIALOG_GAP
	skills.get_parent().hide()
	skills.get_parent().queue_free()
	skills = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## A building message pauses the night like the original message box; queued
## messages from the same night follow one another.
func _show_building_message() -> void:
	if building_message != null or skills != null or first_shop != null or rune_shop != null or building_messages.is_empty() or ui == null or _message_holds > 0: return
	if _mission_fade != null or _reward_transition() or (second_hud != null and not visible): return
	# A message queued behind the map's commands waits until they have run.
	if building_messages[0].get("wait_idle", false) and not director._map_idle(): return
	paused = true
	dragging = false
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	building_message = ELBuildingMessageView.new()
	scrim.add_child(building_message)
	var message: Dictionary = building_messages.pop_front()
	if strategic_session != null and message.get("site_notice", false) and message.building >= 0:
		_focus_object(int(message.hero))
		_update_camera()
	if hud != null and state.map.profile.id == "el1" and ELBuildingMessageView.first_applies(message):
		# The original MessageBox does not darken the map.
		scrim.color = Color(0, 0, 0, 0)
		building_message.build_first(state, hud, message)
	elif second_hud != null and ELBuildingMessageView.second_applies(message):
		# The original MessageBox does not darken the map.
		scrim.color = Color(0, 0, 0, 0)
		building_message.build_second(state, second_hud, message)
	else:
		building_message.build(state, hud, message)
		building_message.accept.grab_focus()
	building_message.closed.connect(_close_building_message)

## First game: the local player's resource pile in the original MessageBox
## (T_MB_TAKE_PLUHA_1 over one icon and amount per resource).
func _first_pickup_box(data: Dictionary) -> void:
	if state.map.profile.id != "el1" or hud == null or int(data.get("player", -1)) != state.current_player: return
	var rows: Array = []
	for kind: String in ELResources.ORIGINAL:
		if int(data.amounts.get(kind, 0)) > 0: rows.append([kind, int(data.amounts[kind])])
	if rows.is_empty(): return
	building_messages.append({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": state.map.profile.text("T_MB_TAKE_PLUHA_1"), "resources": [], "skill": "", "key": "T_MB_TAKE_PLUHA_1", "box": "first", "rows": rows, "site_notice": true})
	_show_building_message()

## Second game: a resource pile taken by a hero of the local (human) player
## adds T_TAKE_PLUHA with the amount and the resource icon to the message line
## at the top left; there is no message box.
func _second_pickup_line(data: Dictionary) -> void:
	if state.map.profile.id != "el2" or second_hud == null or world == null or int(data.get("player", -1)) != world.fog_player: return
	var format := state.map.profile.text("T_TAKE_PLUHA").strip_edges()
	if format == "T_TAKE_PLUHA" or not format.contains("%d"): format = "Collected: %d"
	for kind: String in ELResources.SEQUEL:
		var amount := int(data.amounts.get(kind, 0))
		if amount > 0: second_hud.add_message(format.replace("%d", str(amount)), kind)

## First game: a mine, ether node or shop taken by or from the local player,
## in the original MessageBox with the object's picture. Mines and nodes add
## the income per turn with its resource icon; a lost node shows nothing.
func _first_capture_box(data: Dictionary) -> void:
	if state.map.profile.id != "el1" or hud == null: return
	var local := state.current_player
	var item := state.object(int(data.get("id", -1)))
	var taken := int(data.get("player", -1)) == local and int(data.get("previous", -1)) != local
	var lost := int(data.get("previous", -1)) == local and int(data.get("player", -1)) != local
	if item.is_empty() or not (taken or lost): return
	var profile := state.map.profile
	var message := {"kind": "building_message", "hero": -1, "building": -1, "title": "", "resources": [], "skill": "", "box": "first", "picture": ["object", int(item.uid)]}
	if ELResourceSites.TYPES.has(item.get("group")):
		if lost and item.group == "mana_nodes": return
		var kind := "Ether"
		var amount := ELResourceSites.mana_production(item, str(state.players.get(local, {}).get("color", "")))
		if item.group == "mines":
			var production := ELResourceSites.production(profile, item)
			for resource: String in ELResources.ORIGINAL:
				if int(production.get(resource, 0)) > 0:
					kind = resource
					amount = int(production[resource])
					break
		message.key = "T_MB_TAKE_MINE" if taken else "T_MB_LOSE_MINE"
		message.text = _fill(profile.text(message.key), [ELResourceSites.title(profile, item), amount])
		message.inline = kind
	else:
		message.key = "T_MB_TAKE_SHOP" if taken else "T_MB_LOSE_SHOP"
		message.text = _fill(profile.text(message.key), [str(item.get("title", profile.text(str(_art.resolve(item).get("row", {}).get("ELKName", item.name)))))])
	message.site_notice = true
	building_messages.append(message)
	_show_building_message()

## Second game: a mine taken by the local player shows T_MB_TAKE_MINE (name,
## income per payment, income of the ten payments); one taken from the local
## player shows T_MB_LOSE_MINE. The box carries the text only: the resource
## icon markers are dropped and the mine picture is not drawn.
func _second_capture_box(data: Dictionary) -> void:
	if state == null or state.map.profile.id != "el2" or second_hud == null: return
	var local := state.current_player
	var item := state.object(int(data.get("id", -1)))
	var taken := int(data.get("player", -1)) == local and int(data.get("previous", -1)) != local
	var lost := int(data.get("previous", -1)) == local and int(data.get("player", -1)) != local
	if item.is_empty() or item.get("group") != "mines" or not (taken or lost): return
	var profile := state.map.profile
	var amount := 0
	var production := ELResourceSites.production(profile, item)
	for resource: String in ELResources.types(profile.id):
		if int(production.get(resource, 0)) > 0:
			amount = int(production[resource])
			break
	var key := "T_MB_TAKE_MINE" if taken else "T_MB_LOSE_MINE"
	var text := _fill(profile.text(key), [ELResourceSites.title(profile, item), amount, amount * 10])
	for marker: String in ["@1", "@2"]: text = text.replace(" " + marker, "").replace(marker, "")
	text = text.strip_edges()
	building_messages.append({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": text, "resources": [], "skill": "", "key": key})
	_show_building_message()

## Replaces the text's %s and %d markers in order.
static func _fill(text: String, values: Array) -> String:
	for value: Variant in values:
		var at := -1
		for marker: String in ["%s", "%d"]:
			var found := text.find(marker)
			if found >= 0 and (at < 0 or found < at): at = found
		if at < 0: break
		text = text.substr(0, at) + str(value) + text.substr(at + 2)
	return text

func _close_building_message() -> void:
	if building_message == null: return
	if building_message.data.get("battle_reward", false): _reward_wait = REWARD_DIALOG_GAP
	building_message.get_parent().hide()
	building_message.get_parent().queue_free()
	building_message = null
	paused = false
	_refresh_hero_info()
	_show_waiting_map_dialogs()

func _show_waiting_map_dialogs() -> void:
	if _mission_fade != null or _reward_transition(): return
	_show_building_message()
	if building_message == null and not deferred_shop.is_empty():
		var shop_waiting := deferred_shop
		deferred_shop = {}
		_present(shop_waiting)
	if building_message == null and result_waiting:
		result_waiting = false
		_show_result()
	if building_message == null and not deferred_encounter.is_empty():
		var waiting := deferred_encounter
		deferred_encounter = {}
		_present(waiting)

## First-game hero screens. Ctrl+click on another own hero opens the exchange
## a double-click on the selected hero opens its HeroScreen. Other
## Ctrl+clicks keep only the building click; returns true when consumed.
## First game: the own hero under a right click drops its planned order.
func _cancel_order_at(at: Vector2) -> void:
	if paused or not hud.map_rect().has_point(at): return
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	if hit == null: return
	var tile := Vector2i(floori(hit.x / 2.0), floori(-hit.z / 2.0))
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.alive and item.visible and item.get("placed", true) and not item.get("fortified", false) and int(item.owner) == state.current_player and Vector2i(item.x, item.y) == tile and not item.get("strategy_order", {}).is_empty():
			_cancel_map_order(int(item.uid))
			_refresh_hero_info()
			return

func _hero_click(tile: Vector2i, exchange: bool) -> bool:
	if strategic_session != null and not strategic_session.can_plan(): return false
	var clicked := -1
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.alive and item.visible and item.get("placed", true) and not item.get("fortified", false) and Vector2i(item.x, item.y) == tile and not _fogged(item): clicked = int(item.uid)
	if not exchange:
		if clicked < 0 or clicked != _hero_id(): return false
		open_hero_screen(clicked)
		return true
	if clicked < 0 or int(state.object(clicked).owner) != state.current_player:
		# Only an own building answers a Ctrl+click besides a hero.
		var site := -1
		for id: int in state.objects:
			var item: Dictionary = state.objects[id]
			var size: Vector2i = director.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
			if item.alive and item.get("type") != "hero" and int(item.get("owner", -1)) == state.current_player and Rect2i(item.x, item.y, size.x, size.y).has_point(tile): site = id
		if site >= 0: _click_ground(tile)
		return true
	if clicked == _hero_id(): return true
	var problem := ELHeroExchange.exchange_problem(director, _hero_id(), clicked)
	if not problem.is_empty():
		_remark(problem)
		return true
	_open_hero_view([_hero_id(), clicked], true)
	return true

## First game: a double-click on the player's own castle opens the castle's
## GlobalSpells screen, like its hotkey (the map's double-click handler opens
## the castle as well as the selected hero). The click before it only drew
## the "own castle" notice, which is cleared. Returns true when consumed.
func castle_double_click(at: Vector2, hit: Vector3) -> bool:
	if not ELGlobalSpells.applies(state) or _cursor_modal(): return false
	var item := state.object(_object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL, at))
	if not ELFirstScenario.is_castle(item) or not item.get("alive", false) or int(item.get("owner", -1)) != state.current_player or _fogged(item): return false
	_remark("")
	open_global_spells()
	return global_spells != null

## #169: a hero's screen over the GlobalSpells prompt (a right click on its
## portrait); closing it goes back to the prompt.
func _hero_over_global_spells(id: int) -> void:
	var hero := state.object(id)
	if global_spells == null or hero.is_empty() or not hero.get("alive", false) or int(hero.get("owner", -1)) != state.current_player: return
	_open_hero_view([id], false, true)

func open_hero_screen(id: int) -> void:
	if strategic_session != null and not strategic_session.can_plan(): return
	var hero := state.object(id)
	if hero.is_empty() or not hero.alive or int(hero.owner) != state.current_player: return
	if id != _hero_id(): _select_hero(id)
	_open_hero_view([id], false)

func _open_hero_view(ids: Array[int], exchange: bool, over_global_spells := false) -> void:
	if hero_screen != null or (paused and not over_global_spells) or hud == null: return
	paused = true
	dragging = false
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	hero_screen = ELHeroScreenView.new()
	hero_screen.strategic_session = strategic_session
	scrim.add_child(hero_screen)
	hero_screen.build(director, hud, ids, exchange)
	hero_screen.closed.connect(_close_hero_screen)
	hero_screen.dismissed.connect(func(_id: int):
		_close_hero_screen()
		selected_hero = -1
		_refresh_roster())

## BuildingScreen for one of the player's buildings (from the buildings list).
func open_building_screen(id: int) -> void:
	if building_screen != null or paused or hud == null: return
	var item := state.object(id)
	if item.is_empty() or not item.get("alive", false) or int(item.get("owner", -1)) != state.current_player: return
	if strategic_session != null and (not strategic_session.can_plan() or item.type not in ELBuildingScreen.STRATEGIC_UPGRADES): return
	_focus_object(id)
	paused = true
	dragging = false
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	building_screen = ELBuildingScreenView.new()
	building_screen.strategic_session = strategic_session
	scrim.add_child(building_screen)
	building_screen.build(director, hud, id)
	building_screen.closed.connect(_close_building_screen)
	building_screen.upgraded.connect(func(_id: int): _refresh_hero_info())
	tutorial_event("OPEN_BUILDING_SCREEN")

func _close_building_screen() -> void:
	if building_screen == null: return
	building_screen.get_parent().queue_free()
	building_screen = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

func _close_hero_screen() -> void:
	if hero_screen == null: return
	hero_screen.get_parent().queue_free()
	hero_screen = null
	mana_readout = {}
	# Opened over the GlobalSpells prompt: back to it, the map still held.
	if global_spells != null:
		global_spells.reopen_prompt()
		_refresh_hero_info()
		return
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

func _open_shop() -> void:
	if shop != null or director.shop == null: return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.8)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	# The original screen dims the map itself.
	scrim.color = Color(0, 0, 0, 0)
	shop = ELSpellShopView.new()
	shop.hud = second_hud
	shop.hotkey_settings = settings
	scrim.add_child(shop)
	shop.build(director.shop)
	shop.closed.connect(_close_shop)

func _open_strategy_shop(hero: int, building: int, visit := false, remote := false) -> bool:
	if hud == null or (not visit and not _can_act()): return false
	var trade := director.strategy_shop_trade(state.current_player, hero, building, remote)
	if trade is ELRuneShop: _open_rune_shop(trade, visit)
	elif trade is ELFirstSpellShop: _open_first_shop(trade, visit)
	else: return false
	_refresh_hero_info()
	return true

func _open_rune_shop(trade: ELRuneShop = null, strategic_visit := false) -> void:
	if trade == null: trade = director.rune_shop
	if rune_shop != null or trade == null or hud == null: return
	if strategic_session == null: director.rune_shop = trade
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	rune_shop = ELRuneShopView.new()
	rune_shop.strategic_session = strategic_session
	rune_shop.strategic_shop_visit = strategic_visit
	scrim.add_child(rune_shop)
	rune_shop.build_shop(director, hud, trade)
	rune_shop.closed.connect(_close_rune_shop)

func _close_rune_shop() -> void:
	if rune_shop == null: return
	rune_shop.get_parent().queue_free()
	rune_shop = null
	director.rune_shop = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()
	_show_building_message()

func _open_first_shop(trade: ELFirstSpellShop = null, strategic_visit := false) -> void:
	if trade == null: trade = director.first_shop
	if first_shop != null or trade == null or hud == null: return
	if strategic_session == null: director.first_shop = trade
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	ui.add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	first_shop = ELFirstSpellShopView.new()
	first_shop.strategic_session = strategic_session
	first_shop.strategic_shop_visit = strategic_visit
	scrim.add_child(first_shop)
	first_shop.build_shop(director, hud, trade)
	first_shop.closed.connect(_close_first_shop)

func _close_first_shop() -> void:
	if first_shop == null: return
	first_shop.get_parent().queue_free()
	first_shop = null
	director.first_shop = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()
	_show_building_message()

func _close_shop() -> void:
	if shop == null: return
	shop.get_parent().queue_free()
	shop = null
	director.shop = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 17
	for type: String in ["PanelContainer", "Button"]:
		var style := _style()
		theme.set_stylebox("panel" if type == "PanelContainer" else "normal", type, style)
	ui.theme = theme
	theme.set_stylebox("panel", "TooltipPanel", ELAdventureHud.tooltip_style())
	theme.set_color("font_color", "TooltipLabel", Color("e2d29a"))
	if state.map.profile.id == "el1":
		hud = ELAdventureHud.new()
		ui.add_child(hud)
		if not hud.build(state):
			hud.queue_free()
			hud = null
	elif state.map.profile.id == "el2":
		second_hud = ELSecondAdventureHud.new()
		ui.add_child(second_hud)
		if not second_hud.build(state):
			second_hud.queue_free()
			second_hud = null
	if hud != null: _build_first_controls()
	elif second_hud != null: _build_second_controls()
	else: _build_remake_controls()
	_build_remake_menu()
	notice = Label.new()
	ui.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_left = 24
	notice.offset_top = -203 if state.map.profile.id == "el1" else -167
	notice.offset_right = -24
	notice.offset_bottom = -175 if state.map.profile.id == "el1" else -139
	helper_hint = "Click to move or interact · WASD to pan · Right-drag to rotate · Wheel to zoom · H to follow your hero"
	if state.map.profile.id == "el1": helper_hint = "Select a hero · Click to plan a route or capture · N to end turn · Backspace to clear orders"
	if ELFirstNaval.enabled(state.map): helper_hint = ELRemakeText.t("Click a destination to sail via cyan harbors · Boarding and landing: +3 AP · N to end turn", state.map.profile)
	notice.text = helper_hint if helper_overlay() or (hud == null and second_hud == null) else ""
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_blocker = Control.new()
	dialogue_blocker.name = "DialogueBlocker"
	ui.add_child(dialogue_blocker)
	dialogue_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue_blocker.hide()
	if second_hud != null: _build_second_dialogue()
	else: _build_remake_dialogue()
	if second_hud != null:
		second_precombat = ELSecondPrecombatView.new()
		ui.add_child(second_precombat)
		second_precombat.build(second_hud)
		second_precombat.accepted.connect(begin_encounter)
		second_precombat.declined.connect(decline_encounter)
	if second_hud != null:
		second_hud.resized.connect(_fit_second_layout)
		_fit_second_layout()
	if hud != null:
		hud.resized.connect(_fit_first_layout)
		_fit_first_layout()
		_refresh_roster()
	_apply_helper_overlay()

func _build_remake_menu() -> void:
	var profile := state.map.profile
	remake_overlay = Control.new()
	ui.add_child(remake_overlay)
	remake_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	remake_overlay.hide()
	_remake_menu = PanelContainer.new()
	remake_overlay.add_child(_remake_menu)
	_remake_menu.custom_minimum_size.x = 180
	_remake_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_remake_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_remake_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	var rows := VBoxContainer.new()
	_remake_menu.add_child(rows)
	var campaigns := Button.new()
	campaigns.text = ELRemakeText.t("Campaigns…", profile)
	campaigns.disabled = strategic_session != null
	campaigns.pressed.connect(func(): campaigns_requested.emit())
	rows.add_child(campaigns)
	var options := Button.new()
	options.text = ELRemakeText.t("Options…", profile)
	options.pressed.connect(func():
		close_remake_menu()
		open_original_options())
	rows.add_child(options)
	var back := Button.new()
	back.text = ELRemakeText.t("Close", profile)
	back.pressed.connect(close_remake_menu)
	rows.add_child(back)

func _remake_key_hint() -> void:
	if second_hud == null: return
	var edition := state.map.profile.id
	var overrides := settings.hotkey_overrides(edition) if settings != null else {}
	var code := int(overrides.get("map_remake_menu", KEY_F11))
	var key := InputEventKey.new()
	key.keycode = code & ~ELSettings.HOTKEY_MODIFIERS
	key.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	key.alt_pressed = (code & KEY_MASK_ALT) != 0
	key.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	key.meta_pressed = (code & KEY_MASK_META) != 0
	second_hud.remake_button.tooltip_text = OS.get_keycode_string(code) if ELSettings.hotkey_action(settings, edition, "Map", key) == "map_remake_menu" else ""

func _open_remake_from_pause() -> void:
	close_options()
	_open_remake_menu()

func _open_remake_menu() -> void:
	if director == null or _cursor_modal() or ELWikiScreen.is_open(): return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	_remake_menu.show()
	remake_overlay.move_to_front()
	remake_overlay.show()

func show_remake_picker(picker: Control) -> void:
	_remake_menu.hide()
	_remake_picker = picker
	remake_overlay.add_child(picker)

func close_remake_menu() -> void:
	if remake_overlay == null or not remake_overlay.visible: return
	if is_instance_valid(_remake_picker): _remake_picker.hide()
	_remake_picker = null
	remake_overlay.hide()
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT

## The remake's docked dialogue strip (first game and maps without panel art).
func _build_remake_dialogue() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialoguePanel"
	ui.add_child(dialogue_panel)
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_left = 24
	dialogue_panel.offset_right = -24
	dialogue_panel.offset_top = -245
	dialogue_panel.offset_bottom = -20
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	dialogue_panel.add_child(columns)
	dialogue_portrait = TextureRect.new()
	dialogue_portrait.custom_minimum_size = Vector2(128, 160)
	dialogue_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialogue_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	columns.add_child(dialogue_portrait)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(rows)
	dialogue_name = Label.new()
	dialogue_name.add_theme_font_size_override("font_size", 23)
	dialogue_name.add_theme_color_override("font_color", Color("e0af68"))
	rows.add_child(dialogue_name)
	dialogue_text = RichTextLabel.new()
	dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_text.custom_minimum_size.y = 105
	rows.add_child(dialogue_text)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	accept = Button.new()
	accept.pressed.connect(func(): director.acknowledge("OK"))
	buttons.add_child(accept)
	decline = Button.new()
	decline.text = "No"
	decline.pressed.connect(func(): director.acknowledge("CANCEL"))
	buttons.add_child(decline)
	dialogue_panel.hide()

## Second game: one box object draws the TextDialog and MessageBox panels; the
## dialogue fields point at its parts.
func _build_second_dialogue() -> void:
	second_dialogue = ELSecondDialogueBox.new()
	ui.add_child(second_dialogue)
	second_dialogue.setup(second_hud)
	second_dialogue.answered.connect(func(answer: String): director.acknowledge(answer))
	dialogue_panel = second_dialogue
	dialogue_panel.name = "DialoguePanel"
	dialogue_name = second_dialogue.title
	dialogue_text = second_dialogue.body
	dialogue_portrait = second_dialogue.portrait
	accept = second_dialogue.buttons.TextDialogCloseBtn
	decline = second_dialogue.buttons.TextDialogCancelBtn

## Commands mapped onto the original panel; remake-only actions keep a compact
## strip at the top-left of the map.
func _build_first_controls() -> void:
	hud.hero_selected.connect(_select_hero)
	hud.hero_opened.connect(open_hero_screen)
	hud.building_selected.connect(func(id: int): if not paused: _focus_object(id))
	hud.building_opened.connect(open_building_screen)
	hud.spell_ordered.connect(_order_global_spell)
	hud.spells_opened.connect(func(): open_global_spells())
	hud.diplomacy_opened.connect(open_diplomacy)
	hud.begin_requested.connect(begin_encounter)
	hud.cancel_requested.connect(decline_encounter)
	hud.minimap_clicked.connect(func(cell: Vector2):
		following = -1
		view_moved = true
		target = ELAdventureScene.world_position(cell.x - 0.5, cell.y - 0.5))
	day_button = hud.dial.NextTurn
	day_button.pressed.connect(_end_day)
	if strategic_session != null:
		_turn_clock = ELFirstClock.new()
		ui.add_child(_turn_clock)
		_turn_clock.build(state.map.profile, false)
		strategic_session.turn_timeout.connect(_timed_turn_ended)
		strategic_session.takeover_notice.connect(_show_takeover_notice)
	hud.buttons.NextHero.pressed.connect(_next_hero)
	hud.buttons.HeroInTower.pressed.connect(func():
		hud.tower_only = not hud.tower_only
		_refresh_hero_info())
	leave_button = hud.buttons.RemoveHero
	leave_button.pressed.connect(func():
		if strategic_session != null:
			if not strategic_session.manage_hero(["leave_fort", _hero_id()], func(reason: String):
				if not reason.is_empty(): _remark(reason)):
				_remark("This hero cannot leave right now.")
			return
		if not director.leave_fort(_hero_id()): _remark("This hero cannot leave right now.")
		_refresh_hero_info())
	hud.buttons.Save.pressed.connect(open_save_screen)
	hud.buttons.Load.pressed.connect(open_load_screen)
	hud.buttons.QuitToMainMenu.pressed.connect(func(): leave_requested.emit())
	# The Options column's wrench (registry name DisconnectButton, tooltip
	# "Настройки") opens the Options screen.
	hud.buttons.DisconnectButton.pressed.connect(open_original_options)
	var stats := PanelContainer.new()
	var compact := _style()
	compact.content_margin_left = 8
	compact.content_margin_right = 8
	compact.content_margin_top = 4
	compact.content_margin_bottom = 4
	compact.bg_color = Color(0.067, 0.1, 0.09, 0.82)
	stats.add_theme_stylebox_override("panel", compact)
	hud.remake_strip.add_child(stats)
	hero_info = Label.new()
	hero_info.add_theme_font_size_override("font_size", 10)
	stats.add_child(hero_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	hud.remake_strip.add_child(row)
	# The HeroScreen (portrait double-click) holds the spellbook and level-up
	# offers, GSMode the global spells, a right click on a hero cancels its
	# order: the whole strip is helper-only.
	helper_parts.append_array([stats, row])
	var inventory := _compact_button("Spellbook  [I]", compact)
	inventory.pressed.connect(_open_spellbook.bind(-1))
	row.add_child(inventory)
	skill_button = _compact_button("Skills  [K]", compact)
	skill_button.pressed.connect(_open_skills)
	row.add_child(skill_button)
	if ELGlobalSpells.applies(state):
		var spells_button := _compact_button("Global spells  [G]", compact)
		spells_button.tooltip_text = state.map.profile.text("CtrlTtGSMode").strip_edges()
		spells_button.pressed.connect(open_global_spells)
		row.add_child(spells_button)
	cancel_button = _compact_button("Clear order", compact)
	cancel_button.tooltip_text = "Cancel the selected hero's planned order (Backspace)."
	cancel_button.pressed.connect(_cancel_map_order)
	row.add_child(cancel_button)

func _compact_button(text: String, style: StyleBoxFlat) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 10)
	for kind: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var variant: StyleBoxFlat = style.duplicate()
		if kind == "hover": variant.border_color = Color("c0a060")
		button.add_theme_stylebox_override(kind, variant)
	return button

## Notice and dialogue sit above the resource bar and left of the side panel.
func _fit_first_layout() -> void:
	var factor := hud.scale_factor
	notice.offset_left = 12 * factor
	notice.offset_right = -(149 + 12) * factor
	notice.offset_bottom = -34 * factor
	notice.offset_top = notice.offset_bottom - 22 * factor
	notice.add_theme_font_size_override("font_size", int(12 * factor))
	dialogue_panel.offset_right = -(149 + 16) * factor
	dialogue_panel.offset_bottom = -36 * factor
	dialogue_panel.offset_top = dialogue_panel.offset_bottom - 225

## Second-game commands on the original panels; the next-day command (the
## original's AdvPanelEndTurnBtn is never created) and the skills window keep a
## compact remake strip at the top-left of the map.
func _build_second_controls() -> void:
	second_hud.inventory_requested.connect(_open_spellbook.bind(-1))
	second_hud.notebook_requested.connect(open_notebook)
	second_hud.options_requested.connect(open_options)
	second_hud.centre_requested.connect(_centre_hero)
	second_hud.minimap_clicked.connect(func(cell: Vector2):
		if state.camera_locked: return
		following = -1
		scroll_gliding = false
		view_moved = true
		target = ELAdventureScene.world_position(cell.x - 0.5, cell.y - 0.5))
	# The tutorial cannot be saved, so its Save menu button is disabled.
	if state.tutorial and second_hud.menu_buttons.has("EscSave"):
		second_hud.menu_buttons.EscSave.disabled = true
		second_hud.menu_buttons.EscSave.tooltip_text = "The tutorial cannot be saved."
	second_hud.save_requested.connect(func():
		close_options()
		open_save_screen())
	second_hud.load_requested.connect(func():
		close_options()
		open_load_screen())
	second_hud.exit_requested.connect(func():
		close_options()
		leave_requested.emit())
	second_hud.quit_requested.connect(func(): ELAudio.quiet_quit(get_tree()))
	second_hud.menu_closed.connect(close_options)
	second_hud.remake_menu_requested.connect(_open_remake_from_pause)
	# EscEncyclopaedia (0x636) pushes the Encyclopaedia over the Esc menu; its OK
	# or Esc (0xef4) closes only the Encyclopaedia, so the paused Esc menu returns.
	second_hud.original_options_requested.connect(open_original_options)
	second_hud.encyclopaedia_requested.connect(func():
		if not open_extras("encyclopaedia", true): notice.text = "The Encyclopaedia art is unavailable.")
	var compact := _style()
	compact.content_margin_left = 8
	compact.content_margin_right = 8
	compact.content_margin_top = 4
	compact.content_margin_bottom = 4
	compact.bg_color = Color(0.067, 0.1, 0.09, 0.82)
	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel", compact)
	second_hud.remake_strip.add_child(stats)
	hero_info = Label.new()
	hero_info.add_theme_font_size_override("font_size", 10)
	stats.add_child(hero_info)
	# Name, level, health and day are on AdvPanelLB/RB, experience in the level
	# tooltip; travel points have no original readout: the box is helper-only.
	# Next day and Skills have no original control (the day rolls when the
	# main hero's travel runs out; the level-up dialog opens by itself), so
	# they are remake helpers too; K still opens the skills.
	helper_parts.append(stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	second_hud.remake_strip.add_child(row)
	helper_parts.append(row)
	# No shortcut: N belongs to the Notebook in the second game.
	# The never-created AdvPanelEndTurnBtn's own caption and tooltip.
	var next_day := _compact_button(_text_or("CtrlAdvPanelEndTurnBtn", "Next day"), compact)
	next_day.name = "NextDay"
	next_day.tooltip_text = state.map.profile.text("CtrlTTAdvPanelEndTurnBtn")
	next_day.pressed.connect(_end_day)
	row.add_child(next_day)
	day_button = next_day
	skill_button = _compact_button(_text_or("CtrlInvScrHdrSkills", "Skills"), compact)
	skill_button.name = "Skills"
	skill_button.tooltip_text = skill_button.text + " (K)"
	skill_button.pressed.connect(_open_skills)
	row.add_child(skill_button)

## Remake-only details: travel points and experience numbers; health, level,
## name, resources and day are on the original panels.
func _refresh_second_hud(hero: Dictionary) -> void:
	var level := int(hero.get("level", 1))
	var experience := str(ELHeroProgression.effective(hero)) + (" / %d XP" % ELHeroProgression.threshold(state.map.profile, level + 1) if level < ELHeroProgression.MAX_LEVEL else " XP · Maximum level")
	hero_info.text = "%s  ·  Level %d  ·  %s\n%d / %d travel  ·  Day %d" % [hero.get("title", ""), level, experience, hero.get("ap", 0), hero.get("travel_capacity", 8), state.day + 1]
	if skill_button != null: skill_button.text = _text_or("CtrlInvScrHdrSkills", "Skills") + (" (%d)" % hero.skill_points if int(hero.get("skill_points", 0)) > 0 else "")
	var acting := _can_act()
	day_button.disabled = not acting
	second_hud.buttons.AdvPanelOptionsBtn.disabled = paused and not second_hud.menu.visible
	second_hud.refresh(_hero_id(), acting)

## The Notebook (AdvPanelNotesBtn, N) pauses the map like other windows.
func open_notebook() -> void:
	if second_hud == null or notebook != null or paused: return
	var view := ELSecondNotebookView.new()
	ui.add_child(view)
	if not view.build(second_hud):
		view.queue_free()
		notice.text = "The Notebook art is unavailable."
		return
	notebook = view
	notebook.closed.connect(close_notebook)
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_hero_info()

func close_notebook() -> void:
	if notebook == null: return
	notebook.queue_free()
	notebook = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## The Esc menu (AdvPanelOptionsBtn, Esc) pauses the map like other windows.
func open_options() -> void:
	if second_hud == null or second_hud.menu.visible or paused: return
	paused = true
	dragging = false
	if world != null: world.process_mode = Node.PROCESS_MODE_DISABLED
	second_hud.show_menu(true)

func close_options() -> void:
	if second_hud == null or not second_hud.menu.visible: return
	second_hud.show_menu(false)
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## Notice and dialogue sit between the statues, above the panels' lower strips.
func _fit_second_layout() -> void:
	var factor := second_hud.scale_factor
	notice.offset_left = 160 * factor
	notice.offset_right = -160 * factor
	notice.offset_bottom = -(61 + 6) * factor
	notice.offset_top = notice.offset_bottom - 22 * factor
	notice.add_theme_font_size_override("font_size", int(12 * factor))
	if second_dialogue != null:
		second_dialogue.layout()
		return
	dialogue_panel.offset_left = 160 * factor
	dialogue_panel.offset_right = -160 * factor
	dialogue_panel.offset_bottom = -(61 + 8) * factor
	dialogue_panel.offset_top = dialogue_panel.offset_bottom - 225

func _build_remake_controls() -> void:
	var top := PanelContainer.new()
	ui.add_child(top)
	top.position = Vector2(16, 16)
	title = Label.new()
	title.text = state.map.title
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	var back := Button.new()
	ui.add_child(back)
	back.text = "Return to menu"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -180
	back.offset_right = -16
	back.offset_top = 16
	back.pressed.connect(func(): leave_requested.emit())
	var save := Button.new()
	ui.add_child(save)
	save.text = "Save  [F5]"
	save.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	save.offset_left = -180
	save.offset_right = -16
	save.offset_top = 76
	save.pressed.connect(open_save_screen)
	var resume := Button.new()
	ui.add_child(resume)
	resume.text = "Load  [F9]"
	resume.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resume.offset_left = -180
	resume.offset_right = -16
	resume.offset_top = 136
	resume.pressed.connect(open_load_screen)
	var inventory := Button.new()
	ui.add_child(inventory)
	inventory.text = "Spellbook  [I]"
	inventory.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	inventory.offset_left = -180
	inventory.offset_right = -16
	inventory.offset_top = 196
	inventory.pressed.connect(_open_spellbook.bind(-1))
	skill_button = Button.new()
	ui.add_child(skill_button)
	skill_button.text = "Skills  [K]"
	skill_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skill_button.offset_left = -180
	skill_button.offset_right = -16
	skill_button.offset_top = 256
	skill_button.pressed.connect(_open_skills)
	var next_day := Button.new()
	day_button = next_day
	ui.add_child(day_button)
	next_day.text = "End turn  [N]" if state.map.profile.id == "el1" else "Next day  [N]"
	day_button.tooltip_text = "Resolve planned orders and collect production." if state.map.profile.id == "el1" else "Spend the remaining travel points and collect mine production."
	day_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	day_button.offset_left = -180
	day_button.offset_right = -16
	day_button.offset_top = 316
	day_button.pressed.connect(_end_day)
	if state.map.profile.id == "el1":
		hero_selector = OptionButton.new()
		ui.add_child(hero_selector)
		hero_selector.position = Vector2(16, 76)
		hero_selector.custom_minimum_size.x = 220
		hero_selector.item_selected.connect(func(index: int): _select_hero(int(hero_selector.get_item_metadata(index))))
		_refresh_roster()
		cancel_button = Button.new()
		ui.add_child(cancel_button)
		cancel_button.text = "Clear order"
		cancel_button.tooltip_text = "Cancel the selected hero's planned order (Backspace)."
		cancel_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		cancel_button.offset_left = -180
		cancel_button.offset_right = -16
		cancel_button.offset_top = 376
		cancel_button.pressed.connect(_cancel_map_order)
		var leave := Button.new()
		leave_button = leave
		ui.add_child(leave_button)
		leave.text = "Leave fort"
		leave_button.tooltip_text = "The garrison returns to the tile it entered from."
		leave_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		leave_button.offset_left = -180
		leave_button.offset_right = -16
		leave_button.offset_top = 436
		leave_button.pressed.connect(func():
			if not director.leave_fort(_hero_id()): _remark("The garrison cannot leave right now.")
			_refresh_hero_info())
		leave_button.hide()
	var stats := PanelContainer.new()
	ui.add_child(stats)
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stats.offset_left = 16
	stats.offset_top = -164 if state.map.profile.id == "el1" else -128
	stats.offset_bottom = -16
	hero_info = Label.new()
	hero_info.add_theme_font_size_override("font_size", 14)
	hero_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_info.custom_minimum_size.x = 480
	stats.add_child(hero_info)

static func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a17f2")
	style.border_color = Color("78623f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

## The original advances in 64 ms steps and scales the remainder by 67 ms.
static func _script_lens_step(current: float, goal: float, rate: float, delta: float) -> float:
	var difference := goal - current
	if absf(difference * rate) < 0.001: return goal
	var steps := maxf(0, ceilf(delta / TURN_TICK) - 1.0)
	var remainder := delta - steps * TURN_TICK
	return goal - difference * pow(1.0 - rate, steps) * (1.0 - rate * remainder / 0.067)

## A script's distance or angle outlasts a speaker box's close view.
func _set_script_lens(distance: float, angle: float, instant: bool) -> void:
	var goal := view_goal if view_goal.x > 0 else Vector2(zoom, pitch)
	if distance > 0:
		goal.x = distance
		if instant: zoom = distance
	if angle > 0:
		goal.y = angle
		if instant: pitch = angle
	view_goal = goal if goal != Vector2(zoom, pitch) else Vector2(-1, -1)
	if not instant: _script_lens = true
	if distance > 0: state.camera_zoom = distance
	if not text_view.is_empty():
		if distance > 0: text_view.zoom = distance
		if angle > 0: text_view.pitch = angle

func camera_state() -> Dictionary:
	# The standing view is saved, not a speaker box's close view.
	var standing := Vector2(zoom, pitch)
	if not text_view.is_empty(): standing = Vector2(float(text_view.zoom), float(text_view.pitch))
	elif view_goal.x > 0: standing = view_goal
	return {"yaw": yaw, "pitch": standing.y, "zoom": standing.x, "perspective": camera != null and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "target": [camera_goal().x, camera_goal().y, camera_goal().z], "following": following, "script_camera_attached": script_camera_attached, "selected_hero": _hero_id(), "voice_position": audio.voice.get_playback_position() if audio != null and audio.voice.playing else 0.0}

func set_suspended(value: bool) -> void:
	# A message shown while the battle was open keeps the map paused.
	paused = value or building_message != null
	visible = not value
	ui.visible = not value
	world.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	audio.suspended = value
	var first := state.map.profile.id == "el1"
	if first and value: audio.first_battle(true, state)
	for player: AudioStreamPlayer in audio.players():
		if value: player.set_meta("map_paused", player.stream_paused)
		player.stream_paused = true if value else bool(player.get_meta("map_paused", false))
	if first and not value: audio.first_battle(false, state)
	if not value:
		camera.current = true
		if second_hud != null: _show_waiting_map_dialogs()

## F5: the original quick save, the named slot T_QUICK_SAVE_NAME of this
## edition, overwritten without a question; T_GAME_SAVED confirms it.
func quick_save() -> void:
	if _save_preview_pending: return
	ELCrashReport.trace("map quick save")
	if state.tutorial:
		notice.text = "The tutorial cannot be saved."
		return
	wait_cursor(state.map.profile)
	var preview := await _capture_save_preview()
	var error_text := _save_named(ELSaveSlots.quick_name(state.map.profile), preview)
	# The second game prints the confirmation on its message line.
	if error_text.is_empty() and second_hud != null: second_hud.add_message(state.map.profile.text("T_GAME_SAVED"))
	else: notice.text = state.map.profile.text("T_GAME_SAVED").strip_edges() if error_text.is_empty() else error_text

## The open quick-load question (a second F8 answers it).
var _quick_load_box: Control

## F8 / F9: the quick load asks T_MB_LOAD_GAME first; OK resumes the quick
## save, Cancel or Esc keeps playing. Nothing happens without a quick save
## (or an old single-slot file) to load.
func ask_quick_load() -> void:
	if not _can_load_in_place(): return
	var load_save := func(): resume_requested.emit()
	var path := ELSaveSlots.quick_load_path(state)
	if strategic_session != null:
		path = ELSaveSlots.save_path(state.map.profile.id, ELSaveSlots.quick_name(state.map.profile), ELSaveSlots.KIND_STRATEGIC)
		var row := {"path": path, "kind": ELSaveSlots.KIND_STRATEGIC, "name": ELSaveSlots.quick_name(state.map.profile)}
		load_save = func(): slot_requested.emit(row)
	if not FileAccess.file_exists(path):
		notice.text = "There is no quick save to load."
		return
	if not _extras_ready():
		load_save.call()
		return
	_after_extras = Callable()
	dragging = false
	extras.ask_hosted(state.map.profile.text("T_MB_LOAD_GAME").strip_edges(), load_save)
	_quick_load_box = extras.duel_ui.message
	extras_layer.show()
	extras.show()

## Options Save / Esc menu Save: SaveMissionScreen in save mode over the map
## (the quick save when the original art is missing).
func open_save_screen() -> void:
	if _save_preview_pending: return
	if strategic_session != null:
		var problem := strategic_session.save_problem()
		if not problem.is_empty():
			_remark(problem)
			return
	if state.tutorial:
		notice.text = "The tutorial cannot be saved."
		return
	if not _extras_ready():
		quick_save()
		return
	var preview := await _capture_save_preview()
	_open_save_list("save_game", preview)

## Options Load / Esc menu Load: SaveMissionScreen in load mode over the map
## (the quick save when the original art is missing).
func open_load_screen() -> void:
	if not _can_load_in_place(): return
	if _open_save_list("load_game"): return
	if strategic_session != null: ask_quick_load()
	else: resume_requested.emit()

func _can_load_in_place() -> bool:
	return strategic_session == null or (strategic_session.link.local_authority and strategic_session.can_plan())

func _save_named(name: String, preview: Image = null) -> String:
	if strategic_session != null: return strategic_session.save(name, camera_state())
	return ELSaveSlots.write(name, director, camera_state(), preview)

## Render the map from the same camera in a viewport without any HUD layers.
func _capture_save_preview() -> Image:
	if DisplayServer.get_name() == "headless" or not is_visible_in_tree(): return null
	if not RenderingServer.is_render_loop_enabled(): return null
	var viewport := get_viewport()
	if viewport.get_camera_3d() != camera: return null
	var dimensions := viewport.get_texture().get_size()
	if dimensions.x < 2.0 or dimensions.y < 2.0: return null
	_save_preview_pending = true
	var was_paused := paused
	paused = true

	var preview := SubViewport.new()
	var scale_factor := minf(1.0, (2.0 * ELSaveSlots.PREVIEW_SIZE.y) / minf(dimensions.x, dimensions.y))
	scale_factor = minf(scale_factor, 1536.0 / maxf(dimensions.x, dimensions.y))
	preview.size = Vector2i((dimensions * scale_factor).round()).max(Vector2i(2, 2))
	preview.gui_disable_input = true
	preview.world_3d = camera.get_world_3d()
	add_child(preview)

	var capture_camera := Camera3D.new()
	capture_camera.keep_aspect = camera.keep_aspect
	capture_camera.projection = camera.projection
	capture_camera.fov = camera.fov
	capture_camera.size = camera.size
	capture_camera.frustum_offset = camera.frustum_offset
	capture_camera.near = camera.near
	capture_camera.far = camera.far
	capture_camera.cull_mask = camera.cull_mask
	capture_camera.environment = camera.environment
	capture_camera.attributes = camera.attributes
	preview.add_child(capture_camera)
	capture_camera.global_transform = camera.get_camera_transform()
	capture_camera.make_current()
	preview.render_target_update_mode = SubViewport.UPDATE_ONCE

	await RenderingServer.frame_post_draw
	var image := preview.get_texture().get_image() if viewport.get_camera_3d() == camera else null
	preview.queue_free()
	paused = was_paused
	_save_preview_pending = false
	if image == null or image.is_empty(): return null
	# The centre of a wide window, at the picture's 4:3 shape.
	var shape := float(ELSaveSlots.PREVIEW_SIZE.x) / ELSaveSlots.PREVIEW_SIZE.y
	var full := image.get_size()
	var cut := Vector2i(mini(full.x, roundi(full.y * shape)), mini(full.y, roundi(full.x / shape)))
	if cut != full: image = image.get_region(Rect2i((full - cut) / 2, cut))
	image.resize(ELSaveSlots.PREVIEW_SIZE.x, ELSaveSlots.PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	return image

## The mission-start autosave is written before the map is drawn; its picture
## is added once the opening view is on screen (the saved game is unchanged).
func _attach_start_preview() -> void:
	if DisplayServer.get_name() == "headless": return
	var path := ELSaveSlots.auto_path(state.map.profile.id, ELSaveSlots.kind_of(state), "T_AUTOSAVE_START_MISSION")
	var written := FileAccess.get_modified_time(path)
	for i in 3: await RenderingServer.frame_post_draw
	if not is_inside_tree() or _save_preview_pending: return
	var preview := await _capture_save_preview()
	if preview != null and is_inside_tree() and FileAccess.get_modified_time(path) == written: ELSaveSlots.attach_preview(path, preview)

func _open_save_list(target: String, preview: Image = null) -> bool:
	if not _extras_ready(): return false
	extras.mission_load_ui.saver = func(name: String) -> String:
		wait_cursor(state.map.profile)
		return _save_named(name, preview)
	extras.mission_load_ui.current = ELSaveSlots.current_row(state)
	if preview != null: extras.mission_load_ui.current.preview = ImageTexture.create_from_image(preview)
	var kind := ELSaveSlots.kind_of(state) if strategic_session == null else ELSaveSlots.KIND_STRATEGIC
	extras.mission_load_ui.current.kind = kind
	return open_extras(target, true, Callable(), kind)

## First game: the tutorial panel over the map. The adventure screen event
## fires when the human's turn begins (the first day here, later day starts
## through the session events).
func _build_first_tutorial() -> void:
	if ui == null or settings == null: return
	tutorial_panel = ELFirstTutorialPanel.new()
	ui.add_child(tutorial_panel)
	tutorial_panel.build(state.map.profile, ELFirstTutorial.for_settings(settings), ELFirstTutorial.ADVENTURE)
	tutorial_panel.set_volume(float(settings.values.get("effects", 1.0)))
	tutorial_panel.watch_adventure(self)
	if hud != null: hud.hero_selected.connect(func(_id: int): tutorial_panel.fire("HERO_CLICK"))
	if not state.tutorial: tutorial_panel.fire("ADVENTURE_SCREEN")

## A tutorial event of the map by name (windows ported later report here).
func tutorial_event(event_name: String) -> void:
	if tutorial_panel != null: tutorial_panel.fire(event_name)

func _loading(fraction: float) -> void:
	if loading_progress.is_valid(): loading_progress.call(fraction)

func _fail(message: String) -> bool:
	error = message
	return false
