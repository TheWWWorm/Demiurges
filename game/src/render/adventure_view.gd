class_name ELAdventureView
extends Node3D
signal leave_requested
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
var title: Label
var hero_info: Label
var notice: Label
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
var route: MeshInstance3D
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
## Scripted camera turns ease as in the original: each 64 ms tick moves the
## view a sixth of the remaining angle, the shorter way round, and it settles
## once that step is under 0.001 rad. INF when no turn is pending.
const TURN_RATE := 1.0 / 6.0
const TURN_TICK := 0.064
var yaw_goal := INF
var zoom_limits := Vector2(16, 100)
var following := -1
var dragging := false
var error := ""
var paused := false
var settings: ELSettings
var _art: ELAdventureArt
var audio: ELAdventureAudio
## Second game: script particle effects (weather, scenery and cutscene effects).
var effects: ELAdventureEffects
## First game: blazons, building sounds and effects, terrain ambience.
var presentation: ELFirstMapPresentation
var spellbook: ELSpellbookView
var skills: ELHeroSkillsView
var global_spells: ELGlobalSpellsView
var diplomacy: ELDiplomacyView
var global_spell_waiting := false
var skill_button: Button
var day_button: BaseButton
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
var building_screen: ELBuildingScreenView
var building_message: ELBuildingMessageView
var building_messages: Array[Dictionary] = []
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
## Edge camera: the pointer at a screen edge pans (first game; with Ctrl it
## turns and tilts) or turns the view (second game, left and right edges).
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
	# Building or restoring a map shows the wait cursor until the map picks again.
	wait_cursor(profile)
	var map := ELAdventureMap.new()
	if restored.is_empty():
		if not map.load_map(profile, str(scenario.file_name)): return _fail(map.error)
		state = ELAdventureSession.new()
		if not state.start(map, difficulty, 212, str(scenario.get("script", "")), int(str(scenario.get("player", "1"))), scenario.has("number")): return _fail(state.error)
		state.tutorial = bool(scenario.get("tutorial", false))
		director = ELAdventureDirector.new()
		if not director.build(state): return _fail(director.error)
	else:
		state = restored.state
		director = restored.director
		map = state.map
	if scenario.has("header"): map.title = profile.text(str(scenario.header))
	elif profile.id == "el2":
		var metadata := ELCampaign.find_scenario(profile, map.id, state.script_name)
		if metadata.has("header"): map.title = profile.text(str(metadata.header))
	state.event.connect(_state_event)
	director.presentation.connect(_present)
	# ExIsDesktopModalChild: any window or message box over the map.
	state.desktop_modal = func() -> bool: return paused or extras_open() or not director.dialogue.is_empty() or director._shopping()
	_art = ELAdventureArt.new(map)
	world = ELAdventureScene.new()
	add_child(world)
	if not world.build(map, state): return _fail("; ".join(world.errors))
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
	_refresh_hero_info()
	audio = ELAdventureAudio.new()
	add_child(audio)
	audio.build(profile, preferences)
	apply_settings()
	if profile.id == "el2":
		effects = ELAdventureEffects.new()
		world.add_child(effects)
		effects.build(profile, preferences, state)
		audio.listener = target
		audio.restore(state)
	elif profile.id == "el1":
		audio.start_first(state)
		_build_presentation()
	route = MeshInstance3D.new()
	add_child(route)
	if not restored.is_empty():
		var saved: Dictionary = restored.camera
		# A view saved for the other projection (an earlier orthographic map)
		# keeps the standing view instead.
		if bool(saved.get("perspective", false)) == (camera.projection == Camera3D.PROJECTION_PERSPECTIVE):
			yaw = float(saved.get("yaw", yaw))
			pitch = clampf(float(saved.get("pitch", pitch)), pitch_limits.x, pitch_limits.y)
			zoom = clampf(float(saved.get("zoom", zoom)), zoom_limits.x, zoom_limits.y)
		following = int(saved.get("following", following))
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
			world.move_actor(director.movement.id, Vector2(director.movement.path[at]).lerp(Vector2(director.movement.path[at + 1]), director.movement.progress), true)
		elif profile.id == "el1": _draw_route(ELStrategy.order_path(director, state.object(_hero_id())))
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
		if profile.id == "el2" and scenario.get(ELSecondCampaign.KEY) is Dictionary:
			var problem := ELSecondCampaign.start_chapter(state, scenario[ELSecondCampaign.KEY])
			if not problem.is_empty(): return _fail(problem)
			_refresh_hero_info()
		ELFirstScenario.opening(director)
		# First game: every mission start is saved as T_AUTOSAVE_START_MISSION.
		if profile.id == "el1" and not state.tutorial:
			wait_cursor(profile)
			ELSaveSlots.write_auto("T_AUTOSAVE_START_MISSION", director, camera_state())
	if profile.id == "el1": _build_first_tutorial()
	if not state.outcome.is_empty(): _show_result()
	return true

func _exit_tree() -> void:
	if state != null: state.close()

func _process(delta: float) -> void:
	if hud != null and paused and hud.tooltip.visible: hud.tooltip.hide()
	_tick_cursor(delta)
	if second_hud != null: _tick_map_tooltip(delta)
	if director == null or not error.is_empty() or paused or extras_open():
		# Second game: the hero readouts follow the state under a message box or
		# window too (a building use pays its points before its message opens).
		if second_hud != null and director != null: _refresh_hero_info()
		return
	# Notebook entries keep the point the camera looks at.
	state.view_point = Vector2(target.x, -target.z) / ELAdventureTerrain.CELL
	# Options "Accelerated mode": map movement at 16 instead of 4 cells a second.
	director.fast_mode = bool(settings.values.get("adventure_fast", false)) if settings != null else false
	director.advance(delta)
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
		var ease := minf(1, delta * 1.0)
		zoom = lerpf(zoom, view_goal.x, ease)
		pitch = lerpf(pitch, view_goal.y, ease)
		if absf(zoom - view_goal.x) < 0.02 and absf(pitch - view_goal.y) < 0.002:
			zoom = view_goal.x
			pitch = view_goal.y
			view_goal = Vector2(-1, -1)
	if following >= 0 and world.actors.has(following):
		target = target.lerp(world.actors[following].position, minf(1, delta * 6.0))
	elif not state.camera_locked:
		var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		var flat := Vector3(direction.x, 0, direction.y).rotated(Vector3.UP, yaw)
		target += flat * delta * zoom * 0.8 * (float(settings.values.get("keyboard_scroll", 1.0)) if settings != null else 1.0)
	_update_camera()
	_update_rings(delta)
	if audio != null:
		audio.listener = target
		audio.listener_forward = -camera.global_basis.z
	if presentation != null:
		presentation.listener = target
		presentation.listener_forward = -camera.global_basis.z
	_refresh_hero_info()
	_auto_level_up()

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
		if not _pointer_on_map or Input.is_anything_pressed() or state.exclusive or not state.commands.is_empty(): return Vector2i.ZERO
		if _pointer.x < 4: return Vector2i(-1, 0)
		if _pointer.x > size.x - 4: return Vector2i(1, 0)
		return Vector2i.ZERO
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
	elif state.map.profile.id == "el2":
		turn_target = direction.x * EDGE_TURN * rotation_speed * (-1.0 if bool(values.get("invert_rotation", false)) else 1.0)
	elif Input.is_key_pressed(KEY_CTRL):
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
		target += Vector3(_edge_pan.x, 0, _edge_pan.y).rotated(Vector3.UP, yaw) * delta
	# The same turn as dragging towards that edge.
	yaw -= _edge_turn * delta
	if turn_target != 0.0: yaw_goal = INF
	pitch = clampf(pitch + _edge_tilt * delta, pitch_limits.x, pitch_limits.y)

## Held arrow keys on the camera tick (original key-down/key-up handlers).
## First game: arrows pan 2*KeyboardScroll units a tick; with Ctrl, Left/Right
## turn 0.2*KeyboardRotation rad a tick (Ctrl+Left the way Ctrl at the right
## edge turns) and Up/Down tilt as Ctrl at the top/bottom edge. Second game:
## Left/Right turn the way the matching edge does (InvertRotation flips), never
## while a script holds the map; no keyboard panning. Empty when idle.
func keyboard_motion() -> Dictionary:
	if state == null or state.map == null or director == null or state.camera_locked or not visible or paused or _cursor_modal(): return {}
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus is LineEdit or focus is TextEdit: return {}
	var x := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	var y := float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	if x == 0.0 and y == 0.0: return {}
	var values: Dictionary = settings.values if settings != null else {}
	var rotation_speed := float(values.get("keyboard_rotation", 1.0))
	if state.map.profile.id == "el2":
		if x == 0.0 or state.exclusive: return {}
		return {"turn": x * EDGE_TURN * rotation_speed * (-1.0 if bool(values.get("invert_rotation", false)) else 1.0)}
	if Input.is_key_pressed(KEY_CTRL): return {"turn": -x * EDGE_TURN * rotation_speed, "tilt": y * EDGE_TILT}
	return {"pan": Vector2(x, y) * EDGE_PAN * float(values.get("keyboard_scroll", 1.0))}

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
	_refresh_roster()
	var path := ELStrategy.order_path(director, actor)
	_draw_route(path)
	var preview := director.interception.preview(state, actor, path)
	if not preview.is_empty() and not director.interception.enemies(state, actor, preview[-1]).is_empty():
		director.notice = ELInterception.ROUTE_NOTICE
	else: director.notice = ""
	_remark(director.notice)
	_refresh_hero_info()

func _can_act() -> bool:
	return not paused and director.can_move() and director.movement.is_empty()

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
	if day_button != null: day_button.disabled = paused or not director.can_move() or not director.movement.is_empty()
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

## Second game: PreCombatCancel declines the battle shown in the panel.
func decline_encounter() -> void:
	if pending_encounter.is_empty(): return
	pending_encounter = []
	_close_second_precombat()
	if not director.decline_encounter(): notice.text = director.error
	_refresh_hero_info()

func _close_second_precombat() -> void:
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
		faces.append(int(_art.resolve(actor).get("row", {}).get("Face", -1)) if not actor.is_empty() else -1)
	pending_encounter = [first, second]
	# The camera centres between the two sides while the panel is up.
	var one := state.object(first)
	var two := state.object(second)
	if not one.is_empty() and not two.is_empty():
		following = -1
		target = (ELAdventureScene.world_position(one.x, one.y) + ELAdventureScene.world_position(two.x, two.y)) * 0.5
	second_hud.hide()
	second_precombat.open(state, local, other, faces)

func _open_lose_battle() -> void:
	if second_hud == null or lose_battle != null: return
	lose_battle = ELSecondLoseBattleView.new()
	ui.add_child(lose_battle)
	lose_battle.build(second_hud)
	lose_battle.closed.connect(func(): lose_battle = null)

func _end_day() -> void:
	if paused: return
	# First game: the Autosave option saves before the turn ends.
	if state.map.profile.id == "el1" and (settings == null or bool(settings.values.get("autosave", true))) and director.can_move() and director.movement.is_empty():
		wait_cursor(state.map.profile)
		var failed := ELSaveSlots.write_auto("T_AUTOSAVE_EOT", director, camera_state())
		if not failed.is_empty() and not state.tutorial: notice.text = failed
	if not director.end_day(): _remark(director.notice)
	_refresh_hero_info()

func _unhandled_input(event: InputEvent) -> void:
	# The tutorial panel takes every key and click while it is open.
	if tutorial_panel != null and tutorial_panel.handle_input(event): return
	# A script message box over a window is modal: keys answer it.
	if dialogue_blocker != null and dialogue_blocker.visible and director != null and not director.dialogue.is_empty():
		if second_dialogue != null:
			if event is InputEventKey and event.pressed and not event.echo:
				var answer := second_dialogue.key_answer(event.keycode)
				if not answer.is_empty(): director.acknowledge(answer)
				if not answer.is_empty() or event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]: get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			director.acknowledge("CANCEL" if event.keycode == KEY_ESCAPE and bool(director.dialogue.get("question", false)) else "OK")
			get_viewport().set_input_as_handled()
		return
	if hero_screen != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			hero_screen.cancel()
			get_viewport().set_input_as_handled()
		return
	if building_screen != null:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
			_close_building_screen()
			get_viewport().set_input_as_handled()
		return
	if building_message != null:
		var loot_panel := building_message.message_box != null and building_message.message_box.style == "loot"
		if event is InputEventKey and event.pressed and (building_message.message_box.key_answer(event.keycode) == "OK" if loot_panel else event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
			_close_building_message()
			get_viewport().set_input_as_handled()
		return
	if global_spells != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			global_spells.cancel()
			get_viewport().set_input_as_handled()
		return
	if diplomacy != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			diplomacy.cancel()
			get_viewport().set_input_as_handled()
		return
	if first_shop != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			first_shop.cancel_trade()
			get_viewport().set_input_as_handled()
		return
	if rune_shop != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			rune_shop.cancel_trade()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode in RUNE_SHOP_KEYS:
			rune_shop.move_selection(RUNE_SHOP_KEYS[event.keycode])
			get_viewport().set_input_as_handled()
		return
	if shop != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			shop.cancel_trade()
			get_viewport().set_input_as_handled()
		return
	if skills != null:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_K]:
			_close_skills()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and skills is ELSecondLevelUpView:
			(skills as ELSecondLevelUpView).press_ok()
			get_viewport().set_input_as_handled()
		return
	if spellbook != null:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_I]:
			_close_spellbook()
			get_viewport().set_input_as_handled()
		return
	if second_hud != null and second_hud.menu.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_options()
			get_viewport().set_input_as_handled()
		return
	if notebook != null:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_N]:
			notebook.close()
			get_viewport().set_input_as_handled()
		return
	if lose_battle != null:
		if event is InputEventKey and event.pressed and not event.echo: lose_battle.dismiss()
		if event is InputEventKey: get_viewport().set_input_as_handled()
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
		return
	# Second game: the open script box takes its keys first (Enter/Esc/Space).
	if second_dialogue != null and event is InputEventKey and event.pressed and not event.echo and not director.dialogue.is_empty():
		var answer := second_dialogue.key_answer(event.keycode)
		if not answer.is_empty(): director.acknowledge(answer)
		if not answer.is_empty() or event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I: _open_spellbook(-1)
		elif event.keycode == KEY_K: _open_skills()
		elif event.keycode == KEY_G and ELGlobalSpells.applies(state): open_global_spells()
		# Second game: N is the Notebook accelerator; the first keeps
		# N for its end-turn command.
		elif event.keycode == KEY_N and second_hud != null:
			if director.dialogue.is_empty(): open_notebook()
		elif event.keycode == KEY_N: _end_day()
		elif event.keycode == KEY_BACKSPACE and state.map.profile.id == "el1": director.cancel_order(_hero_id())
		elif event.keycode == KEY_F5: quick_save()
		# F8 is the original quick load; F9 is kept as the remake's key.
		elif event.keycode in [KEY_F8, KEY_F9]: ask_quick_load()
		elif event.keycode == KEY_ESCAPE and second_hud != null and director.dialogue.is_empty():
			open_options()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and not director.dialogue.is_empty():
			director.acknowledge()
			get_viewport().set_input_as_handled()
		# First game: H opens the tutorial; Home centres the hero.
		elif event.keycode == KEY_H and tutorial_panel != null: tutorial_panel.open_history()
		elif event.keycode in [KEY_HOME, KEY_H]: following = _hero_id()
		elif event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]: following = -1
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
				if hud != null and event.position.distance_to(_right_origin) <= ELSecondMapTooltips.DRAG_THRESHOLD: _cancel_order_at(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			view_goal = Vector2(-1, -1)
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), zoom_limits.x, zoom_limits.y)
			if second_hud != null:
				map_tip.clear()
				second_hud.hide_map_tooltip()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if hit != null and hud != null and ELHeroExchange.applies(state) and (event.ctrl_pressed or event.double_click) and _hero_click(Vector2i(floori(hit.x / 2.0), floori(-hit.z / 2.0)), event.ctrl_pressed): return
			if hit != null: _click_ground(Vector2i(floori(hit.x / 2.0), floori(-hit.z / 2.0)))
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

## Second game: every cursor move is seen here, before the panels take it;
## _unhandled_input marks the moves that reached the map. A right release
## anywhere ends the press.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = event.position
		_pointer_on_map = false
		_cursor_moved = true
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
			if context.in_bounds: context.picked = ELSecondMapTooltips.object_at(state, point) if second else _object_at(point)
	cursor_context = context
	cursor_name = ELCursors.second_adventure(state, director, context) if second else ELCursors.first_adventure(state, director, context)
	if not edge_cursor.is_empty() and not context.modal: cursor_name = edge_cursor
	ELCursorDriver.request(state.map.profile, cursor_name)

## Windows, panels and message boxes over the map show the default cursor.
func _cursor_modal() -> bool:
	return paused or not error.is_empty() or extras_open() or not director.dialogue.is_empty() \
		or hero_screen != null or building_screen != null or building_message != null or global_spells != null or diplomacy != null \
		or first_shop != null or rune_shop != null or shop != null or skills != null or spellbook != null or notebook != null \
		or (second_hud != null and second_hud.menu.visible) or result_shown \
		or (hud != null and hud.precombat.visible) or (second_precombat != null and second_precombat.visible) or lose_battle != null

## Original map tooltip for the castle, hero or creature under the cursor.
func hover(at: Vector2) -> void:
	var id := -1
	if hud.map_rect().has_point(at):
		var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
		if hit != null: id = _object_at(Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL)
	var item := state.object(id)
	hud.show_tooltip(id, hud.describe(item, _art.resolve(item).get("row", {})) if not item.is_empty() else {}, at)

## First-game building groups with their own map tooltip (and use cursor).
const FIRST_SITE_GROUPS := ["mines", "mana_nodes", "forts", "laboratories", "factories", "resource_cuts"]

## Standing figures extend above their tile, so actors accept points slightly
## behind them; buildings use their footprint.
func _object_at(point: Vector2) -> int:
	var best := -1
	var distance := INF
	for id: int in state.objects:
		var item: Dictionary = state.objects[id]
		if not item.alive or not item.visible or not item.get("placed", true) or item.get("fortified", false) or _fogged(item): continue
		if item.get("type") in ["hero", "monster"]:
			var offset := point - Vector2(float(item.x) + 0.5, float(item.y) + 0.5)
			if absf(offset.x) < 0.9 and offset.y > -0.9 and offset.y < 2.2 and offset.length() < distance:
				best = id
				distance = offset.length()
		elif best < 0 and (ELFirstScenario.is_castle(item) or (state.map.profile.id == "el1" and str(item.get("group", "")) in FIRST_SITE_GROUPS) or (ELMapPickups.is_pickup(item) and (state.map.profile.id == "el1" or item.group == "artefacts")) or (item.get("group") == "additional_buildings" and state.map.profile.id == "el1" and not ELAdditionalBuildings.title(state.map.profile, item).is_empty())):
			var size: Vector2i = director.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
			if Rect2(item.x, item.y, size.x, size.y).has_point(point): best = id
	return best

## Objects the local player cannot see under the first-game fog are not picked.
func _fogged(item: Dictionary) -> bool:
	return ELFog.active(state, state.current_player) and not ELFog.shown(state, state.current_player, item)

func _click_ground(tile: Vector2i) -> void:
	var use_id := -1
	for id: int in state.objects:
		var item: Dictionary = state.objects[id]
		if id == _hero_id() or not item.alive or not item.visible or not item.enabled or not item.get("placed", true) or item.get("fortified", false) or item.group == "terrain_objects" or _fogged(item): continue
		var size: Vector2i = director.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
		if Rect2i(item.x, item.y, size.x, size.y).has_point(tile):
			use_id = id
			break
	var site := state.object(use_id)
	if state.map.profile.id == "el1" and not site.is_empty() and site.type == "hero" and site.owner == state.current_player:
		_select_hero(use_id)
		if tutorial_panel != null: tutorial_panel.map_click(site, false)
		return
	# An own mine or ether node takes no order and opens nothing (EL1
	# EL2 move-and-use has no action for it). An own fort is used
	# like any fort: entered when empty, left by its own garrison (EL2).
	if not site.is_empty() and ELResourceSites.TYPES.has(site.group) and site.owner == state.current_player: return
	var ordered := director.request_move(_hero_id(), tile, use_id)
	if not ordered: _remark(director.notice)
	else:
		_remark(director.notice)
		following = _hero_id()
	if tutorial_panel != null and _hero_id() >= 0: tutorial_panel.map_click(site, ordered)

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
	target += (a as Vector3) - (b as Vector3)
	var low := ELAdventureScene.world_position(-0.5, float(state.map.height) - 0.5)
	var high := ELAdventureScene.world_position(float(state.map.width) - 0.5, -0.5)
	target.x = clampf(target.x, low.x, high.x)
	target.z = clampf(target.z, low.z, high.z)
	_hide_touch_tip()
	_update_camera()

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
	return [["Save", KEY_F5], ["Load", KEY_F9]]

func _hide_touch_tip() -> void:
	if second_hud != null:
		map_tip.clear()
		second_hud.hide_map_tooltip()
	elif hud != null: hud.show_tooltip(-1, {}, Vector2.ZERO)

func _update_camera() -> void:
	if camera == null: return
	camera.size = zoom
	# Orthographic: far back, `zoom` units tall; perspective: `zoom` away.
	var reach := zoom if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 80.0
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * reach
	camera.look_at(target)
	state.camera_zoom = zoom
	state.camera_rotation = rad_to_deg(yaw)
	if hud != null: hud.set_view(target, yaw)

func _present(data: Dictionary) -> void:
	match data.kind:
		"spell_shop": _open_shop()
		"rune_shop", "el1_spell_shop":
			if global_spells != null: _close_global_spells()
			if building_message != null:
				deferred_shop = data
				return
			if data.kind == "rune_shop": _open_rune_shop()
			else: _open_first_shop()
		"actor_moving": world.move_actor(data.id, data.position, data.moving)
		"orient": world.orient_actor(data.id, data.direction)
		"route":
			if not director.strategy.is_empty(): following = data.id
			# Second game: the view goes with the main hero on a scripted walk,
			# as after the e2mission11 gate greeting (original captures).
			elif state.map.profile.id == "el2" and int(data.id) == state.main_hero and director.movement.get("queued", false) and not data.path.is_empty(): following = data.id
			_draw_route(data.path, data.id)
		"strategy_phase":
			if data.phase == "planning":
				following = _hero_id()
				_draw_route(ELStrategy.order_path(director, state.object(_hero_id())))
				_remark(director.notice if not director.notice.is_empty() else "Plan your heroes' orders, then end the turn.")
			else: _remark("Resolving " + str(data.phase) + "…")
			_refresh_hero_info()
		"dialogue":
			var speech: Dictionary = data.dialogue
			if state.map.profile.id == "el2" and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
				if text_view.is_empty(): text_view = {"zoom": zoom if view_goal.x < 0 else view_goal.x, "pitch": pitch if view_goal.x < 0 else view_goal.y}
				view_goal = Vector2(SECOND_TEXT_ZOOM, SECOND_TEXT_PITCH)
			if second_dialogue != null:
				second_dialogue.present(speech, state)
				accept = second_dialogue.accept
				decline = second_dialogue.decline
				_place_dialogue(speech)
				audio.speak(speech.text_id)
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
			if not text_view.is_empty():
				view_goal = Vector2(float(text_view.zoom), float(text_view.pitch))
				text_view = {}
				# Lines answered before the view moved leave nothing to ease back.
				if absf(zoom - view_goal.x) < 0.01 and absf(pitch - view_goal.y) < 0.001: view_goal = Vector2(-1, -1)
			dialogue_panel.hide()
			if second_dialogue != null: second_dialogue.hide()
			_dock_dialogue()
			audio.voice.stop()
			audio.voice.stream = null
		"CameraToObject": _focus_object(int(data.arguments[0]))
		"CameraToPos":
			following = -1
			target = ELAdventureScene.world_position(float(data.arguments[0]), float(data.arguments[1]))
		"CameraAttach": following = int(data.arguments[0]) if data.arguments[0] != null else -1
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
			if building_message != null:
				# The building's message is read before the battle it announces.
				deferred_encounter = data
				return
			if hud != null and precombat_preview:
				var number := 1
				var total := 1
				if director.strategy.get("phase") == "combat":
					number = int(director.strategy.index)
					total = director.strategy.combats.size()
				pending_encounter = [data.hero, data.opponent]
				hud.show_precombat(data.hero, data.opponent, number, total)
			elif second_precombat != null and precombat_preview: _open_second_precombat(data.hero, data.opponent)
			else: encounter_requested.emit(data.hero, data.opponent)
		"lose_battle": _open_lose_battle()
		"teleport", "dock":
			if data.hero == state.main_hero:
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
			building_messages.append(data)
			_show_building_message()

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

func _state_event(data: Dictionary) -> void:
	if data.kind in ["day_changed", "site_captured", "object_changed", "object_killed", "object_created", "skill_learned", "experience_gained"]: mana_readout = {}
	if world == null: return
	if audio != null: audio.script_event(data)
	if data.kind == "colorless_drain": colorless_drain(int(data.id))
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
			if spellbook != null and int(data.id) == spellbook.hero_id: spellbook.refresh()
		"global_spell_ready":
			if int(data.player) == state.current_player: _offer_global_spell()
		"specialization_learned":
			# The original reports a learned specialisation in a message box.
			_remark(data.text)
			building_messages.append({"kind": "building_message", "hero": data.id, "building": -1, "title": "", "text": data.text, "resources": [], "skill": "", "key": ""})
			_show_building_message()
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
				_second_mine_expired()
		"site_income":
			if data.player == state.current_player: _remark("Mine production · " + ELResources.describe(state.map.profile.id, data.amounts, false))
		"barrier_changed":
			# A first-game runestone sounds as its stones move away (instant.wav).
			if data.opened and presentation != null and world.first_barrier(state.object(data.id)): presentation.building_used(int(data.id), "instant")
		"object_changed", "object_killed", "object_created", "shape_changed":
			world.update_object(state.object(data.id))
			world.fog_object(state.object(data.id))
			_refresh_roster()
		"ExCameraScrollToObject": _focus_object(int(data.arguments[0]))
		"ExCameraScrollToPos":
			following = -1
			target = ELAdventureScene.world_position(float(data.arguments[0]), float(data.arguments[1]))
		"ExCameraRotate": yaw_goal = deg_to_rad(float(data.arguments[0]))
		# Script cameras: the original zoom units match the remake's (the second
		# game's camera distance); pitch is degrees below the horizon (negative
		# in scripts). Both are applied at once.
		"ExCameraZoom":
			zoom = clampf(float(data.arguments[0]), zoom_limits.x, zoom_limits.y)
			_set_standing(zoom, -1.0)
		"ExCameraPitch":
			pitch = clampf(deg_to_rad(absf(float(data.arguments[0]))), pitch_limits.x, pitch_limits.y)
			_set_standing(-1.0, pitch)
		"mission_finished":
			_remark(data.get("text", "Mission complete" if data.outcome == "win" else "Mission lost"))
			hall_record = str(data.get("hall_of_fame", ""))
			_show_result()
		"resources_collected":
			_remark("Collected " + ELResources.describe(state.map.profile.id, data.amounts, false))
			_first_pickup_box(data)
		"shop_captured": _first_capture_box(data)
		"experience_gained":
			if int(state.object(data.id).get("owner", -1)) != state.current_player: return
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
	if building_message != null:
		result_waiting = true
		return
	result_shown = true
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
	return true

## The original Options screen over the map (EL1 Options column wrench, EL2
## Esc menu Options). Its Save / Load / Main menu / Quit run once it closed;
## the second game's Esc menu stays open beneath it.
func open_original_options() -> void:
	if not _extras_ready():
		notice.text = "The original Options art is unavailable."
		return
	extras.settings = settings
	# First game: GOInfo opens the running mission's objectives.
	extras.mission_texts = ELFirstObjectivesScreen.mission_texts(state.map) if state != null and ELFirstObjectivesScreen.supports(state.map.profile) else {}
	if not extras.settings_previewed.is_connected(preview_volumes): extras.settings_previewed.connect(preview_volumes)
	open_extras("options", true, _original_options_closed, "adventure")

func _original_options_closed() -> void:
	apply_settings()
	match extras.options_ui.last_command:
		"GOSave": open_save_screen()
		"GOLoad": open_load_screen()
		"GOMenu": leave_requested.emit()
		"GOQuit": ELAudio.quiet_quit(get_tree())

## Options changed: the map takes the new values at once.
func apply_settings() -> void:
	if settings == null: return
	preview_volumes(settings.values)
	if world != null: world.set_animate_objects(bool(settings.values.get("animated_objects", true)))
	if world != null: world.set_animate_fog(bool(settings.values.get("fog_animations", true)))
	if world != null: world.set_blob_shadows(bool(settings.values.get("shadows", true)))
	if presentation != null: presentation.apply(settings.values)
	_apply_helper_overlay()

## Remake readouts of map events and refused orders. The original shows these
## in its message boxes, by the cancel cursor or not at all, so the status line
## repeats them only with the helper overlay; `remark` keeps the last one.
func _remark(text: String) -> void:
	remark = text
	# Without the original HUD art the status line is the only readout.
	if notice != null and (helper_overlay() or (hud == null and second_hud == null)): notice.text = text

## Second game: the scripted loot report (ExSendLootMessage /
## ExSendNoLootMessage) in the message box: T_MB_RECEIVE_LOOT over one line
## per spell and artifact, or T_MB_RECEIVE_NO_LOOT. The original shows the
## items as pictures with names; the remake lists the names.
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
	# The original queues the report behind the loot effect, so a battle's
	# experience box comes first; queue it after the current step.
	var message := {"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": "\n".join(PackedStringArray(lines)), "resources": [], "skill": "", "key": key}
	# Received loot uses the Messages panel: the title, then a picture and a name per item.
	if not data.get("none", false):
		message.text = lines[0]
		message.loot = items.duplicate(true)
	_queue_building_message.call_deferred(message)

func _queue_building_message(message: Dictionary) -> void:
	if ui == null: return
	building_messages.append(message)
	_show_building_message()

## Second game: a depleted own mine reports T_MB_MINE_EXPIRED in the message
## box (queues the message action when the counter reaches 0).
func _second_mine_expired() -> void:
	if state.map.profile.id != "el2" or second_hud == null: return
	var text := state.map.profile.text("T_MB_MINE_EXPIRED").strip_edges()
	building_messages.append({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": text, "resources": [], "skill": "", "key": "T_MB_MINE_EXPIRED"})
	_show_building_message()

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
	var profile := state.map.profile
	result_kind = "lost"
	if state.outcome == "win":
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, str(progress.get("current", ""))):
			error = campaign.error
			leave_requested.emit()
			return
		result_kind = ELSecondCampaign.complete_chapter(progress, ELSecondCampaign.capture(state), campaign.scenarios.size())
		if not ELSecondCampaign.write(ELSecondCampaign.AUTOSAVE, progress): push_warning("The campaign progress could not be autosaved.")
	result_progress = progress
	if result_kind in ["lost", "finished"] or ELSecondCampaign.chapter(profile, progress).is_empty():
		_leave_after_result()
		return
	campaign_map_requested.emit(progress)

func _focus_object(id: int) -> void:
	var item := state.object(id)
	if item.is_empty(): return
	following = -1
	target = ELAdventureScene.world_position(item.x, item.y)

## Guard zones end a drawn route in the first game, and for player 1's heroes
## in the second (route preview).
func _zones_stop(actor: Dictionary) -> bool:
	return state.map.profile.id == "el1" or state.map.profile.id == "el2" and int(actor.get("owner", -1)) == 1

func _draw_route(path: Array, actor_id := -1) -> void:
	if route == null: return
	var actor := state.object(_hero_id() if actor_id < 0 else actor_id)
	var zoned := _zones_stop(actor)
	if zoned: path = director.interception.preview(state, actor, path)
	if path.size() < 2:
		route.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var remaining := int(actor.get("ap", 0))
	for index in range(1, path.size()):
		remaining -= director.grid.passability(path[index])
		var color := Color("788587") if state.map.profile.id == "el1" and director.strategy.is_empty() and remaining < 0 else Color("f4da87")
		if zoned and not director.interception.enemies(state, actor, path[index]).is_empty(): color = Color("f07561")
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(ELAdventureScene.world_position(path[index - 1].x, path[index - 1].y) + Vector3(0, 0.12, 0))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(ELAdventureScene.world_position(path[index].x, path[index].y) + Vector3(0, 0.12, 0))
	if zoned and not director.interception.enemies(state, actor, path[-1]).is_empty():
		var stop := ELAdventureScene.world_position(path[-1].x, path[-1].y) + Vector3(0, 0.12, 0)
		var corners := [Vector3(-0.2, 0, 0), Vector3(0, 0, -0.2), Vector3(0.2, 0, 0), Vector3(0, 0, 0.2)]
		mesh.surface_set_color(Color("f07561"))
		for index in 4:
			mesh.surface_add_vertex(stop + corners[index])
			mesh.surface_add_vertex(stop + corners[(index + 1) % 4])
	mesh.surface_end()
	route.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	route.material_override = material
	route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## `scripted` is ExShowInventory: the script opens the main hero's inventory
## whatever the player is doing.
func _open_spellbook(scripted_hero := -1) -> void:
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
	spellbook = ELSecondInventoryView.make(second_hud) if second_hud != null else ELSpellbookView.new()
	scrim.add_child(spellbook)
	spellbook.build(state, shown)
	spellbook.closed.connect(_close_spellbook)
	if spellbook is ELSecondInventoryView:
		inventory_blinks = BlinkFrames.new()
		inventory_blinks.state = state
		var screen: ELSecondInventoryView = spellbook
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
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## Second game: the level-up dialog opens by itself for the local player's
## main hero once the map is idle and a skill choice waits (queues the
## level-up action, whose run shows it with victory.wav). Closing it
## without a choice brings it back on the next idle frame, as in the original.
func _auto_level_up() -> void:
	if second_hud == null or skills != null or paused or state.map.profile.id != "el2": return
	if not director.can_move() or not director.movement.is_empty() or not pending_encounter.is_empty() or not building_messages.is_empty(): return
	var hero := state.object(state.main_hero)
	if hero.is_empty() or not hero.get("alive", false) or int(hero.get("owner", -1)) != state.current_player or int(hero.get("skill_points", 0)) <= 0: return
	if ELHeroSkills.prepare(state.map.profile, hero).is_empty(): return
	_open_skills(state.main_hero)
	if skills != null and audio != null: audio.effect_sound("Adventure/victory.wav")

func _open_skills(for_hero := -1) -> void:
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
	scrim.add_child(skills)
	skills.build(state, shown)
	skills.closed.connect(_close_skills)

## First-game global spells screen; `prompt` opens the finished spell's prompt.
func open_global_spells(prompt := false) -> void:
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
	scrim.add_child(global_spells)
	global_spells.build(state, state.current_player)
	global_spells.closed.connect(_close_global_spells)
	if prompt: global_spells.open_prompt()

## First-game Diplomacy screen (DiplomacyMode).
func open_diplomacy() -> void:
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
	scrim.add_child(diplomacy)
	diplomacy.build(state, state.current_player)
	diplomacy.closed.connect(_close_diplomacy)
	tutorial_event("OPEN_DIPLOMACY_SCREEN")

func _close_diplomacy() -> void:
	if diplomacy == null: return
	diplomacy.get_parent().queue_free()
	diplomacy = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT

func _close_global_spells() -> void:
	if global_spells == null: return
	global_spells.get_parent().queue_free()
	global_spells = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	mana_readout = {}
	_refresh_hero_info()
	if global_spell_waiting: _offer_global_spell()

## A click on a spell in the adventure panel's list orders it without extra
## ether; a spell finished at once asks for its targets.
func _order_global_spell(code: String) -> void:
	if paused or not _can_act(): return
	ELGlobalSpells.produce(state, state.current_player, code)

## A finished spell asks to be applied once the map is free of other windows.
func _offer_global_spell() -> void:
	global_spell_waiting = true
	if global_spells != null:
		global_spell_waiting = false
		global_spells.refresh()
		global_spells.open_prompt()
		return
	if paused or building_message != null or not director.strategy.is_empty(): return
	global_spell_waiting = false
	open_global_spells(true)

func _close_skills() -> void:
	if skills == null: return
	skills.get_parent().queue_free()
	skills = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

## A building message pauses the night like the original message box; queued
## messages from the same night follow one another.
func _show_building_message() -> void:
	if building_message != null or building_messages.is_empty() or ui == null: return
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
	building_messages.append({"kind": "building_message", "hero": -1, "building": -1, "title": "", "text": state.map.profile.text("T_MB_TAKE_PLUHA_1"), "resources": [], "skill": "", "key": "T_MB_TAKE_PLUHA_1", "box": "first", "rows": rows})
	_show_building_message()

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
	building_message.get_parent().queue_free()
	building_message = null
	paused = false
	_refresh_hero_info()
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
			director.cancel_order(int(item.uid))
			_refresh_hero_info()
			return

func _hero_click(tile: Vector2i, exchange: bool) -> bool:
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

func open_hero_screen(id: int) -> void:
	var hero := state.object(id)
	if hero.is_empty() or not hero.alive or int(hero.owner) != state.current_player: return
	if id != _hero_id(): _select_hero(id)
	_open_hero_view([id], false)

func _open_hero_view(ids: Array[int], exchange: bool) -> void:
	if hero_screen != null or paused or hud == null: return
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
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	mana_readout = {}
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
	scrim.add_child(shop)
	shop.build(director.shop)
	shop.closed.connect(_close_shop)

func _open_rune_shop() -> void:
	if rune_shop != null or director.rune_shop == null or hud == null: return
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
	scrim.add_child(rune_shop)
	rune_shop.build_shop(director, hud, director.rune_shop)
	rune_shop.closed.connect(_close_rune_shop)

func _close_rune_shop() -> void:
	if rune_shop == null: return
	rune_shop.get_parent().queue_free()
	rune_shop = null
	director.rune_shop = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

func _open_first_shop() -> void:
	if first_shop != null or director.first_shop == null or hud == null: return
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
	scrim.add_child(first_shop)
	first_shop.build_shop(director, hud, director.first_shop)
	first_shop.closed.connect(_close_first_shop)

func _close_first_shop() -> void:
	if first_shop == null: return
	first_shop.get_parent().queue_free()
	first_shop = null
	director.first_shop = null
	paused = false
	if world != null: world.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_hero_info()

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
	notice = Label.new()
	ui.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_left = 24
	notice.offset_top = -203 if state.map.profile.id == "el1" else -167
	notice.offset_right = -24
	notice.offset_bottom = -175 if state.map.profile.id == "el1" else -139
	helper_hint = "Click to move or interact · WASD to pan · Right-drag to rotate · Wheel to zoom · H to follow your hero"
	if state.map.profile.id == "el1": helper_hint = "Select a hero · Click to plan a route or capture · N to end turn · Backspace to clear orders"
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
	hud.minimap_clicked.connect(func(cell: Vector2):
		following = -1
		target = ELAdventureScene.world_position(cell.x - 0.5, cell.y - 0.5))
	day_button = hud.dial.NextTurn
	day_button.pressed.connect(_end_day)
	hud.buttons.NextHero.pressed.connect(_next_hero)
	hud.buttons.HeroInTower.pressed.connect(func():
		hud.tower_only = not hud.tower_only
		_refresh_hero_info())
	leave_button = hud.buttons.RemoveHero
	leave_button.pressed.connect(func():
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
	cancel_button.pressed.connect(func(): director.cancel_order(_hero_id()))
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
	second_hud.centre_requested.connect(func(): following = _hero_id())
	second_hud.minimap_clicked.connect(func(cell: Vector2):
		if state.camera_locked: return
		following = -1
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
		cancel_button.pressed.connect(func(): director.cancel_order(_hero_id()))
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

## A script's distance or angle outlasts a speaker box's close view.
func _set_standing(distance: float, angle: float) -> void:
	if not text_view.is_empty():
		if distance > 0: text_view.zoom = distance
		if angle > 0: text_view.pitch = angle
	elif view_goal.x > 0: view_goal = Vector2(distance if distance > 0 else view_goal.x, angle if angle > 0 else view_goal.y)

func camera_state() -> Dictionary:
	# The standing view is saved, not a speaker box's close view.
	var standing := Vector2(zoom, pitch)
	if not text_view.is_empty(): standing = Vector2(float(text_view.zoom), float(text_view.pitch))
	elif view_goal.x > 0: standing = view_goal
	return {"yaw": yaw, "pitch": standing.y, "zoom": standing.x, "perspective": camera != null and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "target": [target.x, target.y, target.z], "following": following, "selected_hero": _hero_id(), "voice_position": audio.voice.get_playback_position() if audio != null and audio.voice.playing else 0.0}

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
	if not value: camera.current = true

## F5: the original quick save, the named slot T_QUICK_SAVE_NAME of this
## edition, overwritten without a question; T_GAME_SAVED confirms it.
func quick_save() -> void:
	if state.tutorial:
		notice.text = "The tutorial cannot be saved."
		return
	wait_cursor(state.map.profile)
	var error_text := ELSaveSlots.write(ELSaveSlots.quick_name(state.map.profile), director, camera_state())
	notice.text = state.map.profile.text("T_GAME_SAVED").strip_edges() if error_text.is_empty() else error_text

## F8 / F9: the quick load asks T_MB_LOAD_GAME first; OK resumes the quick
## save, Cancel or Esc keeps playing. Nothing happens without a quick save
## (or an old single-slot file) to load.
func ask_quick_load() -> void:
	if not FileAccess.file_exists(ELSaveSlots.quick_load_path(state)):
		notice.text = "There is no quick save to load."
		return
	if not _extras_ready():
		resume_requested.emit()
		return
	_after_extras = Callable()
	dragging = false
	extras.ask_hosted(state.map.profile.text("T_MB_LOAD_GAME").strip_edges(), func(): resume_requested.emit())
	extras_layer.show()
	extras.show()

## Options Save / Esc menu Save: SaveMissionScreen in save mode over the map
## (the quick save when the original art is missing).
func open_save_screen() -> void:
	if state.tutorial:
		notice.text = "The tutorial cannot be saved."
		return
	if not _open_save_list("save_game"): quick_save()

## Options Load / Esc menu Load: SaveMissionScreen in load mode over the map
## (the quick save when the original art is missing).
func open_load_screen() -> void:
	if not _open_save_list("load_game"): resume_requested.emit()

func _open_save_list(target: String) -> bool:
	if not _extras_ready(): return false
	extras.mission_load_ui.saver = func(name: String) -> String:
		wait_cursor(state.map.profile)
		return ELSaveSlots.write(name, director, camera_state())
	extras.mission_load_ui.current = ELSaveSlots.current_row(state)
	return open_extras(target, true, Callable(), ELSaveSlots.kind_of(state))

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

func _fail(message: String) -> bool:
	error = message
	return false
