extends Node3D
## Runtime composition: profile-owned content -> rules -> scene and controls.

const ACCENT := Color("e0af68")
const INK := Color("e5e3da")
const MUTED := Color("a8b4b1")
var profiles: Dictionary = {}
var profile: ELProfile
## Heading of the X dialog: ether for most spells, health for Channel.
var power_heading: Label
var duel: ELDuel
var stage: Node3D
var camera: Camera3D
var models: Dictionary = {}
var labels: Dictionary = {}
var homes: Dictionary = {}
var ui: Control
var header: HBoxContainer
var hand: HBoxContainer
## Right-button strip preview (see _right_button).
var strip_preview := -1
var right_down := false
var right_from := Vector2.ZERO
## The original list look for hand and artifact slots (ELListLook) and the
## layer behind the card rail that shows the frame tile in its empty slots.
var list_look: ELListLook
var list_look_profile: ELProfile
var hand_frames: Control
var status: Label
var phase_label: Label
var hero_buttons: Array[Button] = []
var end_button: Button
## The end-of-phase socket's original art and shutter, drawn under end_button
## (which keeps the text mode of the post-battle "Continue" control).
var end_face: ELCutPartButton
var attack_button: ELCutPartButton
## The battle tooltips in the original frame (ELCombatTooltip).
var combat_tip: ELCombatTooltip
## Auto combat: the computer plays the human side until stopped (CombatMenu3
## starts it, AutoCombatOff or CombatMenu3 again stops it).
var auto_combat := false
## Hot seat: the side whose player confirmed the hand-over box (-1 none yet)
## and whether a hand-over box is waiting.
var hot_side := -1
var hot_pending := false
var auto_button: ELCutPartButton
## The original game-menu button, top right: the first game's Options wrench
## (DisconnectButton art) or the second game's Esc-menu button. Right-click
## opens the remake menu. Without original art the text button stands in.
var game_menu_button: ELCutPartButton
var menu_button: Button
const GAME_MENU_ART := {"el1": ["DisconnectButton", Rect2(740, 279, 52, 49)], "el2": ["AdvPanelOptionsBtn", Rect2(595, 549, 56, 40)]}
var auto_off_button: ELCutPartButton
var profile_select: OptionButton
var mode_select: OptionButton
var log_text: RichTextLabel
var logs: Array[String] = []
var notice: Label
var selection := -1
## Hand rail cards seen at the last refresh ("side:key:card"), for the drop-in.
var _rail_seen := {}
var _rail_seen_side := -1
var _rail_seen_duel: WeakRef = null
var selection_power := 0
## The original X choice in the combat panel (ManaOk / ManaCancel /
## IncreaseMana / DecreaseMana); `power_amount` is its value.
var power_dialog: ELCombatManaPanel
var power_amount: Range
var power_preview: Label
var pending_power: Dictionary = {}
var exchange_target := -1
var selected_creature := -1
var ai_clock := 0.0
var demo := false
var updating := false
var launch_profile := "el1"
var capture_path := ""
var capture_after := 3.0
var elapsed := 0.0
var content_setup: ELContentSetup
var arena: ELArena
var hud: ELHudFrame
## Original Hand / Artifacts radio pair and the side counters (ELCombatRail).
var rail: ELCombatRail
var hud_root: Control
var hero_values: Array[Label] = []
var hero_names: Array[Label] = []
var portraits: Array[TextureRect] = []
var menu: PanelContainer
var card_scroll: ScrollContainer
var camera_yaw := -0.38
var camera_pitch := 0.7
var camera_distance := 24.0
## The named camera effect playing over the view, if any (see _start_shake).
var camera_shake := {}
## The orbit's centre; the original's default view sets it with the angles.
var camera_target := Vector3(0, 0.6, -0.5)
const PITCH_LIMITS := Vector2(0.3, 1.05)
const DISTANCE_LIMITS := Vector2(15, 40)
var orbiting := false
## Options AutoCamera: authored close-ups of casts, fights and the winner.
var auto_camera: ELAutoCamera
## Height above a framed figure's feet that the automatic camera keeps on screen.
const FRAMED_HEIGHT := 0.7
const EffectTable := preload("res://src/duel/combat_sound_table.gd")
const SharpenLayer := preload("res://src/render/sharpen_layer.gd")
## The current fight already had its chance of a close-up.
var fight_shot := false
## The local side's creatures in the last committed attack (the fight-over
## replay frames those still on the field).
var declared_attackers: Array[int] = []
## The side whose committed attack still waits for its declaration shot, or -1:
## both originals play it when the fight begins, after the defender's answer,
## at the attackers still on the field (none left, no shot).
var own_attack_pending := -1
## A hit hero shows in solid red for a moment.
const HERO_HIT_FLASH := Color(1.0, 0.25, 0.2)
var setup_panel: ELDuelSetup
var match_options: Dictionary = {}
var ability_selection: Dictionary = {}
var inspector: PanelContainer
var inspector_rows: VBoxContainer
var inspect_graveyard := false
var selection_ring: MeshInstance3D
var battle_audio: ELBattleAudio
var settings := ELSettings.new()
var settings_dialog: AcceptDialog
## The original Options screen over a battle (its own hosted front-end canvas).
var options_host: ELFrontMenu
var options_layer: CanvasLayer
var blood: ELCombatBlood
## Spell and summon particle effects (Effects.xml) of the running battle.
var effects: ELCombatEffects
## The cast whose effects start once its action has resolved:
## {card, side, target, affected: figure ids the action touched, hit: seconds
## until the figures it hits react, artifact: used from an artifact}.
var _effect_cast: Dictionary = {}
## Creatures a hero is summoning in the second game, hidden until the caster
## shot (or, without the automatic camera, the casting gesture) is over:
## {card, side, ids, since, camera, gesture, shown_at (-1 until the card's
## effect starts at them)}.
var _arrivals: Array[Dictionary] = []
## An ability's hit can wait for its own MonstersHit cue. RNST affects the
## opposing army, so the scope may hold several creature ids. The action's
## events remain synchronous; deferred hit timers retain their own data.
var _ability_hit: Dictionary = {}
## The EL2 damage reducer starts BlueFeedback on the protected hero before
## the reflected hit lands on the opposite hero.
## Like ability hit cues, this scopes only synchronous presentation events.
var _feedback_hit: Dictionary = {}
## EL2 BlackRedirect's authored Monster Hit cue (frame 25) belongs to the
## creature(s) absorbing the hero's damage, not to the protected hero.
var _redirect_hit: Dictionary = {}
## A trigger effect with its own hit cue (EL2 Pale Warp's PlaneWarp, frame
## 90): the victim's hit or death waits for it.
var _trigger_hit: Dictionary = {}
## Hit reactions waiting for their effect's cue frame, per figure id; the
## serial drops reactions of an earlier battle.
var _hits_waiting: Dictionary = {}
var _hit_serial := 0
## Live floating captions per figure, stacked so they never overlap.
var _floating: Dictionary = {}
var campaign_setup: ELCampaignSetup
var campaign_view: ELAdventureView
var front_layer: CanvasLayer
var front_menu: ELFrontMenu
## Start-up movies while they play (null afterwards).
var movie_layer: CanvasLayer
var movie_player: ELMoviePlayer
## Original Duel mode match in progress (ELDuelMatch); null outside it.
var duel_match: ELDuelMatch
## Plays combat resolution blow by blow (ELMeleePlayback); lives with the stage.
var melee: ELMeleePlayback
var front_line: Array[int] = []
## The Duel mode match's report (option VisualLog), or null.
var duel_report: ELDuelReport
var match_round_recorded := false
var match_clock := 0.0
var match_result_shown := false
var _match_starting := false
## Second-game combat tutorial (ELCombatTutorial) while its battle is shown.
var combat_tutorial: ELCombatTutorial
var tutorial_panel: ELCombatTutorialPanel
var tutorial_quit: ConfirmationDialog
## First game: the contextual tutorial panel over battles.
var first_tutorial: ELFirstTutorialPanel
## Second game: the original Esc menu in battle (Esc key).
var esc_menu: ELCombatEscMenu
## Second game: the Duel mode match's recording (Save duel replay) and the
## replay being played back (Duel -> Replay) with its TutPlayer panel.
var match_recording: ELDuelRecording
var replay_player: ELDuelReplayPlayer
var replay_panel: ELCombatTutorialPanel
var replay_quit: ConfirmationDialog
## The replay player's Inventory screen (RoundEndDuelScreen) and the hero it shows.
var replay_inventory: ELRoundEndDuelView
var replay_inventory_side := -1
## Seconds the finished round stays on screen before its result panel.
const ROUND_RESULT_DELAY := 1.6
## Original cursors (ELCursors): the character under the pointer when the
## pointer reached the battlefield rather than a panel, and the cursor asked for.
var combat_hover := -1
## Original combat readouts: figure numbers, icons and order marks; phase
## banners and cast messages.
var symbols: ELCombatSymbols
var notices: ELCombatNotices
## The opponent-turn banner shows once per opponent turn.
var _enemy_banner_shown := false
var _control_tips: Dictionary = {}
var cursor_name := ""

func _ready() -> void:
	# The window close button quits through ELAudio.quiet_quit (only when
	# this is the running game, not a scripted check).
	if get_tree().current_scene == self: get_tree().auto_accept_quit = false
	# The public name; the project name keeps the existing user-data folder.
	if get_tree().current_scene == self: get_window().title = "Demiurges"
	# The session marker and log lines for crash reports (the running game).
	if get_tree().current_scene == self and ELCrashReport.instance == null:
		var report := ELCrashReport.new()
		report.options_summary = _options_summary
		get_tree().root.add_child.call_deferred(report)
	settings.load_file()
	ELSettings.apply_display(get_viewport(), settings.values)
	# Touch gestures and the touch bar; inactive without a touch screen.
	add_to_group("touch_camera")
	add_child(ELTouchInput.new())
	# Options gamma over every screen (front end, map, battle, movies).
	var gamma := ELGammaLayer.new()
	gamma.settings = settings
	add_child(gamma)
	# Optional sharpening of the 3D scenes, under every interface layer.
	var sharpen: CanvasLayer = SharpenLayer.new()
	sharpen.settings = settings
	add_child(sharpen)
	# The game chosen last time starts again (unless the command line picks one).
	if settings.edition in ELContentLibrary.EDITIONS: launch_profile = settings.edition
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			launch_profile = arg.get_slice("=", 1)
		elif arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-after="):
			capture_after = float(arg.get_slice("=", 1))
		elif arg == "--demo":
			demo = true
	_load_profiles()
	_build_ui()
	if profiles.is_empty():
		status.text = "Choose a game folder to begin. Original content is required."
		if get_tree().current_scene == self and not demo and capture_path.is_empty(): _content_menu.call_deferred()
		return
	_start(launch_profile if profiles.has(launch_profile) else String(profiles.keys()[0]))
	# The original front end opens when the game itself is launched, after the
	# edition's start-up movies; scripted checks that instantiate this scene
	# keep the direct duel setup.
	if demo or not capture_path.is_empty(): return
	var launched := get_tree().current_scene == self
	if launched: _offer_crash_report.call_deferred()
	if launched and _play_startup_movies(): return
	if not (launched and _show_front_menu()): _open_setup()

## After a session that ended unexpectedly: the box to save or copy its report.
func _offer_crash_report() -> void:
	await get_tree().process_frame
	ELCrashReportBox.offer(ui)

## The player's options in a report: the remake settings that change drawing.
func _options_summary() -> String:
	var parts := PackedStringArray()
	for key: String in ["antialiasing", "sharpening", "terrain_detail", "shadows", "soft_shadows", "weather", "auto_camera", "helper_overlay"]:
		if settings.values.has(key): parts.append("%s=%s" % [key, settings.values[key]])
	return " ".join(parts)

## Start-up logos and intro of the launched edition (both originals play them
## before their first main menu, in silence otherwise); the menu follows when
## the last one ends or is skipped. False when there is nothing to show.
func _play_startup_movies() -> bool:
	if not ELMoviePlayer.enabled or ELMoviePlayer.mode == 0 or profile == null or not ELFrontMenu.supports(profile): return false
	var items := ELMoviePlayer.startup_items(profile)
	if items.is_empty(): return false
	movie_layer = CanvasLayer.new()
	movie_layer.layer = 20
	add_child(movie_layer)
	movie_player = ELMoviePlayer.new()
	movie_layer.add_child(movie_player)
	_pause_battle_audio(true)
	movie_player.finished.connect(func():
		movie_layer.queue_free()
		movie_layer = null
		movie_player = null
		if not _show_front_menu():
			_pause_battle_audio(false)
			_open_setup(), CONNECT_ONE_SHOT)
	movie_player.play_list(items)
	return true

func _exit_tree() -> void:
	ELMoviePlayer.shutdown()

## Android Back acts as Esc (close a window, cancel, open the game menu);
## the project does not quit on it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not get_tree().auto_accept_quit:
		if ELCrashReport.instance != null: ELCrashReport.instance.clean_exit()
		ELAudio.quiet_quit(get_tree())
		return
	if what != NOTIFICATION_WM_GO_BACK_REQUEST: return
	ELTouchInput.tap_key(KEY_ESCAPE)

func _load_profiles() -> void:
	var config := {}
	var local := "res://.local_profiles.json"
	if FileAccess.file_exists(local):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(local))
		if data is Dictionary: config.merge(data, true)
	# Installed folders the player chose on this computer.
	config.merge(ELContentLibrary.linked_folders(), true)
	for arg in OS.get_cmdline_user_args():
		for edition in ["el1", "el2"]:
			if arg.begins_with("--" + edition + "-path="):
				config[edition] = arg.trim_prefix("--" + edition + "-path=")
	for edition: String in config:
		var root: String = config[edition]
		if not root.is_absolute_path():
			root = ProjectSettings.globalize_path("res://").path_join(root)
		var data := ELProfile.new()
		if edition in ["el1", "el2"] and data.mount(edition, root):
			profiles[edition] = data
		else:
			push_warning(data.error)
	# Editions the player imported on this device (installer or data pack).
	var imported := ELContentLibrary.managed_roots()
	for edition: String in imported:
		if profiles.has(edition): continue
		var data := ELProfile.new()
		if data.mount(edition, imported[edition]):
			profiles[edition] = data
		else:
			push_warning(data.error)

func _start(edition: String, options: Dictionary = {}, restored: ELDuel = null, battle_seed := 212) -> void:
	if _campaign_battle() != null and restored != _campaign_battle():
		_notice("Finish or surrender the campaign battle first.")
		return
	# Any battle not started by the Duel mode match ends that match.
	if not _match_starting:
		duel_match = null
		_drop_duel_report()
	if combat_tutorial != null and (restored == null or restored != combat_tutorial.duel): _close_combat_tutorial()
	if replay_player != null and (restored == null or restored != replay_player.duel): _close_replay()
	if esc_menu != null: esc_menu.hide()
	var next_duel := restored if restored != null else ELDuel.new()
	if restored == null and not next_duel.start(profiles[edition], battle_seed, options):
		_notice(next_duel.error)
		return
	var kind := "campaign" if restored != null and restored == _campaign_battle() else ("restored" if restored != null else "duel")
	ELCrashReport.trace("battle start %s %s: %s" % [edition, kind, " vs ".join(next_duel.heroes.map(func(h: Dictionary) -> String: return "%s %s" % [h.get("faction", "?"), h.get("hero", "")]))])
	ELCrashReport.where("battle %s %s" % [edition, kind])
	if setup_panel != null: setup_panel.hide()
	if is_instance_valid(melee): melee.abort()
	melee = null
	own_attack_pending = -1
	if stage != null:
		remove_child(stage)
		stage.queue_free()
	models.clear()
	labels.clear()
	homes.clear()
	logs.clear()
	selection = -1
	selection_power = 0
	pending_power.clear()
	if power_dialog != null: _hide_power_panel()
	exchange_target = -1
	selected_creature = -1
	ability_selection.clear()
	ai_clock = 0
	auto_combat = false
	profile = profiles[edition]
	duel = next_duel
	match_options = duel.setup.duplicate(true)
	stage = Node3D.new()
	add_child(stage)
	arena = ELArena.new()
	stage.add_child(arena)
	_use_edition(edition)
	if not arena.build(profile, String(match_options.get("arena", "Green.001"))):
		status.text = "Arena failed: " + "; ".join(arena.errors)
		return
	arena.light.shadow_enabled = settings.values.shadows
	arena.light.shadow_blur = 2.0 if settings.values.soft_shadows else 1.0
	arena.set_detail(bool(settings.values.terrain_detail))
	blood = ELCombatBlood.new()
	stage.add_child(blood)
	blood.build(profile, arena, battle_seed, edition)
	blood.set_enabled(bool(settings.values.blood))
	effects = ELCombatEffects.new()
	stage.add_child(effects)
	effects.build(profile)
	effects.set_scene(arena.light, arena.environment_settings)
	_effect_cast = {}
	_arrivals.clear()
	_feedback_hit.clear()
	_redirect_hit.clear()
	_hits_waiting.clear()
	_hit_serial += 1
	battle_audio = ELBattleAudio.new()
	stage.add_child(battle_audio)
	battle_audio.build(profile, arena.definition, settings.values)
	if front_menu != null and front_menu.music_owned(): _pause_battle_audio(true)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.fov = auto_camera_angle()
	camera.current = true
	battle_audio.listener = camera
	auto_camera = ELAutoCamera.new(profile, battle_seed)
	_default_view()
	fight_shot = false
	ending = {}
	for side in 2:
		var model := ELModel.new()
		stage.add_child(model)
		var combatant: Dictionary = duel.heroes[side]
		var hero: Dictionary = profile.table("Shapes")[combatant.shape] if not String(combatant.get("shape", "")).is_empty() else profile.table("HeroTemplates")[combatant.template]
		if combatant.has("monster_name"): hero = ELFirstMonsters.appearance(profile, combatant.monster_name, combatant.monster_difficulty)
		var directory := "Creatures/" if combatant.get("kind", "hero") == "monster" else "Heroes/"
		if not model.build(profile, hero.Model, directory + hero.Texture, directory + hero.Texture2 if hero.has("Texture2") else ""):
			push_error(model.error)
		model.position = ELMeleePlayback.hero_position(side)
		model.scale = Vector3.ONE * hero_figure_scale(profile.id, String(hero.get("Model", "")))
		model.set_meta("sound_directory", hero.get("SndDir", ""))
		model.set_meta("skin_sound", hero.get("SkinSndType", ""))
		# Hero figures (he* models) speak their hits and casts from voice/.
		model.set_meta("voice", combatant.get("kind", "hero") != "monster" and String(hero.get("Model", "")).to_lower().begins_with("he"))
		model.set_meta("blood", hero.get("Blood", ""))
		model.position.y = arena.ground_height(model.position.x, model.position.z)
		model.rotation.y = _facing(side)
		models[side] = model
		homes[side] = model.position
		model.animation_finished.connect(_animation_done.bind(side))
		_hear_idle(model)
		effects.attach(model)
		if duel.phase == ELDuel.Phase.FINISHED:
			model.play(victory_clip(model) if duel.winner == side else "udeath")
		_add_label(side)
		portraits[side].texture = profile.card_icon(ELFirstMonsters.definition(profile, combatant.monster_name, combatant.monster_difficulty).Creature) if combatant.has("monster_name") else profile.portrait(int(hero.Face))
	hud.build(profile)
	symbols.build(profile)
	symbols.camera = camera
	notices.build(profile)
	_enemy_banner_shown = false
	auto_button.build(profile, "CombatMenu3", Rect2(619, 542, 47, 49))
	attack_button.build(profile, "CombatMenu1", Rect2(509, 542, 47, 49))
	end_face.build(profile, "CombatMenu2", Rect2(564, 544, 47, 46))
	for button: ELCutPartButton in [attack_button, auto_button, end_face]: button.set_process(true)
	combat_tip.setup(profile)
	auto_off_button.build(profile, "AutoCombatOff", Rect2(735, 10, 45, 44), "Type1")
	auto_off_button.visible = false
	var art: Array = GAME_MENU_ART.get(profile.id, [])
	if not art.is_empty(): game_menu_button.build(profile, art[0], art[1])
	game_menu_button.visible = not art.is_empty() and game_menu_button.has_art()
	menu_button.visible = not game_menu_button.visible
	rail.build(profile)
	if power_dialog != null: power_dialog.build(profile)
	_layout_hud()
	for c: Dictionary in duel.creatures.values(): _spawn_creature(c)
	selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.65
	ring.outer_radius = 0.72
	ring.rings = 32
	ring.ring_segments = 8
	selection_ring.mesh = ring
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = ACCENT
	selection_ring.material_override = ring_material
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(selection_ring)
	selection_ring.hide()
	front_line = []
	melee = ELMeleePlayback.new()
	melee.view = self
	stage.add_child(melee)
	duel.changed.connect(_refresh)
	duel.event.connect(_event)
	profile_select.select(0 if edition == "el1" else 1)
	_notice("Select a spell or a ready creature. Right-drag to orbit · Wheel to zoom · R resets the camera." if helper_overlay() else "")
	_refresh()
	# EL1 resolves global spells before models or the event listener
	# exist. Replay their original battle-opening effects after the figures
	# are ready, never on a loaded battle. LGWR strikes the opponent; HSTL
	# creates the owner's HOAM enchantment (original HOAM PosEnchantment).
	# FRGF casts a Tree Snake through the original opening spell factory; its
	# normal TRSN GreenSummon effect was also lost before view subscription.
	if restored == null and edition == "el1":
		for entry: Dictionary in duel.history:
			if entry.get("kind") != "global_spell": continue
			var recipient := -1
			var effect := ""
			match str(entry.get("spell", "")):
				"LGWR":
					recipient = 1 - int(entry.side)
					effect = "RedLightning"
				"HSTL":
					recipient = int(entry.side)
					effect = "PosEnchantment"
				"FRGF":
					for event_entry: Dictionary in duel.history:
						if event_entry.get("kind") != "summon": continue
						var creature: Dictionary = event_entry.get("creature", {})
						if str(creature.get("card", "")) != "TRSN" or int(creature.get("owner", -1)) != int(entry.side): continue
						recipient = int(creature.get("id", -1))
						effect = "GreenSummon"
						break
			if not effect.is_empty() and models.has(recipient):
				battle_audio.effect(effect)
				_figure_effect(effect, recipient)

var _melee_shown := false

func _process(delta: float) -> void:
	elapsed += delta
	_update_cursor()
	# The phase oval and the shutters follow a fight starting and ending.
	if duel != null and phase_label != null and _melee_busy() != _melee_shown:
		_melee_shown = _melee_busy()
		phase_label.text = phase_caption()
		_refresh_buttons()
	if _campaign_battle() != null and not campaign_view.director.watch_encounter().is_empty():
		# A chapter outcome reached during the duel ends the battle at once.
		_return_from_encounter()
		return
	if duel != null:
		ai_clock += delta
		if duel_match != null and duel.phase == ELDuel.Phase.FINISHED and not _melee_busy(): _watch_match_round(delta)
		if replay_player != null:
			# A duel replay plays its recorded actions at the battle's pace.
			if replay_player.playing and duel == replay_player.duel and not _overlay_open() and not _melee_busy() and ai_clock >= 0.85:
				ai_clock = 0.0
				replay_player.step()
		elif combat_tutorial != null:
			# The computer side replays its recorded commands.
			if duel.phase != ELDuel.Phase.FINISHED and not _overlay_open() and not _melee_busy() and ai_clock >= 0.85 and combat_tutorial.opponent_due():
				ai_clock = 0.0
				combat_tutorial.step_opponent()
		elif duel.phase != ELDuel.Phase.FINISHED and not _overlay_open() and not _melee_busy() and ai_clock >= 0.85 and (demo or (mode_select.selected == 0 and duel.active_side() == 1 and not _hot_seat()) or (auto_combat and _human_side())):
			ai_clock = 0.0
			# Without "use spells", auto combat uses no artifacts or spell charges (hero abilities stay).
			var auto := auto_combat and _human_side() and not demo
			ELPracticeAI.step(duel, auto and not bool(settings.values.get("use_spells", true)))
		_step_auto_camera(delta)
		_step_ending(delta)
		if not _arrivals.is_empty(): _step_arrivals()
		_step_shake(delta)
		var figures: Array = []
		# NumbersOnCamera off hides the figure marks while a close-up plays.
		var numbers := bool(settings.values.get("creature_numbers", true)) and not (auto_camera != null and auto_camera.active() and not bool(settings.values.get("numbers_on_camera", true)))
		for id: int in labels:
			if not models.has(id) or not is_instance_valid(models[id]):
				continue
			var label: Label3D = labels[id]
			var model: ELModel = models[id]
			var top := _numbers_point(model)
			if id < 2:
				# The hero panels show health; the floating readout is helper-only.
				label.text = "%d HP" % duel.heroes[id].health if helper_overlay() else ""
				var hero: Dictionary = duel.heroes[id]
				if numbers and duel.phase != ELDuel.Phase.FINISHED:
					figures.append({"id": id, "top": top, "numbers": ELCombatSymbols.number_row(0, int(hero.health), int(hero.health) < int(hero.get("maximum", hero.health)), true), "icons": [], "order": []})
			elif duel.creatures.has(id):
				var c: Dictionary = duel.creatures[id]
				# Remake-only state words (helper overlay); the original marks are glyphs.
				var parts: Array[String] = []
				if helper_overlay():
					if c.sick: parts.append("SUMMONED")
					elif c.resting: parts.append("RESTING")
				label.text = "  •  ".join(parts)
				label.modulate = ACCENT if not c.enchantments.is_empty() else INK
				# Pale aspect: the figure's opacity pulses 0.2-0.6 (1.8 s triangle wave).
				if duel.in_plane(id):
					if helper_overlay(): label.text += ("  •  " if not label.text.is_empty() else "") + "PALE"
					model.set_opacity(0.2 + 0.4 * (1.0 - absf(fmod(elapsed, 1.8) / 0.9 - 1.0)))
					model.set_meta("pale", true)
				elif model.get_meta("pale", false):
					model.set_opacity(1.0)
					model.set_meta("pale", false)
				# Options ShowCreatureNumbers (all rows), ShowIcons, ShowOrder.
				if numbers and model.visible:
					var blocked := int(duel.blocks.get(id, -1))
					figures.append({"id": id, "top": top,
						"numbers": ELCombatSymbols.number_row(int(c.power), int(c.toughness) - int(c.damage), int(c.damage) > 0, false),
						"icons": creature_icons(id) if bool(settings.values.get("ability_icons", true)) else [],
						"order": ELCombatSymbols.order_row(duel.attacks.find(id) + 1, duel.attacks.find(blocked) + 1 if blocked >= 0 else 0) if bool(settings.values.get("attack_order", true)) else []})
			label.position = top + Vector3(0, 0.35, 0)
		if is_instance_valid(symbols): symbols.figures = figures
		if is_instance_valid(selection_ring):
			selection_ring.visible = models.has(selected_creature) and not duel.entity(selected_creature).is_empty()
			if selection_ring.visible: selection_ring.position = models[selected_creature].position + Vector3(0, 0.08, 0)
	if not capture_path.is_empty() and elapsed >= capture_after:
		var output := capture_path
		capture_path = ""
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output)
		if duel != null:
			var report := FileAccess.open(output.get_basename() + ".json", FileAccess.WRITE)
			report.store_string(JSON.stringify({"state": duel.snapshot(), "events": duel.history,
				"models": models.size(), "profile_assets_read": profile.asset_reads}, "\t"))
		ELAudio.quiet_quit(get_tree())

func _input(event: InputEvent) -> void:
	# A move that a panel takes never reaches _unhandled_input: no character.
	if event is InputEventMouseMotion: combat_hover = -1
	# A release over a panel still ends the preview and the turn.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and right_down and duel != null:
		_right_button(event)

func _unhandled_input(event: InputEvent) -> void:
	if duel == null:
		return
	# The tutorial panel takes every key and click while it is open.
	if first_tutorial != null and first_tutorial.handle_input(event): return
	if event is InputEventMouseMotion: combat_hover = _character_at(event.position)
	if power_dialog != null and power_dialog.visible:
		# The X choice holds the battle: Enter takes the value, Esc cancels.
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER]: _confirm_power()
			elif event.keycode == KEY_ESCAPE: _cancel_power()
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and esc_menu != null and esc_menu.visible:
			_close_esc_menu()
			return
		if event.keycode == KEY_ESCAPE and _wants_esc_menu():
			_open_game_menu()
			return
		if event.keycode == KEY_ESCAPE:
			selection = -1
			selection_power = 0
			exchange_target = -1
			selected_creature = -1
			ability_selection.clear()
			_hint("Selection cancelled.")
			if setup_panel != null and setup_panel.visible: setup_panel.hide()
			_refresh()
		elif event.keycode == KEY_F5: _save_duel()
		elif event.keycode == KEY_F9: _load_duel()
		elif event.keycode == KEY_SPACE and (_human_turn() or ((_campaign_battle() != null or duel_match != null or combat_tutorial != null) and duel.phase == ELDuel.Phase.FINISHED and not _overlay_open())):
			_end_phase()
		elif event.keycode == KEY_R:
			_default_view()
		elif event.keycode == KEY_L:
			log_text.visible = not log_text.visible
		# The second game's radio tooltips name A and H as their keys.
		elif event.keycode in [KEY_A, KEY_H] and profile != null and profile.id == "el2" and rail != null and not _overlay_open():
			rail._select(event.keycode == KEY_A)
		# E and G choose the upper strip's list in the second game.
		elif event.keycode in [KEY_E, KEY_G] and profile != null and profile.id == "el2" and rail != null and not _overlay_open():
			rail.select_strip(event.keycode == KEY_G)
		# First game: H opens the tutorial.
		elif event.keycode == KEY_H and profile != null and profile.id == "el1" and not demo and not _overlay_open(): _first_tutorial_panel().open_history()
	if _overlay_open(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_right_button(event)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_distance = clampf(camera_distance + (-1.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.3), DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
			_update_camera()
	if event is InputEventMouseMotion and right_down: _right_button(event)
	if event is InputEventMouseMotion and orbiting:
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.005, PITCH_LIMITS.x, PITCH_LIMITS.y)
		_update_camera()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _human_turn():
		var nearest := _character_at(event.position)
		if nearest >= 0:
			_target(nearest)
			if event.double_click and nearest >= 2 and duel.phase == ELDuel.Phase.ATTACK and selection < 0 and ability_selection.is_empty():
				if not duel.toggle_attack(nearest): _hint(duel.error)

## The hero or creature drawn nearest a screen point (within 65 px), or -1.
func _character_at(at: Vector2) -> int:
	var nearest := -1
	var distance := 65.0
	if duel == null or camera == null: return nearest
	for id: int in models:
		if id >= 2 and not duel.creatures.has(id):
			continue
		var point := camera.unproject_position(models[id].position + Vector3(0, 0.7, 0))
		var d := point.distance_to(at)
		if d < distance:
			distance = d
			nearest = id
	return nearest

## Requests the original cursor for the battle or menu on screen. The
## adventure map, while shown, picks its own.
func _update_cursor() -> void:
	if profile == null or (campaign_view != null and campaign_view.visible): return
	var wanted := "default"
	if duel != null and profile.id == "el1" and not _overlay_open() and _human_turn():
		var pending := {}
		if selection >= 0 and selection < duel.heroes[duel.active_side()].hand.size(): pending = {"card": duel.heroes[duel.active_side()].hand[selection]}
		elif not ability_selection.is_empty():
			var definition: Dictionary = {"target": ability_selection.get("target", "")}
			for item: Dictionary in duel.abilities(int(ability_selection.source)):
				if item.key == ability_selection.key: definition = item
			pending = {"ability": definition, "source": int(ability_selection.source)}
		wanted = ELCursors.first_combat(duel, combat_hover, pending, selected_creature)
	cursor_name = wanted
	ELCursorDriver.request(profile, wanted)

## Touch gestures (remake addition) with the mouse camera's limits: one
## finger turns as a right drag does, two fingers turn, tilt and zoom.
func touch_camera_ready() -> bool:
	return duel != null and camera != null and camera.current and not _overlay_open() and not (campaign_view != null and campaign_view.visible)

func touch_pan(from: Vector2, to: Vector2) -> void:
	touch_orbit(-(to.x - from.x) * 0.006, (to.y - from.y) * 0.005)

func touch_orbit(turn: float, tilt: float) -> void:
	camera_yaw += turn
	camera_pitch = clampf(camera_pitch + tilt, PITCH_LIMITS.x, PITCH_LIMITS.y)
	_update_camera()

func touch_zoom(factor: float) -> void:
	camera_distance = clampf(camera_distance / factor, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_update_camera()

func touch_bar_keys() -> Array:
	return [["Camera", KEY_R]]

## The player's own view; any manual camera change ends an automatic close-up.
func _update_camera() -> void:
	if auto_camera != null: auto_camera.stop()
	camera.fov = auto_camera_angle()
	_place_orbit()

## This edition's battle view angle (vertical degrees).
func auto_camera_angle() -> float:
	return auto_camera.view_angle if auto_camera != null else (ELAutoCamera.SECOND_VIEW_FOV if profile != null and profile.id == "el2" else ELAutoCamera.VIEW_FOV)

## The player's standing view: the first game's original Default1 view
## (AutoCameraView 0), the second game's view from original footage, both from
## the player's side; the remake's orbit, zoom and R start from it.
func _default_view() -> void:
	var original: Dictionary = auto_camera.standing_view() if auto_camera != null else {}
	if original.is_empty(): original = {"target": Vector3(0, 0.6, -0.5), "yaw": -0.38, "pitch": 0.7, "distance": 24.0}
	camera_target = original.target
	camera_yaw = original.yaw
	camera_pitch = clampf(original.pitch, PITCH_LIMITS.x, PITCH_LIMITS.y)
	camera_distance = clampf(original.distance, DISTANCE_LIMITS.x, DISTANCE_LIMITS.y)
	_update_camera()

## A saved orbit, when the save has one; otherwise the default view stays.
func _restore_orbit(saved: Array) -> void:
	if saved.size() != 3: return
	camera_yaw = saved[0]
	camera_pitch = saved[1]
	camera_distance = saved[2]
	_update_camera()

func _place_orbit() -> void:
	var target := camera_target
	camera.position = target + Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(target)
	arena.clear_camera_view(camera.position, target)

## The size a hero-slot figure is drawn at (EL1, EL2): the
## second game draws every hero half as large again, and a figure that is not
## a hero model (a monster standing as the opposing side) a further quarter;
## the first game enlarges only those monster figures, by half.
static func hero_figure_scale(edition: String, model_name: String) -> float:
	var hero_model := model_name.to_lower().begins_with("he")
	if edition == "el2": return 1.5 * (1.0 if hero_model else 1.25)
	return 1.0 if hero_model else 1.5

func _facing(side: int) -> float:
	# The imported characters face local +Z, toward the opposing side after rotation.
	return PI / 2 if side == 0 else -PI / 2

func _target(id: int) -> void:
	if not _human_turn():
		return
	if not ability_selection.is_empty():
		if ability_selection.target == "enchantment":
			selected_creature = id
			inspect_graveyard = false
			_hint("Choose the enchantment to remove on the upper strip.")
		elif (ability_selection.get("key", "").begins_with("combine") or not str(ability_selection.get("second", "")).is_empty()) and not ability_selection.has("first"):
			var recycling: bool = str(ability_selection.get("key", "")).begins_with("recycle")
			if recycling and not duel.in_plane(id): _hint("Choose a creature in the Colourless Plane.")
			elif not recycling and (not duel.creatures.has(id) or duel.creatures[id].owner != duel.active_side()): _hint("Choose one of your creatures to sacrifice.")
			else:
				ability_selection.first = id
				_hint("Now choose a creature in the Ether to send away. Esc cancels." if recycling else ("Now choose a creature or hero to burn. Esc cancels." if ability_selection.get("second") == "any" else "Now choose the creature that receives its strength. Esc cancels."))
		elif ability_selection.has("first"):
			if duel.use_ability(ability_selection.source, ability_selection.key, ability_selection.first, id): ability_selection.clear()
			else: _hint(duel.error)
		elif ability_selection.target == "grave":
			if id < 2:
				selected_creature = id
				inspect_graveyard = true
				_hint("Choose a creature in this graveyard. Esc cancels.")
			else: _hint("Click a hero portrait to open that graveyard.")
		elif duel.use_ability(ability_selection.source, ability_selection.key, id, -1, int(ability_selection.get("amount", -1))):
			ability_selection.clear()
		else: _hint(duel.error)
	elif selection >= 0:
		var card: String = duel.heroes[duel.active_side()].hand[selection]
		var effect: String = ELCatalog.rule(profile, card).get("effect", "")
		if effect == "dispel":
			var invalid := duel._target_error(card, id)
			if not invalid.is_empty(): _hint(invalid)
			else:
				selected_creature = id
				inspect_graveyard = false
				_hint("Choose the enchantment to remove on the upper strip. Esc cancels.")
		elif effect == "trade" and exchange_target < 2:
			var invalid := duel._target_error(card, id)
			if not invalid.is_empty(): _hint(invalid)
			else:
				exchange_target = id
				_hint("Choose a character, then the enchantment to remove. Esc cancels.")
		elif effect == "trade":
			selected_creature = id
			inspect_graveyard = false
			_hint("Choose the enchantment to remove on the upper strip. Esc cancels.")
		elif effect == "swap" and exchange_target < 2:
			var invalid := duel._target_error(card, id)
			if not invalid.is_empty(): _hint(invalid)
			else:
				exchange_target = id
				_hint("Now choose the creature to destroy. Esc cancels.")
		elif effect == "swap":
			if duel.cast(selection, exchange_target, id):
				selection = -1
				exchange_target = -1
				_hint("Spell cast.")
			else: _hint(duel.error)
		elif effect == "pale_revival" and exchange_target < 2:
			# Pale revival: a creature in the plane, then a creature in either graveyard.
			var invalid := duel._target_error(card, id)
			if not invalid.is_empty(): _hint(invalid)
			elif duel.valid_grave_targets(card).is_empty(): _hint("No graveyard holds a creature to return.")
			else:
				exchange_target = id
				_hint("Now click a hero portrait and choose a creature in that graveyard. Esc cancels.")
		elif effect in ["reanimate", "repair", "pale_revival"]:
			if id >= 2: _hint("Click a hero portrait to open that graveyard.")
			else:
				selected_creature = id
				inspect_graveyard = true
				_hint("Choose a creature in this graveyard. Esc cancels.")
		elif effect == "exchange":
			var invalid := duel._target_error(card, id)
			if not invalid.is_empty(): _hint(invalid)
			elif duel.valid_grave_targets(card).is_empty(): _hint("Your graveyard contains no creature to return.")
			else:
				exchange_target = id
				selected_creature = duel.active_side()
				inspect_graveyard = true
				_hint("Choose the creature to return from your graveyard. Esc cancels.")
		elif duel.cast(selection, id, -1, selection_power):
			selection = -1
			selection_power = 0
			_hint("Spell cast.")
		else:
			_hint(duel.error)
	elif duel.phase == ELDuel.Phase.DEFENCE and selected_creature >= 2 and duel.creatures.has(selected_creature) and duel.creatures[selected_creature].owner == duel.active_side() and duel.attacks.has(id):
		if not duel.assign_block(selected_creature, id): _hint(duel.error)
	elif duel.phase == ELDuel.Phase.ATTACK and id == 1 - duel.attacker and selected_creature >= 2:
		if not duel.toggle_attack(selected_creature): _hint(duel.error)
	else:
		selected_creature = id
		inspect_graveyard = false
	_refresh()

func _cast_card(index: int) -> void:
	if not _human_turn():
		return
	var card: String = duel.heroes[duel.active_side()].hand[index]
	ability_selection.clear()
	exchange_target = -1
	selection_power = 0
	if duel.variable_power(card):
		selection = -1
		_open_power(index)
		_refresh()
		return
	if duel.target_kind(card) != "none":
		selection = -1 if selection == index else index
		var wanted := "hero portrait to open its graveyard" if duel.target_kind(card) == "grave" else duel.target_kind(card)
		_hint("Select a %s for %s. Esc cancels." % [wanted, duel.card_name(card)])
	else:
		if not duel.cast(index):
			_hint(duel.error)
		selection = -1
	_refresh()

func _open_power(index: int) -> void:
	var card: String = duel.heroes[duel.active_side()].hand[index]
	pending_power = {"duel": duel, "side": duel.active_side(), "turn": duel.turn_serial, "index": index, "card": card}
	power_heading.text = duel.card_name(card) + (" · health to pay (X)" if ELCatalog.rule(profile, card).get("x_source") == "health" else " · extra ether (X)")
	# Both games open the choice at the most the hero can pay (ether after
	# the card's cost); Channel, paid in health, opens at 1.
	var health: bool = ELCatalog.rule(profile, card).get("x_source") == "health"
	power_dialog.open(0, duel.maximum_power(card), 1 if health else duel.maximum_power(card))
	_preview_power()
	_show_power_panel()

func _preview_power(_value := 0.0) -> void:
	if pending_power.is_empty(): return
	if pending_power.has("ability"):
		power_preview.text = "Pay %d ether · %d left after use" % [int(power_amount.value), duel.available_mana(duel.active_side()) - int(power_amount.value)]
		return
	var card: String = pending_power.card
	var amount := int(power_amount.value)
	var channel_loss := duel.channel_cost(card) if amount > 0 else 0
	var rule := ELCatalog.rule(profile, card)
	var target_text: String = {"enemy": "Enemy creatures", "all": "All creatures", "ground": "All creatures without flying", "flying": "All flying creatures", "heroes": "Both heroes"}.get(rule.get("scope", "enemy"), "")
	if rule.effect == "damage": target_text = "A creature or hero of your choice"
	var result := "%d damage" % amount
	if rule.effect == "draw":
		target_text = "The chosen hero"
		result = "draws %d cards" % amount
	elif rule.effect == "enchant":
		target_text = "The chosen creature"
		result = ("+%d health" if rule.get("stat") == "toughness" else "+%d power") % amount
	if rule.get("x_source") == "health":
		# Channel pays X in health: X damage to the caster, X (+4 in the first game) ether, the opponent heals X.
		var side := duel.active_side()
		var gain := amount + (4 if profile.id == "el1" else 0)
		power_preview.text = "You take %d damage · opponent heals %d\n+%d ether · %d ether total\nAfter casting: %d health · %d ether" % [amount, amount, gain, duel.cost(card), duel.heroes[side].health - amount, duel.heroes[side].mana - duel.cost(card) + gain]
		return
	power_preview.text = "%s\n%s · %d ether total\nAfter casting: %d ether · %d channels" % [target_text, result, duel.cost(card) + amount, duel.heroes[duel.active_side()].mana - duel.cost(card) - amount, duel.heroes[duel.active_side()].channels - channel_loss]
	if duel.channel_cost(card) > 0: power_preview.text += "\nRequires %d channels; sacrifices them when X is greater than zero." % duel.channel_cost(card)

## Pay-X creature abilities reuse the spell power dialog.
func _open_ability_power(source: int, ability: Dictionary) -> void:
	pending_power = {"duel": duel, "side": duel.active_side(), "turn": duel.turn_serial, "source": source, "ability": ability}
	power_heading.text = str(ability.name) + " · ether to pay (X)"
	var available := duel.available_mana(duel.active_side())
	power_dialog.open(int(ability.get("minimum", 0)), available, available)
	_preview_power()
	_show_power_panel()

func _power_tooltip() -> void:
	if power_dialog.readout != null: power_dialog.readout.tooltip_text = power_heading.text + "\n" + power_preview.text

func _show_power_panel() -> void:
	_power_tooltip()
	phase_label.hide()
	power_dialog.show()
	power_dialog.layout()

func _hide_power_panel() -> void:
	power_dialog.close()
	phase_label.show()

func _confirm_power() -> void:
	var choice := pending_power.duplicate()
	pending_power.clear()
	_hide_power_panel()
	if choice.has("ability"):
		if choice.duel != duel or choice.side != duel.active_side() or choice.turn != duel.turn_serial or not _human_turn(): return
		var amount := int(power_amount.value)
		if choice.ability.target == "none":
			if not duel.use_ability(choice.source, choice.ability.key, -1, -1, amount): _hint(duel.error)
		else:
			ability_selection = {"source": choice.source, "key": choice.ability.key, "target": choice.ability.target, "amount": amount}
			_hint("%s · %d ether: choose a %s. Esc cancels." % [choice.ability.name, amount, "hero" if choice.ability.target == "hero" else str(choice.ability.target)])
		_refresh()
		return
	if choice.is_empty() or choice.duel != duel or choice.side != duel.active_side() or choice.turn != duel.turn_serial or not _human_turn(): return
	var cards: Array = duel.heroes[duel.active_side()].hand
	if choice.index >= cards.size() or cards[choice.index] != choice.card:
		_hint("The selected spell changed. Select it again.")
		_refresh()
		return
	selection_power = int(power_amount.value)
	if duel.target_kind(choice.card) == "none":
		if not duel.cast(choice.index, -1, -1, selection_power): _hint(duel.error)
		selection_power = 0
	else:
		selection = choice.index
		_hint("%s · %d damage. Select a creature or hero. Esc cancels." % [duel.card_name(choice.card), selection_power])
	_refresh()

func _cancel_power() -> void:
	pending_power.clear()
	selection = -1
	selection_power = 0
	_hide_power_panel()
	_hint("Spell selection cancelled.")
	_refresh()

func _human_turn() -> bool:
	return duel != null and replay_player == null and not demo and not auto_combat and not _overlay_open() and duel.phase != ELDuel.Phase.FINISHED and _human_side() and not hot_pending and not _melee_busy()

# --- Hot seat (MultiplayerStart -> HotSeat) -----------------------------------

## Both sides are local human players taking the screen in turn.
func _hot_seat() -> bool:
	return duel_match != null and duel_match.hot_seat and duel != null and replay_player == null and combat_tutorial == null and not demo

## Hand-over (EL1, EL2): whenever the
## side that must act changes, the hand, rail and selection are hidden and a
## modal box with OK names the next player; that player's hand and controls
## appear only after OK. No box while the same side continues. The remake
## also shows it at each round start and after loading a save.
func _check_handover() -> void:
	if not _hot_seat() or hot_pending or duel.phase == ELDuel.Phase.FINISHED: return
	if duel.active_side() == hot_side: return
	hot_pending = true
	selection = -1
	selection_power = 0
	exchange_target = -1
	selected_creature = -1
	ability_selection.clear()
	call_deferred("_show_handover")

## T_MB_HOT_SEAT_DUEL_WAIT ("player %d") while the side's name is the default
## hero caption, else T_MB_HOT_SEAT_DUEL_WAIT_COMBAT with the name.
func _handover_text(side: int) -> String:
	var name := String(duel_match.names[side]) if duel_match != null else ""
	var plain := profile.text("CtrlDUMyHero" if side == 0 else "CtrlDUEnemyHero")
	if name.is_empty() or name == plain: return profile.text("T_MB_HOT_SEAT_DUEL_WAIT").replace("%d", str(side + 1))
	return profile.text("T_MB_HOT_SEAT_DUEL_WAIT_COMBAT").replace("%s", name)

func _show_handover() -> void:
	if not hot_pending or duel == null: return
	var host := _battle_host()
	if host == null:
		_confirm_handover()
		return
	host.inform_hosted(_handover_text(duel.active_side()), _confirm_handover)
	options_layer.show()
	host.show()

func _confirm_handover() -> void:
	if not hot_pending: return
	hot_pending = false
	hot_side = duel.active_side() if duel != null else -1
	_refresh()

## The acting side is played from this screen (not by the practice opponent).
func _human_side() -> bool:
	return (mode_select.selected == 1 and combat_tutorial == null) or duel.active_side() == 0 or _hot_seat()

## Starts auto combat on the player's turn, or stops it at any time; starting
## cancels any half-made selection. Not offered in the recorded tutorial.
func _toggle_auto() -> void:
	if auto_combat:
		_set_auto(false)
	elif _human_turn() and combat_tutorial == null and not _hot_seat():
		selection = -1
		selection_power = 0
		exchange_target = -1
		selected_creature = -1
		ability_selection.clear()
		_set_auto(true)

func _set_auto(on: bool) -> void:
	auto_combat = on
	auto_off_button.visible = on
	_refresh()

func _end_phase() -> void:
	if _campaign_battle() != null and duel.phase == ELDuel.Phase.FINISHED:
		_return_from_encounter()
		return
	if duel_match != null and duel.phase == ELDuel.Phase.FINISHED:
		_continue_match()
		return
	if combat_tutorial != null and duel.phase == ELDuel.Phase.FINISHED:
		_leave_combat_tutorial()
		return
	selection = -1
	selection_power = 0
	exchange_target = -1
	selected_creature = -1
	ai_clock = 0.0
	ability_selection.clear()
	# Both original editions have separate own-attack declaration shots for
	# the group the player commits, not for each selection/recall click; the
	# shot itself waits for the fight (_auto_attack_own).
	var own_attack_side := int(duel.attacker)
	var committing: Array[int] = []
	if profile.id in ["el1", "el2"] and duel.phase == ELDuel.Phase.ATTACK and _local_side(own_attack_side):
		for id: int in duel.attacks:
			if models.has(id): committing.append(id)
	if not duel.end_phase():
		_hint(duel.error)
	elif not committing.is_empty():
		declared_attackers = committing
		own_attack_pending = own_attack_side

## The fight of the player's committed attack begins (its first blow is about
## to be shown): the declaration shot at the declared attackers still on the
## field. The first blow's AttackCombat shot follows it (_auto_fight).
func _auto_attack_own() -> void:
	var side := own_attack_pending
	own_attack_pending = -1
	# A fight of the other side's turn: the player's attackers never fought.
	if int(duel.attacker) != side or not _auto_camera_on(): return
	var middle := Vector3.ZERO
	var slots: Array[int] = []
	for id: int in declared_attackers:
		if duel.creatures.has(id) and models.has(id):
			middle += models[id].position
			slots.append(int(models[id].get_meta("slot", 0)))
	if slots.is_empty(): return
	auto_camera.attack_own(side, middle / slots.size(), int(settings.values.get("auto_camera_dynamics", 50)), slots)

func _spawn_creature(c: Dictionary) -> void:
	var original: Dictionary = profile.table("CombatCreatures")[c.card]
	var model := ELModel.new()
	stage.add_child(model)
	if not model.build(profile, original.Model, "Creatures/" + original.Texture, "Creatures/" + original.SecTexture if original.has("SecTexture") else ""):
		push_error(model.error)
	model.scale = Vector3.ONE * float(original.get("Scale", 1.0))
	model.set_meta("sound_directory", original.get("SndDir", ""))
	model.set_meta("attack_sound", original.get("AttackSndType", ""))
	model.set_meta("skin_sound", original.get("SkinSndType", ""))
	model.set_meta("blood", original.get("Blood", ""))
	var occupied: Array[int] = []
	for other: int in models:
		if other >= 2 and duel.creatures.has(other) and duel.creatures[other].owner == c.owner:
			occupied.append(int(models[other].get_meta("slot", 0)))
	var slot := 0
	while occupied.has(slot): slot += 1
	model.set_meta("slot", slot)
	# The original's arc of home slots; combat ordering lives only in ELDuel.
	model.position = ELMeleePlayback.slot_position(int(c.owner), slot, ELMeleePlayback.Line.HOME)
	model.position.y = arena.ground_height(model.position.x, model.position.z)
	# A new creature faces the centre of the arena.
	model.rotation.y = atan2(-model.position.x, -model.position.z)
	models[c.id] = model
	homes[c.id] = model.position
	model.animation_finished.connect(_animation_done.bind(c.id))
	model.frame_event.connect(_footfall.bind(c.id))
	_hear_idle(model)
	if is_instance_valid(effects): effects.attach(model)
	_add_label(c.id)

## A summoned figure's own entrance: its usummon clip and Summon sound.
func _enter(id: int) -> void:
	var summoned: ELModel = models[id]
	if summoned.has_clip("usummon") and summoned.play("usummon"):
		battle_audio.unit(summoned, "summon")

## Holds a hero's summon effects until the caster has been shown.
func _hold_arrival(pending: Dictionary) -> bool:
	var ids: Array[int] = []
	for id: int in pending.get("affected", []):
		if models.has(id) and models[id].get_meta("arriving", false): ids.append(id)
	if ids.is_empty(): return false
	var side := int(pending.side)
	var second := profile.id == "el2"
	_arrivals.append({"card": String(pending.card), "side": side, "ids": ids, "since": elapsed,
		"camera": second and auto_camera != null and auto_camera.showing_caster(),
		"gesture": (maxf(ELAutoCamera.cast_seconds(models[side].timing, "summon"), 0.0) if second else _summon_mark(side)) if models.has(side) else 0.0,
		"shown_at": -1.0})
	return true

## Seconds from the start of a hero's summoning gesture to its mark frame,
## where the first game starts the summoned creature's effect.
func _summon_mark(side: int) -> float:
	if bool(settings.values.get("hide_cast", false)): return 0.0
	var model: ELModel = models[side]
	var clip: Dictionary = model.timing.get("usummon", {})
	var mark := int(clip.get("mark", -1))
	return mark / (model.fps * maxf(model.speed, 0.01)) if mark > 0 else 0.0

## Starts held summon effects once the caster shot ends, and shows each
## creature at the effect's summon cue.
func _step_arrivals() -> void:
	for arrival: Dictionary in _arrivals.duplicate():
		var waited := elapsed - float(arrival.since)
		if float(arrival.shown_at) < 0.0:
			var caster_shown := bool(arrival.camera) and auto_camera != null and auto_camera.showing_caster()
			if (caster_shown or (not bool(arrival.camera) and waited < float(arrival.gesture))) and waited < 8.0: continue
			var targets: Array = []
			for id: int in arrival.ids:
				if models.has(id): targets.append(models[id])
			if is_instance_valid(effects) and not targets.is_empty():
				effects.cast(String(arrival.card), {"Start": [models.get(int(arrival.side))], "Target": targets})
			arrival.shown_at = elapsed + ELCombatEffects.summon_delay(profile, String(arrival.card))
		if elapsed < float(arrival.shown_at): continue
		_arrivals.erase(arrival)
		for id: int in arrival.ids:
			if not models.has(id): continue
			models[id].visible = true
			models[id].remove_meta("arriving")
			_enter(id)

## Declared attackers step out to their front-line slots; withdrawn ones
## walk back. Once blows are shown the playback brings everyone home.
func _step_front_line() -> void:
	if not is_instance_valid(melee): return
	var declared: Array[int] = []
	if not melee.busy() and duel.phase != ELDuel.Phase.FINISHED: declared.assign(duel.attacks)
	if not melee.busy():
		for id: int in declared:
			if not front_line.has(id): melee.step_out(id)
		for id: int in front_line:
			if not declared.has(id): melee.step_back(id)
	front_line = declared

## Combat playback (ELMeleePlayback): true while blows are still being shown.
func _melee_busy() -> bool:
	return is_instance_valid(melee) and melee.busy()

func _event(data: Dictionary) -> void:
	if own_attack_pending >= 0 and data.get("kind") == "strike" and not _melee_busy(): _auto_attack_own()
	# Blows and what follows them wait for the combat playback.
	if is_instance_valid(melee) and melee.capture(data): return
	if not _effect_cast.is_empty():
		if profile.id == "el1" and _effect_cast.card == "FRNT" and data.kind == "fury_result":
			_effect_cast.fury_attempts = int(data.get("attempts", 0))
			_effect_cast.fury_attacker = int(data.get("attacker", duel.attacker))
		if profile.id == "el2" and _effect_cast.card == "FRNT" and data.kind == "fury_result":
			_effect_cast.fury_deaths = int(data.get("deaths", 0))
			_effect_cast.fury_recipient = int(data.get("target", 1 - int(_effect_cast.side)))
		if data.kind == "forest_creature_cue" and _effect_cast.card in ["DNFR", "DRFR", "ANFR"]:
			_effect_cast.forest_targets.append(int(data.target))
		if profile.id in ["el1", "el2"] and _effect_cast.card == "FOGG" and data.kind == "fog_creature_cue":
			_effect_cast.fog_targets.append(int(data.target))
		if profile.id in ["el1", "el2"] and _effect_cast.card == "FRST":
			if data.kind == "firestorm_victim_cue":
				_effect_cast.firestorm_targets.append(int(data.target))
			elif data.kind == "firestorm_channel_cue":
				_effect_cast.firestorm_loss = int(data.get("amount", 0)) < 0 and int(data.get("side", -1)) == int(_effect_cast.side)
		if profile.id in ["el1", "el2"] and _effect_cast.card == "FRWA" and data.kind == "fire_wave_victim_cue":
			_effect_cast.fire_wave_targets.append(int(data.target))
		if profile.id in ["el1", "el2"] and _effect_cast.card == "LGST" and data.kind in ["lightning_storm_damage_cue", "lightning_storm_bless_cue"]:
			_effect_cast.lightning_sites.append({"target": int(data.target), "blessed": data.kind == "lightning_storm_bless_cue"})
		if profile.id in ["el1", "el2"] and _effect_cast.card == "WNFL" and data.kind == "winds_flame_victim_cue":
			_effect_cast.winds_flame_targets.append(int(data.target))
		if profile.id == "el2" and _effect_cast.card == "SNOV" and data.kind == "supernova_channel_cue":
			_effect_cast.supernova_loss = int(data.get("amount", 0)) == -1 and int(data.get("side", -1)) == int(_effect_cast.side)
		if profile.id == "el1" and _effect_cast.card == "SNOV" and data.kind == "supernova_global_cue":
			_effect_cast.supernova_global = int(data.get("side", -1)) == int(_effect_cast.side)
		if profile.id in ["el1", "el2"] and _effect_cast.card == "ANHL" and data.kind in ["annihilation_creature_cue", "annihilation_hero_cue"]:
			_effect_cast.annihilation_sites.append(int(data.target))
		if profile.id in ["el1", "el2"] and _effect_cast.card in ["CRHG", "RVHG"] and data.kind == "hunger_victim_cue":
			_effect_cast.hunger_sites.append(int(data.target))
		# Both original Tap Life callbacks (EL1, EL2)
		# skip their life-line/rune cues if damage failed, e.g. Feedback.
		# The untagged caster heal occurs only after successful damage;
		# unrelated ability/revival heals carry a card or spec field.
		if profile.id in ["el1", "el2"] and _effect_cast.card == "TPLF" and data.kind == "heal" and int(data.get("target", -1)) == int(_effect_cast.side) and not data.has("card") and not data.has("spec"):
			_effect_cast.tap_life_landed = true
			# The original DrainLife sound belongs to a successful hit, not the
			# earlier cast event. Play when that hit's heal is confirmed.
			if profile.id in ["el1", "el2"] and models.has(int(_effect_cast.side)) and models.has(1 - int(_effect_cast.side)):
				battle_audio.spell("TPLF", models[int(_effect_cast.side)],
					models[1 - int(_effect_cast.side)])
		var touched := int(data.creature.id) if data.kind == "summon" else int(data.get("target", -1))
		if data.kind in ["summon", "damage", "heal", "enchant", "disenchant", "death", "plane"] and touched >= 0 and not _effect_cast.affected.has(touched):
			_effect_cast.affected.append(touched)
		# A later action in the same frame no longer waits for the cast's cue.
		if data.kind in ["strike", "phase", "ability", "combat_ability"]: _effect_cast.hit = 0.0
	match data.kind:
		"summon":
			var c: Dictionary = data.creature
			_spawn_creature(c)
			# In both original editions Tree Snake GreenSummon's Target is the
			# newly created creature, which exists only after the cast event.
			# Queue its own WAV here instead of at the earlier hero cast.
			if profile.id in ["el1", "el2"] and _effect_cast.get("card", "") == "TRSN" and str(c.card) == "TRSN" and models.has(c.id):
				battle_audio.spell("TRSN", models.get(int(c.owner)), models[c.id])
			# Original figures in both editions may have their own usummon clip,
			# CreaturesPFX/<model>/summon.pfx and SndDir/Summon.wav, distinct
			# from the casting hero's voice and the colour summon effects.
			# Do not replay an entrance when rebuilding models from a save.
			# The second game's summoning hero finishes its gesture first, the
			# first game's reaches its gesture's mark; the creature then rises
			# in the card's effect at its own spot.
			if profile.id in ["el1", "el2"] and models.has(c.id) and not _effect_cast.is_empty() and String(_effect_cast.card) == String(c.card) and duel.is_summon(String(c.card)):
				models[c.id].visible = false
				models[c.id].set_meta("arriving", true)
			elif profile.id in ["el1", "el2"] and models.has(c.id):
				_enter(c.id)
			_log("%s summons %s." % [_side_name(c.owner), duel.card_name(c.card)])
		"cast":
			var animation := "usummon" if duel.is_summon(data.card) else ("uenchantment" if ELCatalog.rule(profile, data.card).get("effect") == "enchant" else "uinstant")
			# Options "Hide casting animations" skips the hero's gesture only.
			if not bool(settings.values.get("hide_cast", false)): models[data.side].play(animation)
			# The caster's own sound follows its cast animation; the card's effects start with it.
			battle_audio.unit(models[data.side], animation.trim_prefix("u"))
			# Original EL1 Fury registers GreenDamage only after it counts at
			# least one attempted creature hit. Its sound follows that cue too.
			if profile.id == "el1" and data.card == "FRNT":
				battle_audio.effect("GreenForceNature", models[data.side] if models.has(data.side) else null)
			elif profile.id == "el2" and data.card == "FRNT":
				# Original EL2 Draw is absent when Fury destroys no creature.
				# Queue its original audio alongside the conditional particle.
				battle_audio.effect("GreenForceNature", models[data.side] if models.has(data.side) else null)
			elif profile.id == "el1" and data.card == "ASLT":
				# Original Assault@ has one unconditional caster
				# PosSorcery; its other sounds belong to guarded army callbacks.
				battle_audio.effect("PosSorcery")
			elif profile.id in ["el1", "el2"] and data.card == "FLOD":
				# EL1 Flood@ and EL2 Flood@ register a single
				# caster NegEnchantment; guarded creature callbacks
				# EL1@ and EL2@ own their CantUntap sounds.
				battle_audio.effect("NegEnchantment")
			elif profile.id == "el1" and data.card == "ERBN":
				# EarthBondsEnchantment@ registers NegEnchantment
				# at its enchanted creature; @ separately registers
				# CantUntap for each creature of that holder's race.
				battle_audio.effect("NegEnchantment")
			elif profile.id == "el2" and data.card == "ERBN":
				# Original EL2 EarthBondsEnchantment attach@ queues
				# the chosen holder's NegEnchantment only; apply@
				# requests the separate creature CantUntap sounds per race match.
				battle_audio.effect("NegEnchantment")
			elif profile.id in ["el1", "el2"] and data.card == "SMOK":
				# Original SmokeEnchantment attach (EL1, EL2) registers one
				# caster NegEnchantment. Its separate guarded creature modifier
				# @ requests CantUntap only for applicable figures.
				battle_audio.effect("NegEnchantment")
			elif profile.id in ["el1", "el2"] and data.card == "CNAR":
				# Original CondensedAirEnchantment attach (EL1, EL2) requests
				# only caster NegEnchantment; the @ creature callback
				# supplies individual CantUntap sounds for eligible flyers.
				battle_audio.effect("NegEnchantment")
			elif profile.id in ["el1", "el2"] and data.card == "MDBL":
				# Both originals play their named FX/sound for each
				# hero whose post-shield hand-size damage is positive.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "FOGG":
				# BlueFog is unconditional; the original CantAttack callback
				# supplies one creature-bound cue/sound for each live figure.
				battle_audio.effect("BlueFog")
			elif profile.id == "el2" and data.card == "ENLH" and int(data.get("enlightenment_count", -1)) == 0:
				# Original ENLH has no Discard/Draw sites if its hand is empty.
				# The hero's own casting-gesture sound still plays above.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "BRRL" and int(data.get("broken_reality_ether", 0)) <= 0:
				# Both original callbacks bypass LoseMana and BlackDamage
				# registrations for zero ether; the cast gesture still plays.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "FRST":
				# Both originals register Firestorm FX/audio at conditional
				# wave/victim sites rather than an unconditional cast (X=0).
				# EL2 alone adds the caster channel-loss effect.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "FRWA":
				# Both original Fire Waves play one caster Start wave and
				# separate victim-bound damage effects/audio, not a generic
				# sound on an empty opposing board.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "LGST":
				# Both original Lightning Storms branch per living creature: damage
				# gets RedLightning, Storm Mastery rescue gets three positive
				# stat effects. Neither is an unconditional cast sound.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "WNFL":
				# Both originals queue Fireball and FireballExpl for each
				# affected flying creature, never a generic caster sound.
				# X=0 and an empty eligible set have no named FX/audio.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "SNOV":
				# Both originals skip RedSuperNova for X=0; EL2 alone
				# registers an additional LoseMana after channel payment.
				# Neither named sound belongs to the unconditional cast.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "ANHL":
				# Both originals' per-creature/positive-opposing-hero registrations
				# supply the original FX sound, not a generic once-per-cast cue.
				pass
			elif profile.id in ["el1", "el2"] and data.card in ["CRHG", "RVHG"]:
				# Both originals queue one Hunger effect/sound per positive-power
				# victim, not one unconditional caster sound.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "GRUN":
				# Both original GreaterUnsummon callbacks queue BlueDeath/Draw
				# separately for EACH creature it actually returns, not once
				# unconditionally at the casting hero.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "DPGS":
				# Original EL1 and EL2
				# separate caster cues from the creature callback's
				# creature-bound negative attack/rune cues on each affected
				# figure. No unconditional NegAttack sound at an empty board.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "DRGS":
				# Both original Drowsy Gas versions have separate caster and per-creature FX
				# registrations; sound follows those sites, not the generic cast.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "FRGS":
				# Both originals' Frenzy Gas have separate caster and creature
				# effect sites; the named audio follows those actual figure sites.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "TRSN":
				# Source GreenSummon sound belongs to the newly created Target
				# model; the summon event starts it when the figure exists.
				pass
			elif profile.id in ["el1", "el2"] and data.card == "REPR":
				# Original Repair in both editions binds BlackDamage to the
				# opposing hero; the own-grave action target is not that source.
				battle_audio.spell(data.card, models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id == "el2" and data.card == "JRRG":
				# Original Juryrig puts BlackDamage at the opposing hero. The
				# untargeted revive action has no model for its audio source.
				battle_audio.spell(data.card, models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id in ["el1", "el2"] and data.card == "AMNS":
				# Both originals use two hero-bound Discard sounds. EL2 alone
				# adds caster Draw; a generic sound loses one Discard instance.
				battle_audio.amnesia(models.get(0), models.get(1), models.get(int(data.side)))
			elif profile.id in ["el1", "el2"] and data.card == "PWTP":
				# Both original Powertap versions start DrainMana at opposing donor
				# finishes at the caster, even though the card has no selected target.
				battle_audio.spell(data.card, models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id == "el2" and data.card == "INCR":
				# INCR removes an opposing channel. The owner LoseMana Target
				# sound source follows that affected hero, not the no-target cast.
				battle_audio.spell(data.card, models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id in ["el1", "el2"] and data.card == "CHNL":
				# Both original Channels pay life on the caster but place
				# GainLife at the opposing hero; bind that WAV source.
				battle_audio.spell(data.card, models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id == "el2" and data.card == "MNBR":
				# EL2 Mana Breeze queues a GainMana sound at EACH hero's Target,
				# not one generic sound at the caster.
				battle_audio.mana_breeze(models.get(int(data.side)),
					models.get(1 - int(data.side)))
			elif profile.id in ["el1", "el2"] and data.card == "TPLF":
				# Original Tap Life in both editions registers DrainLife/runes only
				# after positive damage. The cast event precedes the untagged
				# heal, whose event handler starts the genuine bound sound.
				pass
			else:
				battle_audio.spell(data.card, models.get(int(data.side)), models.get(int(data.get("target", -1))))
			# Particles start after the action resolves, when the figures it
			# touched (a summoned creature, the damaged ones) are known.
			_pend_cast_effects(data, false)
			if not data.get("script", false): _cast_notice(int(data.side), String(data.card))
			# First game: the local player's cast by spell class.
			if profile.id == "el1" and not demo and (data.side == 0 or mode_select.selected == 1 or _hot_seat()):
				var spell_class := str(profile.table("CombatSpells").get(data.card, {}).get("Class", ""))
				if ELFirstTutorial.CAST_EVENTS.has(spell_class): _first_tutorial_panel().fire(ELFirstTutorial.CAST_EVENTS[spell_class])
		"damage", "death":
			if not _hit_later(data): _show_hit(data)
		"exile":
			# Both original Exile effects (EL1@, EL2@)
			# bind BlackExile to their selected Target. Their shipped
			# Monsters Hit callback is frame 90 (30 fps): keep the original
			# creature model as the effect anchor until then, although the
			# creature has already left gameplay state. Other exiles clean up
			# just after the deferred cast effects receive their target.
			var id := int(data.target)
			var delay := 0.0
			if profile.id in ["el1", "el2"] and _effect_cast.get("card", "") == "EXIL" and int(_effect_cast.get("target", -1)) == id:
				delay = float(_effect_cast.get("hit", 0.0))
			if delay > 0.0 and models.has(id) and is_inside_tree():
				_hits_waiting[id] = int(_hits_waiting.get(id, 0)) + 1
				get_tree().create_timer(delay).timeout.connect(_finish_exile.bind(id, _hit_serial))
			else:
				call_deferred("_remove_model", id)
		"heal":
			_float_number(data.target, -int(data.amount))
			if data.get("skill") == "REGN": _log("%s regenerates 1 health." % _side_name(data.target))
			# Complicity's regeneration hook (EL1, EL2)
			# plays GainLife once at each healed holder's hero.
			if data.get("card") == "COPL" and profile.id in ["el1", "el2"] and models.has(int(data.target)):
				battle_audio.effect("GainLife")
				_figure_effect("GainLife", int(data.target))
		"aura_cue":
			var covered := int(data.target)
			if models.has(covered):
				for effect: String in EffectTable.AURA_EFFECTS.get(String(data.card), []):
					battle_audio.effect(effect, models[covered])
					_figure_effect(effect, covered)
		"bat_drain_cue":
			# Vampire Bat (EL1, EL2):
			# DrainLife runs from the opposing hero to the bats' own hero.
			var bat_side := int(data.side)
			if models.has(bat_side) and models.has(1 - bat_side):
				battle_audio.effect("DrainLife")
				if is_instance_valid(effects):
					effects.play("DrainLife", {"Start": [models[1 - bat_side]], "Finish": [models[bat_side]]})
		"spwb_gain_life_cue":
			# Original EL2 Spiritual Web graveyard callback
			# queues one GainLife particle and authored sound at the owning
			# hero per active copy, not at the dead creature or its controller.
			if profile.id == "el2" and models.has(int(data.side)):
				battle_audio.effect("GainLife")
				_figure_effect("GainLife", int(data.side))
		"wtlk_el1_gain_life_cue":
			# EL1 Water Link left-play – registers a
			# Target/GainLife at each link owner before possible reanimation,
			# not at the departing creature, its controller or grave origin.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("GainLife")
				_figure_effect("GainLife", int(data.side))
		"wtlk_el2_gain_life_cue":
			# EL2 Water Link - independently registers
			# original Target/GainLife on each owning hero on death to grave,
			# regardless of the later optional return of the creature.
			if profile.id == "el2" and models.has(int(data.side)):
				battle_audio.effect("GainLife")
				_figure_effect("GainLife", int(data.side))
		"baso_death_draw_cue":
			# EL1 BASO left-play registers Target/Draw at the
			# departing creature's current controller, not the BASO caster,
			# enchantment holder, original owner or dead model.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"baso_el2_death_draw_cue":
			# Original EL2 BASO slot6 queues its own Target/Draw
			# on the departing creature's current controller, after the
			# unchanged per-copy card draw. EL1 has a separate original slot.
			if profile.id == "el2" and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"disturbance":
			# EL1's turn entry plays RedLightning at the damaged hero only when
			# the ether disturbance is positive (before hero damage);
			# EL2 binds it the same way.
			if profile.id in ["el1", "el2"] and int(data.amount) > 0 and models.has(int(data.side)):
				battle_audio.effect("RedLightning")
				_figure_effect("RedLightning", int(data.side))
			_log("Ether disturbance deals %d damage to %s." % [data.amount, _side_name(data.side)])
		"mind_blast_cue":
			# EL1 - and EL2 -
			# visit hero 0 then 1. Each successful
			# positive hit gets its own original Target effect and sound;
			# the generic caster-bound spell playback is suppressed below.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				battle_audio.effect("BlueMindBlast", models[int(data.target)])
				_figure_effect("BlueMindBlast", int(data.target))
		"turn_stasis":
			# Start-of-turn global Stasis marker (EL1 -, EL2).
			if profile.id in ["el1", "el2"] and models.has(int(data.side)):
				battle_audio.effect("BlueStasis", models[int(data.side)])
				_figure_effect("BlueStasis", int(data.side))
		"turn_pos_rune":
			# Positive player-modifier indicator (EL1 -, EL2).
			if profile.id in ["el1", "el2"] and models.has(int(data.side)):
				battle_audio.effect("PosRune")
				_figure_effect("PosRune", int(data.side))
		"turn_neg_rune":
			# Negative player-modifier indicator (EL1 -, EL2).
			if profile.id in ["el1", "el2"] and models.has(int(data.side)):
				battle_audio.effect("NegRune")
				_figure_effect("NegRune", int(data.side))
		"turn_creature_pos_rune", "turn_creature_neg_rune":
			# Per-creature modifier rune indicators (EL1 -, EL2).
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				var name := "PosRune" if data.kind == "turn_creature_pos_rune" else "NegRune"
				battle_audio.effect(name)
				_figure_effect(name, int(data.target))
		"attack_tax_effect":
			# The attack assignment's nonzero mana tax, at the attacker
			# (EL1, EL2).
			var taxed := int(data.get("target", data.side))
			if profile.id in ["el1", "el2"] and models.has(taxed):
				battle_audio.effect("LoseMana")
				_figure_effect("LoseMana", taxed)
		"war_banner_shift":
			# EL1 / EL2: the live creature entry/exit
			# callback plays signed attack/defence effects at affected Target.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				var prefix := "Pos" if int(data.amount) > 0 else "Neg"
				for name: String in [prefix + "Attack", prefix + "Defence"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"walking_horror_hit":
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				battle_audio.effect("BlackDamage")
				_figure_effect("BlackDamage", int(data.target))
		"bless_expire":
			# EL1 - and EL2 detach effects
			# target the creature losing WandOfBless's temporary +4/+4;
			# Bless and Combine's turn-end removal plays the same three.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				for name: String in ["NegAttack", "NegDefence", "NegRune"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"devour_growth":
			# EL2 Devourer1/2Enchantment attach binds
			# Target to the Devourer that killed its prey.
			if models.has(int(data.target)):
				for name: String in ["PosAttack", "PosDefence", "PosRune"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"lightning_storm_bless_expire":
			# EL1@ and EL2@ both queue three negative
			# Target effects at the former +3/+3 recipient.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				for name: String in ["NegAttack", "NegDefence", "NegRune"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"twisted_decay", "overload_decay":
			# Both originals' Twisted Enhancement (EL1, EL2)
			# and Overload (EL1, EL2) end-of-turn callbacks
			# play three Target-bound cues on the decaying creature.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				for name: String in ["NegAttack", "NegDefence", "NegRune"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"alpha_strike_death":
			# AlphaStrikeEnchantment removal (EL1, EL2) ends
			# with BlackDeath at its holder, before the ordinary death
			# animation/removal.
			if profile.id in ["el1", "el2"] and models.has(int(data.target)):
				battle_audio.effect("BlackDeath")
				_figure_effect("BlackDeath", int(data.target))
		"quick_fix_return":
			# QuickFixEnchantment leave-play callback (EL1, EL2
			# ): card returns to the enchantment caster and Draw plays
			# at Target.
			if profile.id in ["el1", "el2"] and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"delusion_return":
			# EL2 DelusionEnchantment leave-play callback:
			# each returned Delusion draws an original particle/audio cue at
			# its caster even if another player controlled its creature.
			if profile.id == "el2" and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"mana_vortex_cue":
			# EL1 original MNTX creature-spell callback emits
			# Target/GainMana on the enchanted hero, not the summoner.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("GainMana")
				_figure_effect("GainMana", int(data.side))
		"sacr_mana_gain_cue":
			# EL1 SACR activated-ability original registers
			# GainMana on its casting hero after sacrifice and ether change.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("GainMana")
				_figure_effect("GainMana", int(data.side))
		"sptr_upkeep_cue":
			# Original EL1 SPTR uses GreenDamage for each turn-start
			# enchantment callback at the current paying hero, not its caster.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("GreenDamage")
				_figure_effect("GreenDamage", int(data.side))
		"stsi_upkeep_draw_cue":
			# Original EL1 STSI registers a separate Target/Draw
			# during its own owner's turn-start upkeep callback.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"eten_return_draw_cue":
			# EL1 Eternal Enchantment: successful
			# dispel return queues Target/Draw at the enchantment's caster.
			if profile.id == "el1" and models.has(int(data.side)):
				battle_audio.effect("Draw")
				_figure_effect("Draw", int(data.side))
		"script_cast":
			# Battle scripts cast silently and for free; name the spell so the effect reads.
			_float_text(data.side, duel.card_name(data.card), Color("c9a6ff"), true)
			_log("A battlefield power casts %s for %s." % [duel.card_name(data.card), _side_name(data.side)])
		"script_card":
			_log("A battlefield power gives %s to %s." % [duel.card_name(data.card), _side_name(data.side)])
		"script_unsupported":
			_log("Scripted spell %s is not supported yet and has no effect." % duel.card_name(data.card))
		"channels":
			_log("%s %s %d ether channels." % [_side_name(data.side), "gains" if data.amount > 0 else "loses", absi(data.amount)])
		"ether":
			_log("%s %s %d ether." % [_side_name(data.side), "gains" if data.amount > 0 else "loses", absi(data.amount)])
		"upkeep":
			_log("%s pays %d ether for %s." % [_side_name(data.side), data.amount, duel.card_name(data.card)])
		"trigger":
			# Both original SFGS end-turn callbacks bind BlackDamage at each
			# affected victim. Other trigger sounds remain unbound.
			if profile.id in ["el1", "el2"] and String(data.card) == "SFGS":
				battle_audio.trigger(data.card, models.get(int(data.target)))
			else:
				battle_audio.trigger(data.card)
			if is_instance_valid(effects) and models.has(data.target):
				var owner := int(data.target) if int(data.target) < 2 else int(duel.entity(data.target).get("owner", 0))
				if profile.id == "el2" and String(data.card) == "PLWP":
					var delay := ELCombatEffects.effect_hit_delay(profile, "PlaneWarp")
					if delay > 0.0:
						_trigger_hit = {"target": int(data.target), "hit": delay}
						call_deferred("_clear_trigger_hit")
				if data.has("source") and models.has(int(data.source)):
					# A drawn-from figure (Mechozaurus drain): Start there, Finish at the target.
					effects.trigger(data.card, {"Start": [models[int(data.source)]], "Finish": [models[data.target]], "Target": [models[data.target]]})
				else:
					effects.trigger(data.card, {"Target": [models[data.target]], "Start": [models.get(1 - owner)]})
			var target_name := _side_name(data.target) if data.target < 2 else duel.card_name(duel.entity(data.target).get("card", ""))
			_log("%s deals %d damage to %s." % [duel.card_name(data.card), data.amount, target_name])
		"skill":
			var skill := ELHeroSkills.definition(profile, data.skill, int(duel.heroes[data.side].skills[data.skill]))
			_log("%s draws an extra spell with %s." % [_side_name(data.side), profile.text(str(skill.get("Name", data.skill)))])
		"enchant":
			_float_text(data.target, "%+d / %+d" % [data.power, data.toughness] if data.power != 0 or data.toughness != 0 else duel.card_name(data.card), Color("91dcc2"), true)
			# EL1 CombineEnchantment@ and EL2@ each
			# queue four original Target effects on the surviving combined
			# creature, not on the hero receiving the initial CMBN card.
			if profile.id in ["el1", "el2"] and String(data.card) == "CMBN" and int(data.target) >= 2 and models.has(int(data.target)):
				for name: String in ["PosAttack", "PosDefence", "Trample", "PosRune"]:
					battle_audio.effect(name)
					_figure_effect(name, int(data.target))
		"unsummon":
			# EL1 Unsummon@, LesserUnsummon@ and
			# EL2 Unsummon@, LesserUnsummon@ bind BlueDeath to the departing
			# creature and Draw to its owner.
			# Play the queued cast effects
			# first, while the creature model still exists as an FX anchor.
			# Game-state removal remains synchronous in both editions.
			var unsummon_fx: bool = profile.id in ["el1", "el2"] and _effect_cast.get("card", "") in ["UNSM", "LSUS"]
			if profile.id in ["el1", "el2"] and _effect_cast.get("card", "") == "GRUN":
				# The original mass callback queues each creature's own BlueDeath
				# and its ORIGINAL owner's Draw before removing the model.
				# The event's owner may instead be a temporary controller.
				var creature_id := int(data.target)
				var original_owners: Dictionary = _effect_cast.get("grun_original_owners", {})
				_effect_cast.grun_sites.append({"creature": creature_id,
					"owner": int(original_owners.get(creature_id, data.get("owner", -1)))})
				call_deferred("_remove_model", creature_id)
			elif unsummon_fx and int(_effect_cast.get("target", -1)) == int(data.target):
				_effect_cast.return_owner = int(data.get("owner", -1))
				call_deferred("_remove_model", int(data.target))
			else:
				_remove_model(data.target)
		"plane":
			battle_audio.effect("OutPlaneEntry" if data.enter else "OutPlaneExit")
			_figure_effect("OutPlaneEntry" if data.enter else "OutPlaneExit", data.target)
			_float_text(data.target, "Pale aspect" if data.enter else "Manifests", Color("c9d4dd"), true)
			_log("%s %s the Colourless Plane." % [duel.card_name(duel.entity(data.target).get("card", "")), "enters" if data.enter else "leaves"])
		"spec":
			_float_text(data.side, _spec_name(data.spec), Color("e8c66a"), true)
			_announce("T_SPEC_WORKED", [_spec_name(data.spec), _hero_name(data.side)], int(data.side))
		"global_spell":
			var spell := profile.text(str(profile.table("GlobalSpells").get(data.spell, {}).get("Name", data.spell)))
			_float_text(data.side, spell, Color("9fc4ff"), true)
			_log("Global spell %s of %s takes effect." % [spell, _side_name(data.side)])
		"dissipate":
			_log("%s dissipates instead of dying." % duel.card_name(duel.entity(data.target).get("card", "")))
		"lifeguard":
			battle_audio.effect("LifeguardAbility")
			_figure_effect("LifeguardAbility", data.target)
			_float_text(data.target, "Protected", Color("91dcc2"), true)
		"regenerate":
			battle_audio.effect("RegenEffect")
			_figure_effect("RegenEffect", data.target)
			_float_text(data.target, "Regeneration", Color("91dcc2"), true)
		"disenchant":
			_float_text(data.target, "Disenchanted", Color("91dcc2"), true)
			_log("%s is removed." % duel.card_name(data.card))
		"artifact":
			_announce("T_USE_ARTIFACT", [_hero_name(data.side), str(data.get("title", duel.card_name(data.card)))], int(data.side))
			# The artifact's own effects (its spell's cast visual), without the hero's cast gesture.
			# Both originals register WRBN hero PosEnchantment once; original
			# per-creature PosAttack/PosDefence effects and WAV belong to each
			# positive-kin non-exempt target, not the general spell sound list.
			if profile.id in ["el1", "el2"] and data.card == "WRBN":
				battle_audio.effect("PosEnchantment")
			else:
				battle_audio.spell(data.card)
			_pend_cast_effects(data, true)
		"ability":
			# A hero's ability comes from an enchantment on it (T_USE_ENCHANTMENT);
			# a creature's is its own (T_USE_ABILITY).
			var source := int(data.get("source", data.side))
			if source < 2: _announce("T_USE_ENCHANTMENT", [_hero_name(source), String(data.get("name", String(data.ability).capitalize()))], int(data.side))
			else: _announce("T_USE_ABILITY", [duel.card_name(duel.entity(source).get("card", ""))], int(data.side))
			_ability_effects(data)
			_auto_ability(data)
		"trigger_cue":
			# A trigger's original effect without damage (Outer Cripple's draw).
			battle_audio.trigger(data.card)
			if is_instance_valid(effects) and models.has(int(data.target)):
				effects.trigger(data.card, {"Target": [models[int(data.target)]]})
		"camera_cue":
			_auto_cue(data)
		"combat_ability":
			_combat_ability(data)
		"redirect":
			# The hero's damage leaves it for each creature that takes it instead.
			battle_audio.effect(EffectTable.REDIRECT)
			var shields: Array = []
			for id: int in data.get("creatures", []):
				if models.has(id): shields.append(models[id])
			if is_instance_valid(effects) and models.has(data.target) and not shields.is_empty():
				effects.play(EffectTable.REDIRECT, {"Start": [models[data.target]], "Finish": shields})
			if profile.id == "el2" and not shields.is_empty():
				var delay := ELCombatEffects.effect_hit_delay(profile, EffectTable.REDIRECT)
				if delay > 0.0:
					_redirect_hit = {"targets": data.creatures.duplicate(), "hit": delay}
					call_deferred("_clear_redirect_hit")
		"feedback":
			battle_audio.effect(EffectTable.FEEDBACK)
			_figure_effect(EffectTable.FEEDBACK, int(data.target))
			# Both originals give BlueFeedback a MonstersHit cue at frame 10.
			# Only the reflected hit presentation waits; health is already settled.
			if profile.id in ["el1", "el2"] and int(data.target) in [0, 1]:
				var delay := ELCombatEffects.effect_hit_delay(profile, EffectTable.FEEDBACK)
				if delay > 0.0:
					_feedback_hit = {"target": 1 - int(data.target), "hit": delay}
					call_deferred("_clear_feedback_hit")
		"chain_mirror":
			# Original EL2 Ethereal Chain creates RedDamage at the *receiving*
			# hero, before the reflected hit. Game-state damage is unchanged.
			if profile.id == "el2" and models.has(int(data.target)):
				battle_audio.effect("RedDamage")
				_figure_effect("RedDamage", int(data.target))
		"barrier":
			battle_audio.effect(EffectTable.BARRIER)
			_figure_effect(EffectTable.BARRIER, int(data.target))
		"stoneskin":
			battle_audio.effect(EffectTable.STONESKIN)
			_figure_effect(EffectTable.STONESKIN, int(data.target))
		"strike":
			# The combat playback presents held blows itself.
			if is_instance_valid(melee): return
			if not fight_shot and models.has(data.from) and models.has(data.to): _auto_fight(int(data.from), int(data.to))
			if models.has(data.from) and models.has(data.to):
				var model: ELModel = models[data.from]
				battle_audio.unit(model, "attack")
				battle_audio.hit(model, models[data.to])
				model.play("uattack")
				var start: Vector3 = homes[data.from]
				var destination: Vector3 = models[data.to].position
				var tween := model.create_tween()
				tween.tween_property(model, "position", start.lerp(destination, 0.6), 0.26)
				tween.tween_property(model, "position", start, 0.36)
		"phase":
			fight_shot = false
			selection = -1
			selection_power = 0
			exchange_target = -1
			selected_creature = -1
			_phase_notice(int(data.side), String(data.phase) == "attack", int(data.round))
		"victory":
			_bleed(1 - data.side)
			# Both editions' defeated heroes have original udeath and their
			# own SndDir/death.wav. A lethal hero emits a result event, not
			# creature death, so _show_hit does not start this figure sound.
			if profile.id in ["el1", "el2"]: battle_audio.unit(models[1 - int(data.side)], "death")
			models[1 - data.side].play("udeath")
			# The winner's clip, camera and fanfare follow once the death
			# clip ends (_step_ending).
			_begin_ending(int(data.side))
			if combat_tutorial != null: _tutorial_result()
			else: _hint("%s wins. Start a new duel or change game profile." % _side_name(data.side))
			_log("%s wins the duel." % _side_name(data.side))
		"duel_draw":
			for side in 2:
				_bleed(side)
				# Each edition's fallen figure has its own original death sound;
				# a mutual lethal result does not emit creature death events.
				if profile.id in ["el1", "el2"]: battle_audio.unit(models[side], "death")
				models[side].play("udeath")
			_begin_ending(-1)
			selection = -1
			selection_power = 0
			_hint("Both heroes have fallen. The duel is a draw.")
			_log("The duel ends in a draw.")

## The original phase notices (EL1, EL2): the local side's
## attack shows the attack banner and announces the turn number; its defence
## shows the defence banner; the opponent's phases show «ХОД ПРОТИВНИКА» once
## until the local side attacks again. Option CombatPhases gates the banners.
func _phase_notice(side: int, attack: bool, round_number: int) -> void:
	var local := _local_side(side)
	var band := -1
	if local:
		band = 0 if attack else 1
		if attack:
			_enemy_banner_shown = false
			_announce("T_TURN_NUMBER", [round_number], -1)
	elif not _enemy_banner_shown:
		band = 2
		_enemy_banner_shown = true
		# Second game: the opponent's cast icons clear when its turn begins.
		if attack and is_instance_valid(notices): notices.clear_icons()
	if band >= 0 and bool(settings.values.get("combat_phases", true)) and is_instance_valid(notices): notices.show_banner(band)

## Whether `side` is played at this screen (both sides in a local two-player battle).
func _local_side(side: int) -> bool:
	return side == 0 or _hot_seat() or (mode_select != null and mode_select.selected == 1 and combat_tutorial == null)

## A hero's cast: T_CASTING in the log; the first game also lists it on screen,
## the second shows the opponent's spell icon at the top left.
func _cast_notice(side: int, card: String) -> void:
	if profile.id == "el2":
		_log(_format_text("T_CASTING", [_hero_name(side), duel.card_name(card)]))
		if not _local_side(side) and is_instance_valid(notices): notices.add_icon(profile.card_icon(card))
		return
	_announce("T_CASTING", [_hero_name(side), duel.card_name(card)], side)

## The hero's name in the original messages: its own title, the hot-seat
## player's name, else the first game's duel captions «Ваш герой» /
## «Герой противника».
func _hero_name(side: int) -> String:
	if duel != null and duel.heroes[side].has("title"): return str(duel.heroes[side].title)
	if _hot_seat() and not String(duel_match.names[side]).is_empty(): return String(duel_match.names[side])
	var caption := _original_text("CtrlDUMyHero" if side == 0 else "CtrlDUEnemyHero", "")
	return caption if not caption.is_empty() else _side_name(side)

## An original message text with its %s / %d fields filled in order.
func _format_text(key: String, args: Array) -> String:
	var text := _original_text(key, key)
	for value: Variant in args:
		var at := text.find("%")
		while at >= 0 and at + 1 < text.length() and not text[at + 1] in ["s", "d"]: at = text.find("%", at + 1)
		if at < 0 or at + 1 >= text.length(): break
		text = text.substr(0, at) + str(value) + text.substr(at + 2)
	return text.strip_edges()

## The first game's message list (options CastMessages and ShowChat): own side
## teal, opponent red, the turn number gold; every message also goes to the log.
func _announce(key: String, args: Array, side: int) -> void:
	var text := _format_text(key, args)
	_log(text)
	if profile.id != "el1" or not is_instance_valid(notices): return
	if not bool(settings.values.get("heroes_casting", true)) or not bool(settings.values.get("show_chat", true)): return
	var colour := Color8(0xff, 0xda, 0x45) if side < 0 else (Color8(0x00, 0xde, 0xc6) if _local_side(side) else Color8(0xff, 0x00, 0x00))
	notices.add_line(text, colour)

## Starts the pending cast's particles. Start = the casting hero; the target
## point = the chosen target, else the figures the cast touched, else the
## caster; effects without points sit at the arena origin.
## Starts the previous pending cast's effects and makes `data` (a cast or an
## artifact use) the pending one. Hits of a non-summon wait for the cue frame
## of the card's effect.
func _pend_cast_effects(data: Dictionary, artifact: bool) -> void:
	if _effect_cast.is_empty(): call_deferred("_start_cast_effects")
	else: _start_cast_effects()
	var card := String(data.card)
	var hit := 0.0 if duel.is_summon(card) else ELCombatEffects.hit_delay(profile, card)
	_effect_cast = {"card": card, "side": data.side, "target": int(data.get("target", -1)), "affected": [], "hit": hit, "artifact": artifact, "power": int(data.get("power", 0)), "tap_life_landed": false}
	if profile.id in ["el1", "el2"] and card == "GRUN":
		# Snapshot original ownership before synchronous mass removal. An
		# enchantment may have lent a creature to the other controller.
		_effect_cast.grun_original_owners = {}
		_effect_cast.grun_sites = []
		for creature: Dictionary in duel.creatures.values():
			_effect_cast.grun_original_owners[int(creature.id)] = duel.origin(int(creature.id))
	if profile.id in ["el1", "el2"] and card == "FRST":
		_effect_cast.firestorm_targets = []
		_effect_cast.firestorm_loss = false
	if profile.id in ["el1", "el2"] and card == "FRWA":
		_effect_cast.fire_wave_targets = []
	if profile.id in ["el1", "el2"] and card == "LGST":
		_effect_cast.lightning_sites = []
	if profile.id in ["el1", "el2"] and card == "WNFL":
		_effect_cast.winds_flame_targets = []
	if profile.id == "el2" and card == "SNOV":
		_effect_cast.supernova_loss = false
	if profile.id == "el1" and card == "SNOV":
		_effect_cast.supernova_global = false
	if profile.id in ["el1", "el2"] and card == "ANHL":
		_effect_cast.annihilation_sites = []
	if profile.id in ["el1", "el2"] and card in ["CRHG", "RVHG"]:
		_effect_cast.hunger_sites = []
	if profile.id == "el1" and card == "FRNT":
		_effect_cast.fury_attempts = 0
		_effect_cast.fury_attacker = int(duel.attacker)
	if profile.id == "el2" and card == "FRNT":
		_effect_cast.fury_deaths = 0
		_effect_cast.fury_recipient = 1 - int(data.side)
	if profile.id in ["el1", "el2"] and card == "FOGG":
		_effect_cast.fog_targets = []
	if card in ["DNFR", "DRFR", "ANFR"]:
		_effect_cast.forest_targets = []
	if profile.id == "el2" and card == "CANV":
		_effect_cast.devour_power = int(data.get("devour_power", 0))
	if profile.id == "el2" and card == "ENLH":
		_effect_cast.enlightenment_count = int(data.get("enlightenment_count", -1))
	if profile.id in ["el1", "el2"] and card == "BRRL":
		_effect_cast.broken_reality_ether = int(data.get("broken_reality_ether", 0))
	if profile.id in ["el1", "el2"] and card == "TRAD":
		var second := int(data.get("second", -1))
		_effect_cast.second = second
		# Snapshot the second creature's controller before synchronous destruction.
		_effect_cast.beneficiary = int(duel.creatures[second].owner) if duel.creatures.has(second) else -1

## A damaged or dying figure's reaction during a cast whose effect marks a cue
## frame waits for that frame. False when it shows at once.
func _hit_later(data: Dictionary) -> bool:
	var delay := float(_effect_cast.get("hit", 0.0))
	var id := int(data.get("target", -1))
	# EL2 RodofColossus@- applies nine damage to its
	# selected figure and one to the rest of that figure's side, but queues
	# just ONE ColosusLeg Target. The original MonstersHit@14
	# belongs only to that selected figure; splash victims have no impact
	# cue and must react immediately. Game-state damage is already settled.
	if bool(_effect_cast.get("artifact", false)) and _effect_cast.get("card", "") == "RDCL" and id != int(_effect_cast.get("target", -1)):
		delay = 0.0
	if int(_ability_hit.get("target", -1)) == id or _ability_hit.get("targets", []).has(id):
		delay = float(_ability_hit.get("hit", 0.0))
	if int(_feedback_hit.get("target", -1)) == id:
		delay = float(_feedback_hit.get("hit", 0.0))
	if _redirect_hit.get("targets", []).has(id):
		delay = float(_redirect_hit.get("hit", 0.0))
	if int(_trigger_hit.get("target", -1)) == id:
		delay = float(_trigger_hit.get("hit", 0.0))
	# A creature that falls to its own ability (Fingus spores, Final Courtesy)
	# finishes the action the original queues before its death.
	if data.kind == "death" and models.has(id) and models[id].clip == "uinstant" and models[id].playing:
		var actor: ELModel = models[id]
		delay = maxf(delay, (actor.clip_frames() - actor.frame) / (actor.fps * actor.speed))
	if delay <= 0.0 or not models.has(id) or not is_inside_tree(): return false
	_hits_waiting[id] = int(_hits_waiting.get(id, 0)) + 1
	get_tree().create_timer(delay).timeout.connect(_late_hit.bind(data, _hit_serial))
	return true

func _clear_feedback_hit() -> void:
	_feedback_hit.clear()

func _clear_redirect_hit() -> void:
	_redirect_hit.clear()

func _clear_trigger_hit() -> void:
	_trigger_hit.clear()

func _late_hit(data: Dictionary, serial: int) -> void:
	if serial != _hit_serial: return
	var id := int(data.target)
	_hits_waiting[id] = int(_hits_waiting.get(id, 0)) - 1
	if int(_hits_waiting[id]) <= 0: _hits_waiting.erase(id)
	_show_hit(data)

func _finish_exile(id: int, serial: int) -> void:
	if serial != _hit_serial: return
	_hits_waiting.erase(id)
	_remove_model(id)

## A figure's hit (clip, sound, number) or death (blood, clip, removal).
func _show_hit(data: Dictionary) -> void:
	var id := int(data.target)
	if not models.has(id): return
	var model: ELModel = models[id]
	if data.kind == "damage":
		# A hero already lying defeated keeps its death pose.
		if not (id < 2 and duel.phase == ELDuel.Phase.FINISHED):
			battle_audio.unit(model, "hit")
			model.play("uhit")
			if id < 2: model.flash(HERO_HIT_FLASH, 0.1)
		_float_number(id, int(data.amount))
		return
	_bleed(id)
	battle_audio.unit(model, "death")
	if labels.has(id): labels[id].hide()
	if not model.play("udeath"): _remove_model(id)

func _start_cast_effects() -> void:
	var pending := _effect_cast
	_effect_cast = {}
	# Tremor and Earthquake also queue the named camera effect "Tremor1"
	# (EL1, EL2): a shake over the
	# current view, with or without the automatic camera.
	if profile.id in ["el1", "el2"] and pending.get("card", "") in ["TREM", "ERQA"]: _start_shake()
	_auto_cast(pending)
	if not pending.is_empty() and _hold_arrival(pending): return
	if pending.is_empty() or not is_instance_valid(effects): return
	# Original EL1 GreaterUnsummon@ and EL2@ register
	# Target/BlueDeath on EACH successfully returned creature, then
	# Target/Draw on that creature's original owner, before hard removal.
	# The empty/exempt board has no named FX or effect WAV. Model cleanup
	# remains deferred only until these original-art sites are started.
	if profile.id in ["el1", "el2"] and pending.card == "GRUN":
		for site: Dictionary in pending.get("grun_sites", []):
			var creature := int(site.creature)
			var owner := int(site.owner)
			if models.has(creature):
				effects.play("BlueDeath", {"Target": [models[creature]]})
				battle_audio.effect("BlueDeath")
			if models.has(owner):
				effects.play("Draw", {"Target": [models[owner]]})
				battle_audio.effect("Draw")
		return
	# EL1 Assault@ registers caster PosSorcery. Its aura callback
	#  checks each creature's controller against the caster
	#  before queuing all five creature Target cues.
	# No friendly creatures means no creature effects or their sounds.
	if profile.id == "el1" and pending.card == "ASLT":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("PosSorcery", {"Target": [models[caster]]})
		for creature: Dictionary in duel.army(caster):
			var id := int(creature.id)
			if not models.has(id): continue
			for name: String in ["PosAttack", "PosDefence", "Trample", "Berserk", "PosRune"]:
				effects.play(name, {"Target": [models[id]]})
				battle_audio.effect(name)
		return
	# Original EL1 Flood cast@ and EL2 attach@ register
	# only hero-targeted NegEnchantment. Their individual creature
	# callbacks (EL1 slot11@, EL2 slot13@) conditionally
	# register Target/CantUntap, never a generic casting-hero cue.
	# EL2 checks [figure]+8 == 0 before registration; the original
	# property's precise semantics remain unproved by live original
	# runtime, so reuse the already-ported ground/NoAffect eligibility.
	if profile.id in ["el1", "el2"] and pending.card == "FLOD":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("NegEnchantment", {"Target": [models[caster]]})
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.has_flag(id, "Fly") or duel.has_flag(id, "NoAffect"): continue
			effects.play("CantUntap", {"Target": [models[id]]})
			battle_audio.effect("CantUntap")
		return
	# Original EL1 Earth Bonds attaches NegEnchantment to the chosen
	# creature; its @ callback compares that holder's
	# race with each creature before Target/CantUntap.
	# Apply the remake's existing NoAffect exemption without changing stats.
	if profile.id == "el1" and pending.card == "ERBN":
		var holder := int(pending.target)
		if not duel.creatures.has(holder): return
		if models.has(holder):
			effects.play("NegEnchantment", {"Target": [models[holder]]})
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.race(id) != duel.race(holder) or duel.has_flag(id, "NoAffect"): continue
			effects.play("CantUntap", {"Target": [models[id]]})
			battle_audio.effect("CantUntap")
		return
	# EL2's independent EarthBondsEnchantment attach@ binds NegEnchantment to the
	# enchanted holder. Creature callback@ compares that holder's race to each live
	# creature before registering its own Target/CantUntap; no unconditional
	# caster/other-race cue.
	if profile.id == "el2" and pending.card == "ERBN":
		var holder := int(pending.target)
		if not duel.creatures.has(holder): return
		if models.has(holder):
			effects.play("NegEnchantment", {"Target": [models[holder]]})
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.race(id) != duel.race(holder) or duel.has_flag(id, "NoAffect"): continue
			effects.play("CantUntap", {"Target": [models[id]]})
			battle_audio.effect("CantUntap")
		return
	# EL2 SmokeEnchantment attach@ queues one caster-bound NegEnchantment, while
	# its creature callback@ checks original figure fields before Target/CantUntap.
	# Use the already ported Smoke eligibility: live in-plane figures of either
	# flying status, excluding NoAffect. EL1's Smoke callback tests one figure
	# field before the same Target/CantUntap (EL1 has no plane, so in_plane is
	# always false there).
	if profile.id in ["el1", "el2"] and pending.card == "SMOK":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("NegEnchantment", {"Target": [models[caster]]})
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.in_plane(id) or duel.has_flag(id, "NoAffect"): continue
			effects.play("CantUntap", {"Target": [models[id]]})
			battle_audio.effect("CantUntap")
		return
	# EL2 CondensedAirEnchantment attach@ registers the caster's
	# Target/NegEnchantment; per-creature slot13@ tests the figure's
	# flyer property before its own Target/CantUntap registration. Use the
	# existing in-plane and NoAffect exclusions, without changing untap
	# gameplay. There is no creature cue on empty or ground-only fields.
	# EL1 tests the figure's flying stat the same way.
	if profile.id in ["el1", "el2"] and pending.card == "CNAR":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("NegEnchantment", {"Target": [models[caster]]})
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.in_plane(id) or not duel.has_flag(id, "Fly") or duel.has_flag(id, "NoAffect"): continue
			effects.play("CantUntap", {"Target": [models[id]]})
			battle_audio.effect("CantUntap")
		return
	# Both originals' Mind Blast registers conditional effects on each damaged hero
	# before resolution; no unconditional caster effect remains.
	if profile.id in ["el1", "el2"] and pending.card == "MDBL": return
	# Original EL1@ and EL2@ bypass both Target
	# effect sites when the selected hero had no ether after payment.
	if profile.id in ["el1", "el2"] and pending.card == "BRRL" and int(pending.get("broken_reality_ether", 0)) <= 0:
		return
	# Both original Fog casts (EL1@, EL2@) register an
	# unconditional BlueFog and then Target/CantAttack for each creature
	# in the combat list, including the opposing army.
	# The generic targetless cast incorrectly plays CantAttack on the hero,
	# including when the arena is empty.
	# The forests: the enchantment glow on the caster's hero, the forest
	# itself only on each opposing creature it stops (none when no creature
	# is weak enough), as in both originals.
	if pending.card in ["DNFR", "DRFR", "ANFR"]:
		var names: Array = EffectTable.cast_effects(profile.id, pending.card)
		var hero := int(pending.side)
		if models.has(hero) and names.size() > 0: effects.play(names[0], {"Target": [models[hero]]})
		for id: int in pending.get("forest_targets", []):
			if not models.has(id) or names.size() < 2: continue
			effects.play(names[1], {"Target": [models[id]]})
			battle_audio.effect(names[1], models[id])
		return
	if profile.id in ["el1", "el2"] and pending.card == "FOGG":
		var caster := int(pending.side)
		if models.has(caster): effects.play("BlueFog", {"Target": [models[caster]]})
		for id: int in pending.get("fog_targets", []):
			if not models.has(id): continue
			effects.play("CantAttack", {"Target": [models[id]]})
			# Both originals' CantAttack SOUN source follows this creature's Target.
			battle_audio.effect("CantAttack", models[id])
		return
	# Original EL1 Annihilation@ and EL2@ register a
	# Target/RedAnihilation per non-plane creature in side order, then
	# cue that side's *opposing* hero iff its total creature power is
	# positive. Empty armies register no named effect in either edition.
	if profile.id in ["el1", "el2"] and pending.card == "ANHL":
		for id: int in pending.get("annihilation_sites", []):
			if not models.has(id): continue
			effects.play("RedAnihilation", {"Target": [models[id]]})
			battle_audio.effect("RedAnihilation", models[id])
		return
	# EL1 RavagingHunger@ / CurseOfHunger@ and
	# EL2@ / @ register separate Target/Hunger sites
	# at positive-power creatures before dealing damage.
	# A generic cast otherwise requests one Hunger sound and leaves
	# an incorrect caster-bound effect on an empty battlefield.
	if profile.id in ["el1", "el2"] and pending.card in ["CRHG", "RVHG"]:
		for id: int in pending.get("hunger_sites", []):
			if not models.has(id): continue
			effects.play("Hunger", {"Target": [models[id]]})
			# Both originals attach Hunger's sound to each living victim.
			battle_audio.effect("Hunger", models[id])
		return
	# Both originals' DepressGasEnchantment cast sites (EL1,
	# EL2) register BlackDepressGas and a NegRune at the caster.
	# Creature callbacks (EL1, EL2) register a Target
	# NegAttack and NegRune for each affected creature as it loses power.
	# Generic targetless playback wrongly collapses those into one pair
	# at the casting hero, even with no figures in the battle.
	# Bound to initial cast only; future aura recalculation/arrival cues
	# are not inferred here. Original -2 rules and saves remain untouched.
	if profile.id in ["el1", "el2"] and pending.card == "DPGS":
		var caster := int(pending.side)
		if models.has(caster):
			for effect: String in ["BlackDepressGas", "NegRune"]:
				effects.play(effect, {"Target": [models[caster]]})
				if effect == "BlackDepressGas":
					battle_audio.effect(effect, models[caster])
				else:
					battle_audio.effect(effect)
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.has_flag(id, "NoAffect"): continue
			for effect: String in ["NegAttack", "NegRune"]:
				effects.play(effect, {"Target": [models[id]]})
				battle_audio.effect(effect)
		return
	# Original DrowsyGasEnchantment (EL1, EL2)
	# queues caster-bound BlackDrowsyGas/NegRune. Creature callbacks
	# (EL1, EL2) queue a
	# separate NegAttack/NegRune per living figure. Unlike DPGS, DRGS
	# changes power for NoAffect creatures in the current original-backed
	# rule, so the initial-cast creature cues cover them too. Later aura
	# arrivals/recounts/removals are not inferred from this cast path.
	if profile.id in ["el1", "el2"] and pending.card == "DRGS":
		var caster := int(pending.side)
		if models.has(caster):
			for effect: String in ["BlackDrowsyGas", "NegRune"]:
				effects.play(effect, {"Target": [models[caster]]})
				if effect == "BlackDrowsyGas":
					battle_audio.effect(effect, models[caster])
				else:
					battle_audio.effect(effect)
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id): continue
			for effect: String in ["NegAttack", "NegRune"]:
				effects.play(effect, {"Target": [models[id]]})
				battle_audio.effect(effect)
		return
	# Original EL1 FrenzyGasEnchantment@ / creature callback@
	# and EL2@ / @ bind BlackFrenzyGas/NegRune to the
	# casting hero and NegDefence/NegRune to each eligible creature.
	# Follow the existing NoAffect defence rule; later aura transitions
	# are not inferred from this initial-cast path.
	if profile.id in ["el1", "el2"] and pending.card == "FRGS":
		var caster := int(pending.side)
		if models.has(caster):
			for effect: String in ["BlackFrenzyGas", "NegRune"]:
				effects.play(effect, {"Target": [models[caster]]})
				if effect == "BlackFrenzyGas":
					battle_audio.effect(effect, models[caster])
				else:
					battle_audio.effect(effect)
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or duel.has_flag(id, "NoAffect"): continue
			for effect: String in ["NegDefence", "NegRune"]:
				effects.play(effect, {"Target": [models[id]]})
				battle_audio.effect(effect)
		return
	# Original EL2 Enlightenment@- returns before either
	# Target/Discard or Target/Draw when the hand
	# contains no other card. Positive counts play each effect once at caster.
	if profile.id == "el2" and pending.card == "ENLH" and int(pending.get("enlightenment_count", -1)) == 0:
		return
	# Both WarBanner enchantments apply PosEnchantment to their hero and
	# PosAttack/PosDefence to each non-exempt creature with positive kin.
	# EL1:; EL2:.
	# The original counts same-race creatures on both armies.
	if profile.id in ["el1", "el2"] and pending.get("artifact", false) and pending.card == "WRBN":
		var hero := int(pending.side)
		if models.has(hero): effects.play("PosEnchantment", {"Target": [models[hero]]})
		var exempt: Array = []
		for enchantment: Dictionary in duel.heroes[hero].enchantments:
			if enchantment.card == "WRBN": exempt = enchantment.get("exempt", [])
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id) or exempt.has(id) or duel._kin(creature) <= 0: continue
			effects.play("PosAttack", {"Target": [models[id]]})
			effects.play("PosDefence", {"Target": [models[id]]})
			battle_audio.effect("PosAttack")
			battle_audio.effect("PosDefence")
		return
	# StrengthOfTheWoodsEnchantment: the hero takes PosEnchantment (EL1
	# EL2); the ally-only modifier callback (EL1,
	# EL2) binds PosAttack and PosRune to each of that hero's
	# creatures.
	if profile.id in ["el1", "el2"] and pending.card == "STWO":
		var owner := int(pending.side)
		if models.has(owner): effects.play("PosEnchantment", {"Target": [models[owner]]})
		for creature: Dictionary in duel.army(owner):
			var id := int(creature.id)
			if not models.has(id): continue
			for name: String in ["PosAttack", "PosRune"]:
				effects.play(name, {"Target": [models[id]]})
		return
	# DominantRodEnchantment: the hero takes PosEnchantment (EL1,
	# EL2), and its ally-only modifier callback (EL1,
	# EL2) binds the three stat cues to each creature under that
	# hero's control, not to the hero.
	if profile.id in ["el1", "el2"] and pending.card == "DMRD":
		var hero := int(pending.side)
		if models.has(hero): effects.play("PosEnchantment", {"Target": [models[hero]]})
		for creature: Dictionary in duel.army(hero):
			var id := int(creature.id)
			if not models.has(id): continue
			for name: String in ["PosAttack", "PosDefence", "PosRune"]:
				effects.play(name, {"Target": [models[id]]})
		return
	# Both PouchOfDustEnchantment callbacks (EL1,
	# EL2) queue Target-bound CantAttack and NegRune for
	# creatures across both armies, not for the casting hero.
	if profile.id in ["el1", "el2"] and pending.card == "PCDU":
		for creature: Dictionary in duel.creatures.values():
			var id := int(creature.id)
			if not models.has(id): continue
			effects.play("CantAttack", {"Target": [models[id]]})
			effects.play("NegRune", {"Target": [models[id]]})
		return
	# RodOfDefence: the cast (EL1, EL2) plays PosSorcery
	# on the defending hero; RodOfDefenceEnchantment's modifier callback
	# (EL1, EL2) attaches its +3 health cues to each
	# that hero's creatures (including different races). A generic
	# targetless cast otherwise puts all three on the hero.
	if profile.id in ["el1", "el2"] and pending.get("artifact", false) and pending.card == "RDDF":
		var hero := int(pending.side)
		if models.has(hero): effects.play("PosSorcery", {"Target": [models[hero]]})
		for creature: Dictionary in duel.army(hero):
			var id := int(creature.id)
			if not models.has(id): continue
			effects.play("PosDefence", {"Target": [models[id]]})
			effects.play("PosRune", {"Target": [models[id]]})
		return
	# EL2 LiquidReality takes one channel from the other hero
	# before granting one to the caster. The original effect-site sequence
	# uses DrainMana Start/Finish, then a negative rune on the donor and a
	# positive rune on the recipient (not three cues on the caster).
	if profile.id == "el2" and pending.card == "LQRL":
		var caster := int(pending.side)
		var donor := 1 - caster
		if models.has(caster) and models.has(donor):
			effects.play("DrainMana", {"Start": [models[donor]], "Finish": [models[caster]]})
			effects.play("NegRune", {"Target": [models[donor]]})
			effects.play("PosRune", {"Target": [models[caster]]})
		return
	# Both originals' Powertap (EL1, EL2) drains the
	# opposing hero: Start is the donor, Finish the caster. Their Target
	# runes mark the gained ether on the caster and lost ether on the donor.
	# Generic targetless casts otherwise collapse all three at the caster.
	if profile.id in ["el1", "el2"] and pending.card == "PWTP":
		var caster := int(pending.side)
		var donor := 1 - caster
		if models.has(caster) and models.has(donor):
			effects.play("DrainMana", {"Start": [models[donor]], "Finish": [models[caster]]})
			effects.play("PosRune", {"Target": [models[caster]]})
			effects.play("NegRune", {"Target": [models[donor]]})
		return
	# Both originals' Channel: EL1 and EL2 bind
	# LoseLife/GainMana to the caster, GainLife to the opposite hero.
	# EL2 has three separate Target registrations;
	# the generic targetless cast instead puts all effects on the caster.
	# Preserve edition-specific X, life, ether and audio rules.
	if profile.id in ["el1", "el2"] and pending.card == "CHNL":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("LoseLife", {"Target": [models[caster]]})
			effects.play("GainMana", {"Target": [models[caster]]})
		if models.has(1 - caster):
			effects.play("GainLife", {"Target": [models[1 - caster]]})
		return
	# Both originals' Amnesia (EL1, EL2) loop both
	# hero records and queue a Discard Target cue for each, even when a
	# hand is empty. Only EL2 adds a caster Draw.
	# Generic targetless playback otherwise puts one Discard at caster.
	if profile.id in ["el1", "el2"] and pending.card == "AMNS":
		for hero in 2:
			if models.has(hero): effects.play("Discard", {"Target": [models[hero]]})
		if profile.id == "el2":
			var caster := int(pending.side)
			if models.has(caster): effects.play("Draw", {"Target": [models[caster]]})
		return
	# Both originals' Repair (EL1, EL2) binds
	# PosSorcery/Draw to the caster, but BlackDamage to 1 - side.
	# The generic graveyard-target cast collapsed all three onto the caster.
	if profile.id in ["el1", "el2"] and pending.card == "REPR":
		var caster := int(pending.side)
		var opponent := 1 - caster
		if models.has(caster) and models.has(opponent):
			effects.play("PosSorcery", {"Target": [models[caster]]})
			effects.play("BlackDamage", {"Target": [models[opponent]]})
			effects.play("Draw", {"Target": [models[caster]]})
		return
	# Both originals' BodyExchange cast cues have separate target points:
	# EL1 --; EL2 -
	# -. PosSorcery belongs to the casting hero; BlackDamage
	# to the sacrificed live creature, not the returned graveyard creature.
	# The generic two-target cast incorrectly puts both on the sacrifice.
	if profile.id in ["el1", "el2"] and pending.card == "BDEX":
		var caster := int(pending.side)
		var sacrificed := int(pending.target)
		if models.has(caster): effects.play("PosSorcery", {"Target": [models[caster]]})
		if models.has(sacrificed): effects.play("BlackDamage", {"Target": [models[sacrificed]]})
		return
	# Both original Cannibalism casts (EL1, EL2) queue
	# RedDamage at the sacrificed creature (EL1, EL2)
	# and GainLife at its casting hero (EL1, EL2).
	# The generic target-only cast wrongly places the heal at the victim.
	if profile.id in ["el1", "el2"] and pending.card == "CNBL":
		var sacrificed := int(pending.target)
		var caster := int(pending.side)
		if models.has(sacrificed): effects.play("RedDamage", {"Target": [models[sacrificed]]})
		if models.has(caster): effects.play("GainLife", {"Target": [models[caster]]})
		return
	# EL2 Juryrig: - binds PosSorcery to
	# its casting hero, while - binds BlackDamage to
	# 1 - side (the hurt opposing hero). The generic untargeted cast
	# combines both effects at the affected opponent.
	if profile.id == "el2" and pending.card == "JRRG":
		var caster := int(pending.side)
		var victim := 1 - caster
		if models.has(caster): effects.play("PosSorcery", {"Target": [models[caster]]})
		if models.has(victim): effects.play("BlackDamage", {"Target": [models[victim]]})
		return
	# Tap Life in both originals (EL1, EL2):
	# DrainLife starts at the damaged opponent and finishes at the caster.
	# PosRune marks the recipient, NegRune the donor; a nonpositive hit
	# never creates them (X=0 and Feedback are both visually silent).
	if profile.id in ["el1", "el2"] and pending.card == "TPLF":
		var caster := int(pending.side)
		var victim := 1 - caster
		if int(pending.power) > 0 and bool(pending.tap_life_landed) and models.has(caster) and models.has(victim):
			effects.play("DrainLife", {"Start": [models[victim]], "Finish": [models[caster]]})
			effects.play("PosRune", {"Target": [models[caster]]})
			effects.play("NegRune", {"Target": [models[victim]]})
		return
	# EL1 Unsummon / Lesser Unsummon and EL2
	# Unsummon / Lesser Unsummon create two distinct Target effects:
	# BlueDeath on the departing creature, Draw on its owner.
	if profile.id in ["el1", "el2"] and pending.card in ["UNSM", "LSUS"]:
		var creature := int(pending.target)
		var owner := int(pending.get("return_owner", -1))
		if models.has(creature): effects.play("BlueDeath", {"Target": [models[creature]]})
		if models.has(owner): effects.play("Draw", {"Target": [models[owner]]})
		return
	# Trade in both originals: EL1 / EL2 bind separate
	# GreenDamage Targets to the sacrificed and second creature, followed
	# by GainLife at the second creature's current controller. Gameplay,
	# cost, health, creature removal and save state remain synchronous.
	if profile.id in ["el1", "el2"] and pending.card == "TRAD":
		for victim: int in [int(pending.target), int(pending.get("second", -1))]:
			if models.has(victim): effects.play("GreenDamage", {"Target": [models[victim]]})
		var owner := int(pending.get("beneficiary", -1))
		if models.has(owner): effects.play("GainLife", {"Target": [models[owner]]})
		return
	# Original EL2 Carnivorous@ binds GreenDamage to the eaten
	# creature, GainLife then Draw to the caster, and another GreenDamage
	# to the opposing hero only when the eaten creature's power was > 0
	# . State destruction/heal/draw stay synchronous.
	if profile.id == "el2" and pending.card == "CANV":
		var meal := int(pending.target)
		var caster := int(pending.side)
		if models.has(meal): effects.play("GreenDamage", {"Target": [models[meal]]})
		if models.has(caster):
			effects.play("GainLife", {"Target": [models[caster]]})
			effects.play("Draw", {"Target": [models[caster]]})
		if int(pending.get("devour_power", 0)) > 0 and models.has(1 - caster):
			effects.play("GreenDamage", {"Target": [models[1 - caster]]})
		return
	# EL1 FuryOfNature@: unconditional Target/GreenForceNature
	#  at the caster; Target/GreenDamage only
	# after a positive attempted-hit count at the attacking
	# hero, including defence-phase casts. Do not borrow EL2's Draw cue.
	if profile.id == "el1" and pending.card == "FRNT":
		var caster := int(pending.side)
		var attacker := int(pending.get("fury_attacker", duel.attacker))
		if models.has(caster):
			effects.play("GreenForceNature", {"Target": [models[caster]]})
		if int(pending.get("fury_attempts", 0)) > 0 and models.has(attacker):
			effects.play("GreenDamage", {"Target": [models[attacker]]})
			battle_audio.effect("GreenDamage")
		return
	# EL2 FuryOfNature@ first registers GreenForceNature;
	# - then counts actually destroyed creatures.
	# After the draw loop, - registers exactly one
	# opponent-bound Draw cue when that count is positive.
	if profile.id == "el2" and pending.card == "FRNT":
		var caster := int(pending.side)
		var receiver := int(pending.get("fury_recipient", 1 - caster))
		if models.has(caster):
			effects.play("GreenForceNature", {"Target": [models[caster]]})
		if int(pending.get("fury_deaths", 0)) > 0 and models.has(receiver):
			effects.play("Draw", {"Target": [models[receiver]]})
			battle_audio.effect("Draw")
		return
	# EL1 Firestorm@ and EL2@ both skip effect sites
	# for X=0: positive X starts one caster wave, then RedDamage per
	# opposing creature. Only EL2 adds caster LoseMana after channels.
	# The former generic cast collapsed named effects onto the caster.
	if profile.id in ["el1", "el2"] and pending.card == "FRST":
		if int(pending.power) <= 0: return
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("RedFireWave", {"Start": [models[caster]]})
			battle_audio.effect("RedFireWave", models[caster])
		for id: int in pending.get("firestorm_targets", []):
			if not models.has(id): continue
			effects.play("RedDamage", {"Target": [models[id]]})
			# Both editions' original Firestorm callbacks register the per-creature
			# Target/RedDamage sound; use the live model for the first SOUN key.
			battle_audio.effect("RedDamage", models[id])
		if profile.id == "el2" and bool(pending.get("firestorm_loss", false)) and models.has(caster):
			effects.play("LoseMana", {"Target": [models[caster]]})
			battle_audio.effect("LoseMana", models[caster])
		return
	# EL1 FireWave@ registers Start/RedFireWave,
	# then one creature Target/RedDamage in its nonempty
	# victim loop; EL2 has the same sites.
	# Empty/friendly-only armies still have the caster wave, but no
	# invented RedDamage on the caster (unlike Firestorm's X guard).
	if profile.id in ["el1", "el2"] and pending.card == "FRWA":
		var caster := int(pending.side)
		if models.has(caster):
			effects.play("RedFireWave", {"Start": [models[caster]]})
			battle_audio.effect("RedFireWave", models[caster])
		for id: int in pending.get("fire_wave_targets", []):
			if not models.has(id): continue
			effects.play("RedDamage", {"Target": [models[id]]})
			# Other/unbound and Firestorm RedDamage calls remain unchanged.
			battle_audio.effect("RedDamage", models[id])
		return
	# Both LightningStorms iterate both armies in original order.
	# EL1@ and EL2@ queue RedLightning per struck figure;
	# successful RLSS rescue instead grants +3/+3 and queues three positive
	# Target effects (EL1@, EL2@).
	# No board and failed/absent mastery have no fabricated caster cues.
	if profile.id in ["el1", "el2"] and pending.card == "LGST":
		for site: Dictionary in pending.get("lightning_sites", []):
			var id := int(site.target)
			if not models.has(id): continue
			var names: Array = ["PosAttack", "PosDefence", "PosRune"] if site.blessed else ["RedLightning"]
			for name: String in names:
				effects.play(name, {"Target": [models[id]]})
				# Both originals bind Lightning Storm's RedLightning SOUN to
				# this actual victim, not the caster or global effect origin.
				if name == "RedLightning":
					battle_audio.effect(name, models[id])
				else:
					battle_audio.effect(name)
		return
	# EL1 WindsOfFlame@ and EL2@ both return before
	# these effects at X=0. For positive X the original loop queues Fireball with the
	# caster's Start and that figure's Finish, followed by FireballExpl
	# at the same figure's Finish. Grounded/empty fields queue no pair.
	# Popadanie@39 delays only the hit presentation, not damage rules.
	if profile.id in ["el1", "el2"] and pending.card == "WNFL":
		if int(pending.power) <= 0: return
		var caster := int(pending.side)
		if not models.has(caster): return
		for id: int in pending.get("winds_flame_targets", []):
			if not models.has(id): continue
			effects.play("Fireball", {"Start": [models[caster]], "Finish": [models[id]]})
			battle_audio.effect("Fireball")
			effects.play("FireballExpl", {"Finish": [models[id]]})
			battle_audio.effect("FireballExpl", models[id])
		return
	# EL1 Supernova@ skips its only RedSuperNova site for
	# X=0; positive X queues one untargeted effect before damage.
	# EL2's later channel-loss callback is separate.
	if profile.id == "el1" and pending.card == "SNOV":
		if bool(pending.get("supernova_global", false)):
			effects.play("RedSuperNova", {})
			battle_audio.effect("RedSuperNova")
		return
	# EL2 Supernova@ has no visual registrations at X=0.
	# Positive X registers one untargeted RedSuperNova screen effect
	# then a Target/LoseMana at its paying caster
	# after the one-channel deduction, not at every
	# creature damaged by its all-armies shock.
	if profile.id == "el2" and pending.card == "SNOV":
		if int(pending.power) <= 0: return
		effects.play("RedSuperNova", {})
		battle_audio.effect("RedSuperNova")
		var caster := int(pending.side)
		if bool(pending.get("supernova_loss", false)) and models.has(caster):
			effects.play("LoseMana", {"Target": [models[caster]]})
			battle_audio.effect("LoseMana")
		return
	# EL2 Mana Breeze's two original Target/GainMana registrations are
	# separate hero-bound particles. The generic caster fallback would
	# discard the opponent's effect, despite both heroes gaining channels.
	if profile.id == "el2" and pending.card == "MNBR":
		for hero: int in [int(pending.side), 1 - int(pending.side)]:
			if models.has(hero):
				effects.play("GainMana", {"Target": [models[hero]]})
		return
	var targets: Array = []
	for id: int in ([pending.target] if int(pending.target) >= 0 else pending.affected):
		if models.has(id): targets.append(models[id])
	if targets.is_empty() and models.has(pending.side): targets.append(models[pending.side])
	effects.cast(String(pending.card), {"Start": [models.get(pending.side)], "Target": targets})

func _auto_camera_on() -> bool:
	return auto_camera != null and camera != null and bool(settings.values.get("auto_camera", true))

## Close-ups for a resolved spell: the caster, then the creature(s) it touched.
## Sorcery whose camera event carries effect lengths: [main, extra] effects.
const CAMERA_CAST_LENGTH := {"PWTP": ["DrainMana"], "TPLF": ["DrainLife"], "FRWA": ["RedFireWave", "RedDamage"],
	"ZAPP": ["RedZap"], "COMT": ["RedComet", "RedComet"]}

## Cards whose camera kind differs from the one their rules suggest: the
## camera event each original sends for them (artifacts included).
const CAMERA_KIND := {
	"el1": {"ALST": "sorcery", "FOGG": "sorcery", "FDBK": "sorcery", "SMGS": "enchantment", "INCR": "enchantment",
		"LQRL": "enchantment", "MNFL": "enchantment", "GIFT": "enchantment", "BLNC": "enchantment", "JUST": "enchantment",
		"WRBN": "enchantment", "WNPZ": "enchantment", "RDCM": "enchantment", "RDIS": "enchantment", "DMRD": "enchantment", "RDDF": "enchantment"},
	"el2": {"ALST": "sorcery", "FOGG": "sorcery", "FDBK": "sorcery", "ESWS": "sorcery", "ELKS": "sorcery", "SMGS": "enchantment",
		"INCR": "enchantment", "LQRL": "enchantment", "MNFL": "enchantment", "GIFT": "enchantment", "BLNC": "enchantment", "JUST": "enchantment",
		"WRBN": "enchantment", "RDCM": "enchantment", "RDIS": "enchantment", "DMRD": "enchantment", "RDDF": "enchantment"}}
## Abilities that send a spell camera event, by the card granting them. The
## caster is the user's controlling hero; the figures are the user and its target.
const CAMERA_ABILITY_SORCERY := ["BEHD", "BHWR", "BLDG", "BROT", "CAFG", "CCLP", "ENRG", "FRBL", "GIFG", "GRDG", "GRFG", "KBSH", "LMWK", "MOBE",
	"MOTI", "ORSH", "RNST", "RPST", "RVHL", "RZMN", "SACR", "SEHL", "SPFG", "SPLK", "SWHL", "VBAT", "WLIF", "WLLV", "WLWD", "WZSP"]
const CAMERA_ABILITY := {
	"el1": {"sorcery": CAMERA_ABILITY_SORCERY, "enchantment": ["CMBN"]},
	"el2": {"sorcery": CAMERA_ABILITY_SORCERY + ["CTMN", "SWMN", "FMFI", "MLFI", "PHWL", "PTRS", "RFPT", "WLDT",
		"OUD1", "OUD2", "OUD3", "OUE1", "OUE2", "OUE3", "OUS1", "OUS2", "OUS3"], "enchantment": ["CMBN"]}}

## Ability camera figure lists other than the user and its target: the user
## alone, the user and its hero, the user and both heroes, the hero alone,
## none, the target alone, Burnout's sacrifice and second target, a halo
## (with both heroes only when ether moves), or every enemy creature the
## stones strike (the event comes before the damage).
const CAMERA_ABILITY_FIGURES := {"MOBE": "user", "MOTI": "user", "WLIF": "user", "WLLV": "user", "WLWD": "user", "WZSP": "user",
	"ORSH": "user_hero", "LMWK": "user_hero", "VBAT": "user_heroes", "CMBN": "hero", "RPST": "none", "SPLK": "target",
	"BROT": "targets", "RVHL": "halo", "SEHL": "halo", "SWHL": "halo", "RNST": "enemies"}

func _camera_targets(ids: Array, side: int) -> Array:
	# Heroes count as targets too (the original's flags tell hero from
	# creature); a creature brings its home slot.
	var targets: Array = []
	for id: int in ids:
		if not models.has(id): continue
		if id < 2: targets.append({"at": models[id].position, "side": id, "hero": true})
		else: targets.append({"at": models[id].position, "side": int(duel.entity(id).get("owner", side)), "slot": int(models[id].get_meta("slot", 0)), "card": String(duel.entity(id).get("card", ""))})
	return targets

## Close-ups for a used ability that sends a camera event in the original.
func _auto_ability(data: Dictionary) -> void:
	var source := int(data.get("source", data.side))
	if not _auto_camera_on() or not CAMERA_ABILITY.has(profile.id): return
	var card := _ability_owner_card(source, String(data.ability))
	var kind := ""
	for k: String in CAMERA_ABILITY[profile.id]:
		if card in CAMERA_ABILITY[profile.id][k]: kind = k
	if kind.is_empty(): return
	var side := source if source < 2 else int(duel.entity(source).get("owner", data.side))
	var target := int(data.get("target", -1))
	var figures: Array = [] if source < 2 else [source]
	if target >= 0 and target != source and not CAMERA_ABILITY_FIGURES.has(card): figures.append(target)
	# Some lists hold other figures than the user and its target.
	match CAMERA_ABILITY_FIGURES.get(card, ""):
		"hero": figures = [side]
		"none": figures = []
		"target": figures = [target] if target >= 0 else []
		"targets": figures = [target, int(data.get("hit_target", -1))].filter(func(id: int) -> bool: return id >= 0)
		"user_hero": figures.append(side)
		"user_heroes": figures.append_array([1 - side, side])
		"halo":
			if int(duel.heroes[1 - side].mana) > 0: figures.append_array([1 - side, side])
		"enemies": figures = duel.army(1 - side).map(func(c: Dictionary) -> int: return int(c.id))
	# The Fireball hands the camera its flight and explosion lengths.
	var length := -1.0
	var extra := 0.0
	if card == "FRBL":
		length = ELCombatEffects.fx_frames(profile, "Fireball") * 0.033
		extra = ELCombatEffects.fx_frames(profile, "FireballExpl") * 0.033
	if not models.has(side): return
	auto_camera.cast(kind, side, models[side].position, _camera_targets(figures, side), _local_side(side),
		int(settings.values.get("auto_camera_dynamics", 50)), models[side].timing, length, extra)

## An enchantment's own camera request: a spell shot by the hero over the
## given figures (none for card returns, Barbed Souls' draw, a trap springing
## or Mana Thorns; the shielding creatures for Redirect; both heroes for
## Feedback and Ethereal Chain), or a fight shot at a hero Irritation kills.
func _auto_cue(data: Dictionary) -> void:
	var side := int(data.side)
	if not _auto_camera_on() or not models.has(side): return
	var dynamics := int(settings.values.get("auto_camera_dynamics", 50))
	if data.get("shot", "sorcery") == "fight": auto_camera.combat(side, models[side].position, dynamics)
	else: auto_camera.cast("sorcery", side, models[side].position, _camera_targets(data.get("figures", []), side), _local_side(side), dynamics, models[side].timing)

func _auto_cast(pending: Dictionary) -> void:
	if pending.is_empty() or not _auto_camera_on() or not models.has(pending.side): return
	var card := String(pending.card)
	var kind := "summon" if duel.is_summon(card) else ("enchantment" if ELCatalog.rule(profile, card).get("effect") == "enchant" else "sorcery")
	kind = CAMERA_KIND.get(profile.id, {}).get(card, kind)
	var targets := _camera_targets([pending.target] if int(pending.target) >= 0 else pending.affected, int(pending.side))
	# Sorcery that hands the camera its effect's length (both games): the
	# effect's frames at 33 ms each, plus a second effect for Fire Wave and
	# Comet. Comet striking a hero it kills always shows that hero.
	var length := -1.0
	var extra := 0.0
	var forced := false
	if kind == "sorcery" and CAMERA_CAST_LENGTH.has(card):
		var pair: Array = CAMERA_CAST_LENGTH[card]
		length = ELCombatEffects.fx_frames(profile, String(pair[0])) * 0.033
		if pair.size() > 1: extra = ELCombatEffects.fx_frames(profile, String(pair[1])) * 0.033
		forced = card == "COMT" and int(pending.target) in [0, 1] and int(duel.heroes[int(pending.target)].health) <= 0
	auto_camera.cast(kind, int(pending.side), models[pending.side].position, targets, _local_side(int(pending.side)), int(settings.values.get("auto_camera_dynamics", 50)), models[pending.side].timing, length, extra, forced)

## The end of a battle, as both originals queue it: the
## fallen hero's death clip; then the winner's fanfare and camera and its
## victory clip; when that clip ends the battle is
## over (GameOver): a campaign battle returns to the map by itself, a duel
## round shows its result. Stages: "dying", "victory", "over".
var ending := {}

func _begin_ending(winner: int) -> void:
	var length := 0.0
	for side in 2:
		if side != winner and models.has(side): length = maxf(length, maxf(models[side].clip_seconds("udeath"), 0.0))
	ending = {"winner": winner, "stage": "dying", "clock": 0.0, "length": length}
	ELCrashReport.trace("battle over: %s, round %d" % ["side %d wins" % winner if winner >= 0 else "draw", duel.round_number if duel != null else -1])

## True once the end sequence has played (or none is running).
func ending_over() -> bool:
	return ending.is_empty() or ending.stage == "over"

## The clip a winning hero celebrates with: its victory clip, else (as the
## originals fall back by clip code, EL2, EL1) its instant
## cast clip, else its attack clip; "" when it has none of them.
static func victory_clip(model: ELModel) -> String:
	for code: int in [0x38c0000, 0x1cc0000, 0x2880000]:
		var name := model.clip_for_code(code)
		if not name.is_empty(): return name
	for name: String in ["uvictory", "uinstant", "uattack"]:
		if model.has_clip(name): return name
	return ""

func _step_ending(delta: float) -> void:
	if ending.is_empty() or ending.stage == "over": return
	ending.clock += delta
	if ending.clock < float(ending.length): return
	if ending.stage == "dying":
		var winner := int(ending.winner)
		ending.stage = "victory"
		ending.clock = 0.0
		ending.length = 0.0
		if winner >= 0 and models.has(winner):
			var model: ELModel = models[winner]
			# The fanfare of the winner's colour, for a hero figure (he*) only.
			if String(model.template).begins_with("he"):
				battle_audio.play("buttons/%svictory.wav" % String(duel.heroes[winner].get("faction", "Red")))
			# The winner camera follows the player's own win only (both originals).
			if _auto_camera_on() and _local_side(winner): auto_camera.victory(winner, model.position)
			var clip := victory_clip(model)
			if not clip.is_empty() and model.play(clip):
				battle_audio.unit(model, "victory")
				ending.clip = clip
				ending.length = maxf(model.clip_seconds(clip), 0.0)
		return
	ending.stage = "over"
	# GameOver: a campaign battle closes and the map fades back in.
	if _campaign_battle() != null and duel.phase == ELDuel.Phase.FINISHED: _return_from_encounter()

## The first blow of a fight: the close-up the player's own attack
## declaration shot left for it, if any.
func _auto_fight(from: int, to: int, at := Vector3.INF) -> void:
	fight_shot = true
	if not _auto_camera_on() or from < 2 or not models.has(from) or not models.has(to): return
	auto_camera.first_blow(at)

## The fight a first-blow close-up showed is over: the declaration shot again
## at the attackers still on the field, then back to the player's view.
func _auto_fight_over() -> void:
	if auto_camera == null: return
	if auto_camera.replay.is_empty():
		# A declaration shot still waiting for a blow that was never shown.
		if not auto_camera.fight.is_empty(): auto_camera.release()
		return
	if not _auto_camera_on() or duel.phase == ELDuel.Phase.FINISHED:
		auto_camera.replay = {}
		return
	var middle := Vector3.ZERO
	var count := 0
	for id: int in declared_attackers:
		if duel.creatures.has(id) and models.has(id):
			middle += models[id].position
			count += 1
	auto_camera.fight_over(middle / count if count > 0 else Vector3.INF)

## The original's named camera effect (EL1, applied each frame
##  in every camera mode): the track's motion relative to its first
## key is added to whatever view is current, and it ends on its last key
## with nothing queued after it. Tremor1 moves at most a third of a unit.
func _start_shake(track := "Tremor1.cmf") -> void:
	var source: Dictionary = auto_camera.track(track) if auto_camera != null else {}
	if source.is_empty() or camera == null or source.positions.size() < 2: return
	camera_shake = {"track": source, "time": 0.0, "base": camera.global_transform, "applied": camera.global_transform}

func _step_shake(delta: float) -> void:
	if camera_shake.is_empty() or camera == null: return
	# A view placed since the last frame is the new base; otherwise undo the offset.
	var base: Transform3D = camera_shake.base if camera.global_transform.is_equal_approx(camera_shake.applied) else camera.global_transform
	camera_shake.time += delta
	var source: Dictionary = camera_shake.track
	var frame: float = camera_shake.time * ELAutoCamera.RATE
	var last: int = source.positions.size() - 1
	if frame >= last:
		camera.global_transform = base
		camera_shake = {}
		return
	var i := int(frame)
	var weight := frame - i
	# Tracks are turned half round into this camera's frame (side-0 placement).
	var turn := Quaternion(Vector3.UP, PI)
	var first: Quaternion = source.rotations[0]
	var now: Quaternion = (source.rotations[i] as Quaternion).slerp(source.rotations[i + 1], weight)
	var offset: Vector3 = turn * ((source.positions[i] as Vector3).lerp(source.positions[i + 1], weight) - source.positions[0])
	var spin := turn * (now * first.inverse()) * turn.inverse()
	var shaken := Transform3D(Basis(spin) * base.basis, base.origin + offset)
	camera.global_transform = shaken
	camera_shake.base = base
	camera_shake.applied = shaken

func _step_auto_camera(delta: float) -> void:
	if auto_camera == null or camera == null or not auto_camera.active(): return
	var pose := auto_camera.step(delta)
	if pose.is_empty():
		_update_camera()
	elif pose.get("orbit", false):
		camera.fov = pose.fov
		_place_orbit()
	else:
		var lift := Vector3(0, FRAMED_HEIGHT, 0)
		var with: Array = pose.with.map(func(point: Vector3) -> Vector3: return point + lift)
		var at: Vector3 = ELAutoCamera.clear_of_frame(pose.position, pose.rotation, pose.fov, Vector2(camera.get_viewport().get_visible_rect().size), camera_safe_rect(), pose.anchor + lift, with)
		camera.global_transform = Transform3D(Basis(pose.rotation), at)
		camera.fov = pose.fov
		arena.clear_camera_view(at, pose.focus)

## The part of the battle screen (viewport pixels) not covered by the interface
## frame: the hero columns and corner pieces, the card rail and the top line,
## less a margin so a framed figure is seen whole rather than at the edge.
func camera_safe_rect() -> Rect2:
	var screen := Vector2(camera.get_viewport().get_visible_rect().size) if camera != null else Vector2.ZERO
	if hud_root == null or not hud_root.is_visible_in_tree(): return Rect2(Vector2.ZERO, screen).grow_individual(-screen.x * 0.08, -screen.y * 0.08, -screen.x * 0.08, -screen.y * 0.08)
	var to_screen := hud_root.get_global_transform_with_canvas()
	var size := hud_root.size
	var area := Rect2(to_screen * Vector2(95, 40), Vector2.ZERO).expand(to_screen * Vector2(size.x - 95, size.y - 120))
	return area.grow_individual(-area.size.x * 0.06, -area.size.y * 0.06, -area.size.x * 0.06, -area.size.y * 0.06)

## The card whose ability a character used: a hero's comes from the enchantment
## granting it, a creature's from its own card or the enchantment on it. Empty
## for artifacts and the shared pale-plane abilities.
func _ability_owner_card(source: int, key: String) -> String:
	if source < 2:
		if key.begins_with("artifact:"): return ""
		for e: Dictionary in duel.heroes[source].get("enchantments", []):
			if str(e.get("id", "")) == key.get_slice(":", 1): return String(e.card)
		return ""
	for card: String in ENCHANTMENT_ABILITIES:
		if ENCHANTMENT_ABILITIES[card] == key: return card
	var card := String(duel.entity(source).get("card", ""))
	if card.is_empty() or not duel.creatures.has(source): return ""
	for ability: Dictionary in duel.abilities(source):
		if ability.key == key: return "" if ability.get("pale", false) and String(ability.get("name", "")) != duel.ability_name(card) else card
	return ""

## Abilities every pale creature shares, by remake key.
const PALE_COMMON_ABILITIES := ["dissipate", "sinister", "cruel", "fiendish", "mystic", "cryptic", "courtesy"]

## Effects and sounds of a used ability, drawn between the user and its target.
func _ability_effects(data: Dictionary) -> void:
	var source := int(data.get("source", data.side))
	var side := int(data.side)
	# Each common pale ability first queues its user's action animation
	# (PlayAnimation 7): Dissipation, Sinister, Cruel
	# Fiendish, Mystic, Cryptic Manifestation
	#  and Final Courtesy.
	if profile.id == "el2" and source >= 2 and data.ability in PALE_COMMON_ABILITIES and models.has(source):
		var user: ELModel = models[source]
		if user.has_clip("uinstant") and user.play("uinstant"):
			battle_audio.unit(user, "instant")
	# Common pale abilities have no owner card but three bind effects: Cruel
	#  streams PaleDrainLife from the Shifter (Start) to the creature
	# it destroys (Finish); Mystic streams PaleDrainEncantment
	# the enchantment's holder to the Enchanter; Final Courtesy
	# plays Draw at its owner's hero. Dissipation, Sinister, Fiendish and
	# Cryptic Manifestation have none.
	if profile.id == "el2" and source >= 2 and data.ability in ["cruel", "mystic", "courtesy"]:
		var target := int(data.get("target", -1))
		var name := {"cruel": "PaleDrainLife", "mystic": "PaleDrainEncantment", "courtesy": "Draw"}[data.ability] as String
		var binding := {}
		match data.ability:
			"cruel": if models.has(source) and models.has(target): binding = {"Start": [models[source]], "Finish": [models[target]]}
			"mystic": if models.has(source) and models.has(target): binding = {"Start": [models[target]], "Finish": [models[source]]}
			"courtesy": if models.has(side): binding = {"Target": [models[side]]}
		if not binding.is_empty():
			battle_audio.effect(name)
			if is_instance_valid(effects): effects.play(name, binding)
		return
	var card := _ability_owner_card(source, String(data.ability))
	if card.is_empty() or not models.has(source): return
	# The active creature actions listed below have original uinstant clips
	# and original source figure WAVs. Start only their successful live cues,
	# never passive powers or save-restored creatures.
	if source >= 2 and ((profile.id == "el1" and card == "MNTS" and data.ability == "tap_target")
		or (profile.id == "el2" and card == "MNTS" and data.ability == "tap_target")
		or (profile.id == "el1" and card == "MTSC" and data.ability == "tap_walls")
		or (profile.id == "el2" and card == "MTSC" and data.ability == "tap_walls")
		or (profile.id in ["el1", "el2"] and card == "MTPT" and data.ability == "tap_race")
		or (profile.id == "el1" and card == "ORSH" and data.ability == "ether")
		or (profile.id == "el2" and card == "ORSH" and data.ability == "ether")
		or (profile.id == "el2" and card == "OUS1" and data.ability == "channel_ether")
		or (profile.id == "el2" and card == "OUS2" and data.ability == "ether_plea")
		or (profile.id == "el2" and card == "OUS3" and data.ability == "pale_heal")
		or (profile.id == "el2" and card == "OUD1" and data.ability == "pale_devour")
		or (profile.id == "el2" and card == "OUD2" and data.ability == "pale_devour")
		or (profile.id == "el2" and card == "OUD3" and data.ability == "pale_devour")
		# EL2 Enchanter1Ability@: only successful paid Absorb
		# of a real enchantment has the original EgipetBird action/WAV.
		or (profile.id == "el2" and card == "OUE1" and data.ability == "absorb")
		# EL2 Enchanter2Ability@: successful paid Weave copies an
		# enchantment and plays the genuine EgipetSnake living-source cue.
		or (profile.id == "el2" and card == "OUE2" and data.ability == "weave")
		# EL2 Enchanter3Ability@: successful paid Transpose dispels
		# the target enchantment into hand and animates its EgipetCrocodile source.
		or (profile.id == "el2" and card == "OUE3" and data.ability == "transpose")
		or (profile.id == "el1" and card == "SHSP" and data.ability == "rouse")
		or (profile.id == "el2" and card == "SHSP" and data.ability == "rouse")
		or (profile.id == "el1" and card == "CLSP" and data.ability == "recall_spirit")
		or (profile.id == "el1" and card == "LMMN" and data.ability == "recall_lamia")
		or (profile.id == "el1" and card == "PTRS" and data.ability == "dispel")
		or (profile.id == "el1" and card == "BHWR" and data.ability == "gaze")
		or (profile.id == "el1" and card == "BEHD" and data.ability == "gaze")
		or (profile.id == "el1" and card == "FMFI" and data.ability == "necromancy")
		or (profile.id == "el1" and card == "MLFI" and data.ability == "necromancy")
		or (profile.id == "el1" and card == "BUDG" and data.ability == "breath")
		or (profile.id == "el1" and card == "GRDG" and data.ability == "wall_break")
		or (profile.id == "el2" and card == "GRDG" and data.ability == "wall_break")
		or (profile.id == "el1" and card == "GRFG" and data.ability == "sting")
		or (profile.id == "el1" and card == "CCLP" and data.ability == "sting")
		or (profile.id == "el1" and card == "WZSP" and data.ability == "spirit_flight")
		or (profile.id == "el2" and card == "LMWK" and data.ability == "draw")
		or (profile.id == "el1" and card == "LMWK" and data.ability == "draw")
		or (profile.id in ["el1", "el2"] and card == "VBAT" and data.ability == "bat_drain")
		or (profile.id == "el1" and card == "RVHL" and data.ability == "siphon")
		or (profile.id == "el2" and card == "RVHL" and data.ability == "siphon")
		or (profile.id == "el1" and card == "SEHL" and data.ability == "siphon")
		or (profile.id == "el2" and card == "SEHL" and data.ability == "siphon")
		or (profile.id == "el1" and card == "SWHL" and data.ability == "siphon")
		or (profile.id == "el2" and card == "SWHL" and data.ability == "siphon")
		or (profile.id == "el1" and card == "BLDG" and data.ability == "slay")
		or (profile.id == "el2" and card == "BLDG" and data.ability == "slay")
		or (profile.id in ["el1", "el2"] and card == "RDDG" and data.ability == "breath")
		or (profile.id == "el2" and card == "BUDG" and data.ability == "breath")
		or (profile.id == "el1" and card == "AVMK" and data.ability == "shoot")
		or (profile.id in ["el1", "el2"] and card == "WNHR" and data.ability == "hunt")
		or (profile.id == "el2" and card == "AVMK" and data.ability == "shoot")
		or (profile.id == "el2" and card == "CCLP" and data.ability == "sting")
		or (profile.id == "el2" and card == "GRFG" and data.ability == "sting")
		or (profile.id == "el1" and card == "GIFG" and data.ability == "sting")
		or (profile.id == "el2" and card == "GIFG" and data.ability == "sting")
		or (profile.id == "el2" and card == "BEHD" and data.ability == "gaze")
		or (profile.id == "el2" and card == "BHWR" and data.ability == "gaze")
		or (profile.id == "el1" and card == "DMRT" and data.ability == "recall_rat")
		or (profile.id == "el2" and card == "DMRT" and data.ability == "recall_rat")
		or (profile.id == "el1" and card == "DRAT" and data.ability == "gnaw")
		or (profile.id == "el2" and card == "DRAT" and data.ability == "gnaw")
		or (profile.id == "el1" and card == "PRAT" and data.ability == "plague")
		or (profile.id == "el2" and card == "PRAT" and data.ability == "plague")
		or (profile.id == "el2" and card == "CLSP" and data.ability == "recall_spirit")
		or (profile.id == "el2" and card == "LMMN" and data.ability == "recall_lamia")
		or (profile.id == "el2" and card == "PTRS" and data.ability == "dispel")
		or (profile.id == "el2" and card == "FMFI" and data.ability == "necromancy")
		or (profile.id == "el2" and card == "MLFI" and data.ability == "necromancy")
		or (profile.id == "el2" and card == "WZSP" and data.ability == "spirit_flight")
		# Spitting and Carnivorous Fingus spores and the Reinforced Pteros gaze:
		# EL2 queue the action; EL1 plays
		# it for every successful creature ability.
		or (card in ["SPFG", "CAFG"] and data.ability == "spores")
		or (card == "RFPT" and data.ability == "disenchant")):
		var actor: ELModel = models[source]
		if actor.has_clip("uinstant") and actor.play("uinstant"):
			battle_audio.unit(actor, "instant")
	# Original EL1 SeaHaloAbility - registers DrainMana
	# only when ether moves: Start on the opposing donor hero,
	# Finish on the recipient hero. The zero-ether ability still
	# succeeds and rests its BlueHalo but skips this particle/audio cue.
	# River Halo and Swamp Halo share this code: the same guard and the same
	# donor-to-recipient hero binding.
	# The second game's halos bind the same way (River Halo,
	# skipped when no ether moves).
	if source >= 2 and card in ["SEHL", "RVHL", "SWHL"] and data.ability == "siphon":
		if int(duel.heroes[1 - side].mana) > 0 and models.has(1 - side) and models.has(side):
			battle_audio.effect("DrainMana")
			if is_instance_valid(effects):
				effects.play("DrainMana", {"Start": [models[1 - side]], "Finish": [models[side]]})
		return
	# The successful ability event is synchronous, before target rest changes.
	# Patriarch cues only awake, non-sick enemies of the selected race.
	# Sick matches still pay/rest; EL2 excludes creatures in the Colourless Plane.
	if profile.id in ["el1", "el2"] and source >= 2 and card == "MTPT" and data.ability == "tap_race":
		var race := duel.race(int(data.target))
		for enemy: Dictionary in duel.army(1 - side):
			var target := int(enemy.id)
			if profile.id == "el2" and duel.in_plane(target): continue
			if not enemy.resting and not enemy.sick and duel.race(target) == race and models.has(target):
				_play_ability([["NegSorcery", "at"]], source, side, target, false)
		return
	# Both original Mantis Scribes select awake opposing Walls (EL1
	# –; EL2 –). Sick Walls still
	# pay/rest, but the original Target/NegSorcery is queued separately
	# for each awake non-sick Wall before the synchronous rest change.
	# A magic screen does not protect a non-targeted bystander.
	if profile.id in ["el1", "el2"] and source >= 2 and card == "MTSC" and data.ability == "tap_walls":
		for enemy: Dictionary in duel.army(1 - side):
			var target := int(enemy.id)
			if not enemy.resting and not enemy.sick and duel.race(target) == "Wall" and models.has(target):
				_play_ability([["NegSorcery", "at"]], source, side, target, false)
		return
	# Both original KoboldElderAbility callbacks (EL1 –,
	# EL2 –) bind Target/PosSorcery to each newly
	# readied allied Kobold, not the Elder. The event precedes untap.
	if profile.id in ["el1", "el2"] and source >= 2 and card == "KBEL" and data.ability == "rally":
		for ally: Dictionary in duel.army(side):
			var target := int(ally.id)
			if ally.card != "KBEL" and ally.resting and duel.race(target) == "Kobold" and models.has(target):
				_play_ability([["PosSorcery", "at"]], source, side, target, false)
		return
	# Vampire Bat's DrainLife follows the damage (bat_drain_cue).
	if card == "VBAT" and data.ability == "bat_drain": return
	var items := EffectTable.ability_effects(profile.id, card)
	if card == EffectTable.ILLUSION_CARD and data.has("grave"): items = EffectTable.illusion_effects(int(data.grave))
	# EL2 Burnout's first selection is the creature being sacrificed;
	# original - starts RedDamage there. The later
	# Fireball/FireballExpl points and their impact use the second
	# selection (onwards). EL1 presentation stays unchanged.
	var visual_target := int(data.get("target", -1))
	if profile.id == "el2" and card == "BROT": visual_target = int(data.get("hit_target", visual_target))
	# RNST has no selected target: original RainOfStoneAbility strikes every
	# opposing creature and its RedRainOfStones visual has Monsters Hit@35.
	# Snapshot these ids before synchronous damage removes any of them.
	if profile.id == "el2" and source < 2 and card == "RNST":
		var victims: Array[int] = []
		for victim: Dictionary in duel.army(1 - side):
			if models.has(int(victim.id)): victims.append(int(victim.id))
		var rain_delay := ELCombatEffects.ability_hit_delay(profile, card)
		if rain_delay > 0.0 and not victims.is_empty():
			_ability_hit = {"targets": victims, "hit": rain_delay}
			call_deferred("_clear_ability_hit")
	# Both editions' FRBL hero ability has Fireball's Popadanie@39 hit
	# cue (EL1 original). EL1 GiantFingusAbility@
	# separately starts original FingusSpit, MonstersHit@10 on its target.
	# EL2 creature abilities and BROT's second target keep prior timing;
	# sacrifice death and all underlying damage resolve synchronously.
	elif visual_target >= 0 and ((profile.id == "el2" and (source >= 2 or card in ["FRBL", "BROT"])) or (profile.id == "el1" and card in ["FRBL", "GIFG"])):
		var hit := ELCombatEffects.ability_hit_delay(profile, card)
		if hit > 0.0:
			_ability_hit = {"target": visual_target, "hit": hit}
			call_deferred("_clear_ability_hit")
	if profile.id == "el1" and card == "BROT":
		# The first game's Burnout: RedDamage on the sacrifice (skipped when
		# mastery spares it), then the Fireball flies from the sacrifice to
		# the second target and FireballExpl bursts there.
		var sacrifice: ELModel = models.get(int(data.target))
		var victim: ELModel = models.get(int(data.get("hit_target", -1)))
		if sacrifice != null and not data.get("spared", false):
			battle_audio.effect("RedDamage")
			if is_instance_valid(effects): effects.play("RedDamage", {"Target": [sacrifice]})
		if sacrifice != null and victim != null:
			battle_audio.effect("Fireball")
			battle_audio.effect("FireballExpl", victim)
			if is_instance_valid(effects):
				effects.play("Fireball", {"Start": [sacrifice], "Finish": [victim]})
				effects.play("FireballExpl", {"Finish": [victim]})
	elif profile.id == "el2" and card == "OEXC":
		# OuterExchangeAbility: Start = the creature leaving the
		# Colourless Plane (first choice), Finish = the one entering it.
		var leaving: ELModel = models.get(int(data.target))
		var entering: ELModel = models.get(int(data.get("hit_target", -1)))
		battle_audio.effect("OuterExchange")
		if leaving != null and entering != null and is_instance_valid(effects):
			effects.play("OuterExchange", {"Start": [leaving], "Finish": [entering]})
	elif profile.id == "el2" and card == "BROT":
		# Two different figure bindings in the original ability sequence:
		# its sacrifice glows, then the fireball flies to the damage victim.
		for item: Array in items:
			_play_ability([item], source, side, int(data.target) if String(item[0]) == "RedDamage" else visual_target, true)
	elif profile.id in ["el1", "el2"] and card == "RPST" and source == side:
		# The first game's StationAbility binds the same way (PosSorcery and
		# Draw at its own side, BlackDamage at 1 - side).
		# StationAbility: PosSorcery and Draw are Target-bound to
		# the casting hero; BlackDamage uses 1 - side.
		# The grave choice is not a figure. Generic playback placed all
		# three at the caster instead of showing the opposing hero's hit.
		for item: Array in items:
			_play_ability([item], source, side, 1 - side if String(item[0]) == "BlackDamage" else side, false)
	else:
		# Attach the own-edition first-key impact WAV source to that victim; leave the
		# separate Fireball projectile unpositioned. EL2's two later original-index
		# effect-name references have not been proven to request additional
		# simultaneous audio at ability start.
		_play_ability(items, source, side, visual_target, true,
			profile.id in ["el1", "el2"] and card == "FRBL",
			profile.id == "el2" and ((card == "ORSH" and data.ability == "ether")
				or (card == "OUS1" and data.ability == "channel_ether")))
	# Both editions' KBSH cr206 have a 58-frame uinstant but no figure instant.wav.
	# Bind original RedZap Start/Finish particles to the standing cast joint
	# first, then animate the source without inventing an extra sound.
	if profile.id in ["el1", "el2"] and source >= 2 and card == "KBSH" and data.ability == "sting":
		var shaman: ELModel = models[source]
		if shaman.has_clip("uinstant"):
			shaman.play("uinstant")

func _clear_ability_hit() -> void:
	_ability_hit.clear()

## A combat power's effects and sounds, drawn at (or towards) the figure it struck.
func _combat_ability(data: Dictionary) -> void:
	var source := int(data.get("source", -1))
	if not models.has(source): return
	_play_ability(EffectTable.combat_effects(profile.id, String(data.get("key", ""))), source, int(data.get("side", 0)), int(data.get("target", -1)), false)

## Plays [[effect, binding], ...] between `source` and `target`; with
## `hero_effects`, life/ether/card effects are drawn at the acting hero.
func _play_ability(items: Array, source: int, side: int, target: int, hero_effects: bool, frbl_victim_sound := false, hero_gainmana_source := false) -> void:
	var user: ELModel = models.get(source)
	if user == null: return
	var aim: ELModel = models.get(target, models.get(1 - side))
	for item: Array in items:
		if item.size() < 2: continue
		var effect := String(item[0])
		if hero_gainmana_source and effect == "GainMana" and models.has(side):
			# EL2 ORSH@ and OUS1@ bind their own
			# Target/GainMana to the receiving hero. This magic effect
			# has a separate sound source from the creature's instant.wav.
			battle_audio.effect(effect, models[side])
		elif frbl_victim_sound and effect == "FireballExpl" and is_instance_valid(aim):
			battle_audio.effect(effect, aim)
		else:
			battle_audio.effect(effect)
		if not is_instance_valid(effects): continue
		var at: ELModel = models.get(side) if hero_effects and EffectTable.HERO_EFFECTS.has(effect) else models.get(target, user)
		match String(item[1]):
			"line": if aim != null: effects.play(effect, {"Start": [user], "Finish": [aim]})
			"to_user": if aim != null: effects.play(effect, {"Start": [aim], "Finish": [user]})
			"start": effects.play(effect, {"Start": [user]})
			# Original RainOfStoneAbility binds Start to the opposing hero;
			# falling rocks belong over that side, not the caster.
			"enemy_start": if models.has(1 - side): effects.play(effect, {"Start": [models[1 - side]]})
			"finish": if aim != null: effects.play(effect, {"Finish": [aim]})
			_: if at != null: effects.play(effect, {"Target": [at]})

func _figure_effect(effect: String, id: int) -> void:
	if is_instance_valid(effects) and models.has(id): effects.play(effect, {"Target": [models[id]]})

## A figure's idle sounds (original EL1/EL2 figure sound loader, EL2
## ): idle00.wav with every cycle of the plain idle, as it
## starts and each time it repeats, and idleNN.wav with idle variant N. The
## resting idle has none.
func _hear_idle(model: ELModel) -> void:
	model.animation_started.connect(_idle_sound.bind(model))
	model.animation_looped.connect(_idle_sound.bind(model))

func _idle_sound(clip: String, model: ELModel) -> void:
	var action := ""
	if clip == "cidle": action = "idle00"
	elif clip.begins_with("cspecial") and clip.trim_prefix("cspecial").is_valid_int():
		action = "idle%02d" % int(clip.trim_prefix("cspecial"))
	if action.is_empty() or not is_instance_valid(battle_audio): return
	var path: String = battle_audio.unit_path(model, action)
	if not path.is_empty() and ELAudio.sound(profile, path) != null: battle_audio.play(path)

## A moving creature's walk or run clip reached a footfall.
func _footfall(clip: String, id: int) -> void:
	if models.has(id) and is_instance_valid(melee) and melee.stepping(id, clip): battle_audio.step(models[id])

func _animation_done(clip: String, id: int) -> void:
	if not models.has(id) or _hits_waiting.has(id):
		return
	if _melee_busy() and melee.moving(id): return
	if id >= 2 and not duel.creatures.has(id):
		# During combat playback a creature that falls to a later blow fights on until then.
		if _melee_busy() and clip != "udeath":
			models[id].play("cidle")
			return
		_remove_model(id)
		return
	if duel.phase == ELDuel.Phase.FINISHED:
		return
	var resting: bool = id >= 2 and (duel.creatures[id].resting or duel.creatures[id].sick)
	if not models[id].play("ctapidle" if resting else "cidle"):
		models[id].play("cidle")

## Blood at a dying figure, when the preference allows it; the second game
## colours it by the figure's material.
func _bleed(id: int) -> void:
	if is_instance_valid(blood) and models.has(id) and bool(settings.values.blood):
		blood.burst(ELCombatBlood.body_point(models[id]), String(models[id].get_meta("blood", "")))

func _remove_model(id: int) -> void:
	if not models.has(id): return
	models[id].queue_free()
	models.erase(id)
	labels[id].queue_free()
	labels.erase(id)
	homes.erase(id)

func _add_label(id: int) -> void:
	var label := Label3D.new()
	label.font_size = 28
	label.outline_size = 9
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	stage.add_child(label)
	labels[id] = label

## The overlay rows drawn over a figure this frame, or {} (for checks).
func figure_rows(id: int) -> Dictionary:
	if not is_instance_valid(symbols): return {}
	for figure: Dictionary in symbols.figures:
		if int(figure.get("id", -1)) == id: return figure
	return {}

## Height of a figure's top above its feet: its posed parts' bounds, as the
## original measures the figure each frame.
func _figure_height(model: ELModel) -> float:
	if not is_instance_valid(model) or not model.is_inside_tree(): return 1.7
	var top := model.global_position.y
	for part: Variant in model.parts.values():
		if part is MeshInstance3D and part.mesh != null and part.is_visible_in_tree(): top = maxf(top, (part.global_transform * part.mesh.get_aabb()).end.y)
	var height := top - model.global_position.y
	return height if height > 0.1 else 1.7

## The creature's state and ability icons in the original order (icon bits
## T_CREATURE_ICON_01..21); the second game adds the last three.
func creature_icons(id: int) -> Array:
	var c: Dictionary = duel.creatures.get(id, {})
	if c.is_empty(): return []
	var owned: Array = []
	owned.append_array(c.get("flags", []))
	owned.append_array(c.get("granted", []))
	var marks: Array = [c.get("resting", false), c.get("sick", false), owned.has("NoAttack"), owned.has("Fly"), owned.has("FS"),
		owned.has("Trample"), owned.has("Restless"), owned.has("Lifetap"), duel.regeneration_cost(id) > 0,
		owned.any(func(flag: Variant) -> bool: return String(flag).begins_with("Discard(")), owned.has("Disenchant"), owned.has("Destroy"),
		owned.has("NoUntap"), owned.has("UB"), owned.has("NSS"), owned.has("Berserk"), owned.has("TeamAttack"), owned.has("Elusive")]
	if profile.id == "el2": marks.append_array([duel.pale(id), duel.in_plane(id), duel.race(id) == "OutSpellJammer"])
	var result: Array = []
	for bit in marks.size():
		if marks[bit]: result.append(ELCombatSymbols.ICON_CODES[bit])
	return result

## Where a figure's marks hang: the original reads the model's animated
## "numbers" node; a model without one, or whose clip leaves it
## at the feet, uses the top of its meshes.
func _numbers_point(model: ELModel) -> Vector3:
	var part: Node3D = model.parts.get("numbers")
	if part != null and model.clips.get(model.clip, {}).has("numbers"):
		var mesh: Mesh = model._mesh_cache.get("base/numbers")
		var at := part.global_transform * mesh.get_aabb().get_center() if mesh != null else part.global_position
		if at.y - model.global_position.y > 0.15: return model.position + (at - model.global_position)
	return model.position + Vector3(0, _figure_height(model), 0)

## The original flying number over a figure: damage red, healing (negative) green.
func _float_number(id: int, amount: int) -> void:
	if not models.has(id) or not is_instance_valid(symbols) or not is_instance_valid(models[id]): return
	symbols.add_number(models[id].position + Vector3(0, _figure_height(models[id]), 0), amount, id)

## A rising caption over a figure. Captions that name a spell, ability or
## state have no original counterpart and show only with the helper overlay;
## numbers always show. Captions over one figure stack upward, never overlapping.
func _float_text(id: int, text: String, color: Color, remake_only := false) -> void:
	if not models.has(id) or (remake_only and not helper_overlay()):
		return
	var live: Array = _floating.get(id, []).filter(func(node) -> bool: return is_instance_valid(node) and not node.is_queued_for_deletion())
	var label := Label3D.new()
	label.text = text
	label.font_size = 52
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = true
	stage.add_child(label)
	label.position = models[id].position + Vector3(0, 2 + 0.7 * live.size(), 0)
	live.append(label)
	_floating[id] = live
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.5, 0.9)
	tween.tween_callback(label.queue_free)

## A card dropping into the hand rail. The original steps its inserter
## actions once per rendered frame (EL2 ``/``): the new card
## starts 50 px above its place and transparent; a drawn card is opaque on the
## next frame and falls 25 px per frame; a returned card fades in at half alpha
## over two frames before it falls. One step here is a 60 Hz frame.
static func rail_drop(button: Control, back: bool) -> Tween:
	const STEP := 1.0 / 60.0
	button.modulate.a = 0.0
	var tween := button.create_tween()
	# The rail's container places its cards again when the hand changes size;
	# keep the current rise through that.
	var box := button.get_parent() as Container
	var keep := func() -> void: button.position.y = -float(button.get_meta("rail_rise", 0.0))
	if box != null:
		box.sort_children.connect(keep)
		var release := func() -> void: if box.sort_children.is_connected(keep): box.sort_children.disconnect(keep)
		tween.finished.connect(release)
		button.tree_exiting.connect(release)
	var put := func(alpha: float, rise: float) -> void:
		button.modulate.a = alpha
		button.set_meta("rail_rise", rise)
		button.position.y = -rise
	tween.tween_interval(STEP)
	if back:
		tween.tween_callback(put.bind(0.5, 50.0))
		tween.tween_interval(STEP)
	tween.tween_callback(put.bind(1.0, 25.0))
	tween.tween_interval(STEP)
	tween.tween_callback(put.bind(1.0, 0.0))
	return tween

func _refresh() -> void:
	if duel == null or updating:
		return
	_check_handover()
	_step_front_line()
	updating = true
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	var active := duel.active_side()
	var displayed := 0 if mode_select.selected == 0 and not demo else active
	# Hot seat: the confirmed player's side; nothing while a hand-over waits.
	var concealed := _hot_seat() and hot_pending
	if _hot_seat() and hot_side >= 0: displayed = hot_side
	var hero: Dictionary = duel.heroes[displayed]
	# The original rail holds one icon per hand card (EL2 ``, one
	# CSpellInserter per hand entry); copies are not grouped.
	var showing_artifacts := rail != null and rail.artifacts_shown
	var order: Array[int] = []
	if not showing_artifacts and not concealed: order = duel.hand_display(displayed)
	# A card that joins the hand the rail already shows drops in; a rebuilt rail
	# (another side, the artifact list, a hand-over) does not (EL2 ``
	# sets the inserter's instant flag while it rebuilds).
	var keys: Variant = hero.get("hand_view")
	var tracked: bool = keys is Array and keys.size() == hero.hand.size()
	var seen := {}
	# A loaded or new battle is a rebuild too.
	var same_duel: bool = _rail_seen_duel != null and _rail_seen_duel.get_ref() == duel
	var animate: bool = tracked and _rail_seen_side == displayed and same_duel
	var old_min := INF
	for id: String in _rail_seen: old_min = minf(old_min, float(id.get_slice(":", 0)))
	for i: int in order:
		var card: String = hero.hand[i]
		var uses := duel.hand_uses(displayed, i)
		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(50, 50)
		button.texture_normal = profile.card_icon(card)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var price := "%d + X" % duel.cost(card) if duel.variable_power(card) and ELCatalog.rule(profile, card).get("x_source") != "health" else str(duel.cost(card))
		button.tooltip_text = card_tooltip(card)
		if helper_overlay():
			button.tooltip_text += "\n%s ether" % price
			if uses >= 0:
				var unit := "rune" if profile.id == "el1" else "charge"
				button.tooltip_text += "\n%d %s%s left in this spellbook copy." % [uses, unit, "" if uses == 1 else "s"]
			else:
				button.tooltip_text += "\nUnlimited cantrip." if profile.id == "el1" and profile.table("CombatSpells")[card].get("Rarity") == "Cantrip" else "\nReturned or created spell: no spellbook charge required."
		button.set_meta("card", card)
		button.set_meta("hand_index", i)
		button.set_meta("charges", uses)
		button.disabled = not _human_turn() or duel.available_mana(displayed) < duel.cost(card) or hero.channels < duel.channel_cost(card) or uses == 0
		_list_look().dress(button)
		if i == selection: _selection_outline(button)
		# Remake readout: the cost, only with the helper overlay.
		if helper_overlay():
			var mana := _label(price.replace(" ", ""), 13, ACCENT)
			mana.position = Vector2(2, 1)
			mana.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(mana)
		# The original prints the spellbook slot's remaining charges (runes in the
		# first game) at the icon's lower right in its glyph digits, 0..1000, none
		# for a generated card (EL2 ``, EL1 ``; both step 8 px).
		if uses >= 0 and uses <= 1000:
			var charges := _list_look().number(uses, false)
			charges.set_meta("charge_label", true)
			button.add_child(charges)
		button.pressed.connect(_cast_card.bind(i))
		button.mouse_entered.connect(_hint.bind(button.tooltip_text.replace("\n", " — ")))
		hand.add_child(button)
		if tracked:
			var id := "%d:%s" % [int(keys[i]), card]
			seen[id] = true
			if animate and not _rail_seen.has(id):
				# Drawn cards enter at the left, returned ones at the right.
				var back := float(keys[i]) > old_min
				button.set_meta("rail_drop", rail_drop(button, back))
				if rail != null: rail.reveal_hand(back)
	_rail_seen = seen
	_rail_seen_side = displayed if tracked and not showing_artifacts and not concealed else -1
	_rail_seen_duel = weakref(duel)
	if showing_artifacts and not concealed: _fill_artifact_rail(displayed)
	if hand_frames != null: hand_frames.queue_redraw()
	if rail != null:
		var tallies: Array = []
		for side in 2:
			var h: Dictionary = duel.heroes[side]
			tallies.append([h.grave.size(), h.enchantments.size(), h.hand.size(), h.get("artifacts", []).size()])
		rail.set_counts(tallies[0], tallies[1])
	for side in 2:
		var h: Dictionary = duel.heroes[side]
		hero_values[side].text = "%d   %d   %d" % [h.health, h.mana, h.channels]
	if rail != null: rail.set_stats([duel.heroes[0].health, duel.heroes[0].mana, duel.heroes[0].channels], [duel.heroes[1].health, duel.heroes[1].mana, duel.heroes[1].channels])
	for side in 2:
		var h: Dictionary = duel.heroes[side]
		hero_names[side].text = _side_name(side)
		# The original prints no name over the portraits (a right click names the hero).
		hero_names[side].visible = helper_overlay()
		hero_names[side].modulate = ACCENT if side == active else INK
		# Original value tooltips: CombatTt1/3/5 for the displayed hero, 2/4/6 for the opponent.
		var tips: Array[String] = []
		for index: int in ([1, 3, 5] if side == displayed else [2, 4, 6]): tips.append(_control_tip("CombatTt%d" % index))
		hero_buttons[side].tooltip_text = "\n".join(tips)
		if helper_overlay(): hero_buttons[side].tooltip_text += "\n%s\n%d / %d health · %d ether · %d channels\n%d cards in hand · %d creatures in the graveyard\nClick this portrait to target the hero." % [_side_name(side), h.health, h.maximum, h.mana, h.channels, h.hand.size(), h.grave.size()]
		for code: String in h.get("skills", {}):
			var rank := int(h.skills[code])
			var skill := ELHeroSkills.definition(profile, code, rank)
			hero_buttons[side].tooltip_text += "\n%s %s" % [profile.text(str(skill.get("Name", code))), ["I", "II", "III"][rank]]
		if str(h.get("spec", "NONE")) != "NONE" and helper_overlay(): hero_buttons[side].tooltip_text += "\n%s" % _spec_name(h.spec)
	# The battle title line is a remake readout (helper overlay only).
	status.text = "%s · %s vs %s" % [profile.title, ELCatalog.faction_name(duel.heroes[0].faction), ELCatalog.faction_name(duel.heroes[1].faction)] if helper_overlay() else ""
	phase_label.text = phase_caption()
	phase_label.tooltip_text = "%s's phase" % _side_name(active) if helper_overlay() else ""
	# The phase control is the original panel's end-phase socket; its icon is
	# part of the panel art. Only the post-battle return control carries text.
	end_button.text = "Continue to map" if _campaign_battle() != null and duel.phase == ELDuel.Phase.FINISHED else ("Continue" if (duel_match != null or combat_tutorial != null) and duel.phase == ELDuel.Phase.FINISHED else "")
	_place_end_button()
	end_button.disabled = not _human_turn() and not ((_campaign_battle() != null or duel_match != null or combat_tutorial != null) and duel.phase == ELDuel.Phase.FINISHED)
	# The original control tooltips (CombatMenu2 end of phase, CombatMenu1 attack with all).
	end_button.tooltip_text = _control_tip("CombatMenu2")
	attack_button.tooltip_text = _control_tip("CombatMenu1")
	if helper_overlay():
		end_button.tooltip_text += "\n" + ("End attack [Space]" if duel.phase == ELDuel.Phase.ATTACK else "Resolve battle [Space]")
		attack_button.tooltip_text += "\nAttack with all ready creatures"
	_refresh_buttons()
	if auto_combat and duel.phase == ELDuel.Phase.FINISHED:
		auto_combat = false
		auto_off_button.visible = false
	# Hot seat has no auto combat (unavailable in HotSeat in the original).
	auto_button.disabled = not auto_combat and (not _human_turn() or combat_tutorial != null or _hot_seat())
	for id: int in models:
		if id >= 2 and duel.creatures.has(id) and models[id].clip.begins_with("c"):
			var resting: bool = duel.creatures[id].resting or duel.creatures[id].sick
			var desired := "ctapidle" if resting else "cidle"
			if models[id].base_clip() != desired:
				_turn_figure(models[id], desired, bool(duel.creatures[id].resting))
	_refresh_inspector()
	updating = false

## The panel buttons' availability (their shutters close when unavailable).
## Attack with all is open only while one of the side's creatures can still
## be sent.
func _refresh_buttons() -> void:
	if duel == null or attack_button == null: return
	end_button.disabled = not _human_turn() and not ((_campaign_battle() != null or duel_match != null or combat_tutorial != null) and duel.phase == ELDuel.Phase.FINISHED)
	attack_button.disabled = not _human_turn() or duel.phase != ELDuel.Phase.ATTACK or not duel.army(duel.active_side()).any(func(c: Dictionary) -> bool: return duel.can_attack(c.id) and not duel.attacks.has(c.id))

## A creature put to rest by an action, or rising from rest, plays the figure's own tap
## or untap clip (with its sound and clip particles) before the idle it ends
## in; figures without the clip change idle at once.
func _turn_figure(model: ELModel, desired: String, resting: bool) -> void:
	var from := model.base_clip()
	# A newly summoned figure simply waits in its resting idle.
	var clip := "utap" if desired == "ctapidle" and from == "cidle" and resting else ("uuntap" if desired == "cidle" and from == "ctapidle" else "")
	if not clip.is_empty() and model.has_clip(desired) and model.play(clip):
		battle_audio.unit(model, clip.trim_prefix("u"))
		return
	model.play(desired)

func _list_look() -> ELListLook:
	if list_look == null or list_look_profile != profile:
		list_look = ELListLook.load(profile)
		list_look_profile = profile
	return list_look

## Neither original marks the chosen card or artifact on the rail (its
## buttons show Push only while held; the target prompt and cursor carry the
## choice), so the remake's accent outline is a helper-overlay readout.
func _selection_outline(button: Control) -> void:
	if not helper_overlay(): return
	var outline := ReferenceRect.new()
	outline.border_color = ACCENT
	outline.border_width = 2
	outline.editor_only = false
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## The frame tile in every card-rail slot past the last card or artifact
## (the original hand slots show their Type1 HERO_PANEL_3 layer when empty).
func _draw_hand_frames() -> void:
	if hand == null or profile == null or duel == null: return
	var pitch := 53.0
	var shown := hand.get_child_count()
	var offset := float(card_scroll.scroll_horizontal) if card_scroll != null else 0.0
	_list_look().draw_frames(hand_frames, Vector2(-offset, 0), shown, int(ceil((hand_frames.size.x + offset) / pitch)), pitch)

## The original Artifacts rail: the displayed hero's artifacts in the card
## slots with their icon and charges, greyed while the use gate refuses them;
## a click starts the use exactly like the hero's artifact command.
func _fill_artifact_rail(displayed: int) -> void:
	var commands := {}
	for ability: Dictionary in duel.abilities(displayed):
		if ability.get("effect") == "artifact": commands[int(ability.artifact)] = ability
	var items: Array = duel.heroes[displayed].get("artifacts", [])
	for index in items.size():
		var item: Dictionary = items[index]
		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(50, 50)
		var icon := int(item.custom.get("icon", -1)) if item.has("custom") else -1
		button.texture_normal = profile.icon_at(icon) if icon >= 0 else profile.card_icon(item.spell)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var key := "artifact:%d" % index
		var reason := duel.artifact_error(displayed, index)
		button.tooltip_text = ELCombatRail.artifact_tooltip(profile, item, duel.artifact_title(item)) + ("\n" + reason if not reason.is_empty() else "")
		button.set_meta("artifact_index", index)
		button.set_meta("charges", int(item.charges))
		button.disabled = not _human_turn() or not commands.has(index) or not duel.can_use_ability(displayed, key)
		_list_look().dress(button)
		if ability_selection.get("key") == key: _selection_outline(button)
		# The original prints the charges at the icon's lower right in its
		# glyph digits (ELListLook.number).
		var charges := _list_look().number(int(item.charges), profile.id == "el1")
		charges.set_meta("charge_label", true)
		button.add_child(charges)
		if commands.has(index): button.pressed.connect(_select_ability.bind(displayed, commands[index]))
		button.mouse_entered.connect(_hint.bind(button.tooltip_text.replace("\n", " — ")))
		hand.add_child(button)

func _side_name(side: int) -> String:
	if duel != null and duel.heroes[side].has("title"): return str(duel.heroes[side].title)
	if _hot_seat() and not String(duel_match.names[side]).is_empty(): return String(duel_match.names[side])
	return "Player 1" if side == 0 else ("Practice AI" if mode_select.selected == 0 else "Player 2")

## Remake setting "helper_overlay" (default off): remake-only English readouts
## and hints over the original combat screen.
func helper_overlay() -> bool:
	return settings != null and bool(settings.values.get("helper_overlay", false))

## The phase box in the original texts (EL1, EL2): while a
## spell or ability waits for its target, the two-line T_SPELL_PARAM prompt
## for the kind of target; else T_ATTACK_CAST_PHASE in the local side's attack,
## T_BLOCK_PHASE in its defence, T_ENEMY_TURN in the opponent's phases and
## T_WAIT during a hot-seat hand-over. After the battle: T_WINNER with the
## winner's name, or the edition's draw text.
func phase_caption() -> String:
	if duel.phase == ELDuel.Phase.FINISHED:
		if duel.winner >= 0: return _original_text("T_WINNER", "%s wins").replace("%s", _side_name(duel.winner))
		return _original_text("T_RR_DUEL_DRAW" if profile.id == "el2" else "T_VL_MATCH_DRAW", "Draw")
	if hot_pending: return _original_text("T_WAIT", "Wait")
	# While a fight plays out the original oval reads T_WAIT («Подождите…»).
	if _melee_busy(): return _original_text("T_WAIT", "Wait")
	var kind := target_prompt_kind()
	if kind >= 0:
		var first := _original_text("T_SPELL_PARAM" if kind == 0 else "T_SPELL_PARAM%02d" % (2 * kind + 1), "")
		var second := _original_text("T_SPELL_PARAM%02d" % (2 * kind + 2), "")
		return first if second.is_empty() else first + "\n" + second
	if not _local_side(duel.active_side()): return _original_text("T_ENEMY_TURN", "Enemy turn")
	return _original_text("T_ATTACK_CAST_PHASE" if duel.phase == ELDuel.Phase.ATTACK else "T_BLOCK_PHASE", "Attack" if duel.phase == ELDuel.Phase.ATTACK else "Defence")

## The original target parameter kind of the pending spell or ability, or -1:
## 0 hero, 1 creature, 2 own creature, 3 enemy creature, 4 creature or hero,
## 7 any graveyard, 8 own graveyard, 10 enchantment.
func target_prompt_kind() -> int:
	if not _human_turn(): return -1
	var target := ""
	var rule := {}
	if not ability_selection.is_empty():
		target = String(ability_selection.get("target", "none"))
	elif selection >= 0 and selection < duel.heroes[duel.active_side()].hand.size():
		var card: String = duel.heroes[duel.active_side()].hand[selection]
		rule = ELCatalog.rule(profile, card)
		target = String(rule.get("target", "none"))
		if card == "CHCM": return 3
	match target:
		"hero": return 0
		"any": return 4
		"enchantment": return 10
		"grave": return 8 if rule.get("effect") in ["repair", "exchange"] else 7
		"creature":
			if rule.get("own", false) or rule.get("effect") in ["trade", "exchange"]: return 2
			return 1
	return -1

func _original_text(key: String, fallback: String) -> String:
	var value := profile.text(key) if profile != null else key
	return fallback if value.is_empty() or value == key else value

## The original hand card tooltip, both games: "<type>: <name>" (T_SPELL_TYPE
## creature with its strength and health, _TYPE2 sorcery, _TYPE3 enchantment),
## then T_COST with the cost in T_MANA, then the description.
func card_tooltip(card: String) -> String:
	var spell_class := str(profile.table("CombatSpells").get(card, {}).get("Class", ""))
	var kind: String = {"Creature": "T_SPELL_TYPE", "Sorcery": "T_SPELL_TYPE2", "Enchantment": "T_SPELL_TYPE3"}.get(spell_class, "")
	var title := duel.card_name(card)
	var creature: Dictionary = profile.table("CombatCreatures").get(card, {})
	if spell_class == "Creature" and creature.has("Power"): title += " %d/%d" % [int(creature.Power), int(creature.get("Toughness", 0))]
	var lines: Array[String] = ["%s: %s" % [_original_text(kind, spell_class), title] if not kind.is_empty() else title]
	lines.append("%s %d %s" % [_original_text("T_COST", "Cost:"), duel.cost(card), _original_text("T_MANA", "ether")])
	var description := profile.card_description(card)
	if not description.is_empty() and description != card: lines.append(description)
	return "\n".join(lines)

## The original tooltip for a battle control, or {} for its plain text: a
## hand card's type, name, strength and cost lines (EL2 layout as
## seen in the original), a portrait's hero card, a value box's own line.
func _displayed_side() -> int:
	var side := 0 if mode_select.selected == 0 and not demo else duel.active_side()
	if _hot_seat() and hot_side >= 0: side = hot_side
	return side

func _tip_content(control: Control, at: Vector2) -> Dictionary:
	if duel == null or profile == null: return {}
	if control.has_meta("hero_side"):
		var side := int(control.get_meta("hero_side"))
		var h: Dictionary = duel.heroes[side]
		var displayed := _displayed_side()
		var own := side == displayed
		# The value boxes under the portrait name their own value.
		if at.y >= control.size.y - 22:
			var index := clampi(int(at.x / (control.size.x / 3.0)), 0, 2)
			return ELCombatTooltip.text_content(_control_tip("CombatTt%d" % ([1, 3, 5] if own else [2, 4, 6])[index]))
		if at.y > 60: return {}
		var title := _original_text(("CtrlDUMyHero" if own else "CtrlDUEnemyHero") if profile.id == "el1" else ("CtrlDuMyHero" if own else "CtrlDuEnemyHero"), _side_name(side))
		var health := "%s: %d" % [_original_text("CtrlTTCombatTt1" if profile.id == "el2" else "CtrlTtCombatTt1", "Health"), int(h.health)]
		var level := "%s: %d" % [_original_text("T_LEVEL", "Level"), int(h.get("level", 1))]
		var lines: Array = [level, health] if profile.id == "el1" else [health, level]
		if helper_overlay(): lines.append_array(control.tooltip_text.split("\n"))
		return ELCombatTooltip.hero_content(profile.id, portraits[side].texture, title, lines)
	return {}

## An original control's tooltip text from the Controls table, else "".
func _control_tip(control: String) -> String:
	if profile == null: return ""
	var key := profile.id + ":" + control
	if not _control_tips.has(key):
		_control_tips[key] = ""
		for row: Dictionary in profile.table("Controls").values():
			if str(row.get("Name", "")) == control and not str(row.get("ToolTip", "")).is_empty(): _control_tips[key] = profile.text(str(row.ToolTip))
	return String(_control_tips[key])

## A battle, save or setup message: always shown.
func _notice(text: String) -> void:
	notice.text = text
	notice.visible = true

## A remake prompt, refusal or hover readout in combat. The original has none
## (only the cursor and the phase box prompt), so it shows with the helper
## overlay only.
func _hint(text: String) -> void:
	notice.text = text
	notice.visible = helper_overlay()

func _spec_name(code: String) -> String:
	return profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Name", code)))

func _log(text: String) -> void:
	logs.append(text)
	if logs.size() > 6:
		logs.pop_front()
	log_text.text = "\n".join(logs)

func _style(fill: Color, border := Color("344441")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _label(text: String, size := 18, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 16
	for kind in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", kind, _style(Color("161913e8"), Color("66523a")))
		theme.set_stylebox("hover", kind, _style(Color("353329"), ACCENT))
		theme.set_stylebox("pressed", kind, _style(Color("483b2e"), ACCENT))
		theme.set_stylebox("disabled", kind, _style(Color("17171188")))
		theme.set_color("font_color", kind, INK)
		theme.set_color("font_disabled_color", kind, Color("81918b"))
	ui.theme = theme
	symbols = ELCombatSymbols.new()
	ui.add_child(symbols)
	notices = ELCombatNotices.new()
	ui.add_child(notices)
	status = _label("Choose your original game content from Menu.", 14, Color("e9e4d4"))
	status.position = Vector2(20, 16)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_y", 1)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(status)
	menu_button = _button("Menu", func(): menu.visible = not menu.visible)
	ui.add_child(menu_button)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.offset_left = -112
	menu_button.offset_right = -16
	menu_button.offset_top = 12
	menu_button.offset_bottom = 46
	menu = PanelContainer.new()
	ui.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -310
	menu.offset_right = -16
	menu.offset_top = 56
	menu.add_theme_stylebox_override("panel", _style(Color("111710f5")))
	menu.visible = false
	var menu_rows := VBoxContainer.new()
	menu_rows.add_theme_constant_override("separation", 8)
	menu.add_child(menu_rows)
	menu_rows.add_child(_label("DUEL", 20, ACCENT))
	profile_select = OptionButton.new()
	profile_select.add_item("Etherlords I", 0)
	profile_select.add_item("Etherlords II", 1)
	for i in 2:
		profile_select.set_item_disabled(i, not profiles.has("el1" if i == 0 else "el2"))
	profile_select.item_selected.connect(func(i: int):
		demo = false
		_start("el1" if i == 0 else "el2")
		menu.hide())
	menu_rows.add_child(profile_select)
	# Internal two-local-sides switch for prepared checks. Not shown: local
	# two-player play goes through the original HotSeat duel and its hand-over.
	mode_select = OptionButton.new()
	mode_select.add_item("Practice AI")
	mode_select.add_item("Two local sides")
	mode_select.item_selected.connect(func(_i: int): _refresh())
	mode_select.visible = false
	menu_rows.add_child(mode_select)
	menu_rows.add_child(_button("Main menu", _show_front_menu))
	menu_rows.add_child(_button("Duel screen…", _open_duel_screen))
	menu_rows.add_child(_button("Practice setup / Spellbooks…", _open_setup))
	menu_rows.add_child(_button("Campaigns…", _open_campaigns))
	menu_rows.add_child(_button("Save duel [F5]", _save_duel))
	menu_rows.add_child(_button("Load duel [F9]", _load_duel))
	menu_rows.add_child(_button("Surrender campaign battle", _surrender_encounter))
	menu_rows.add_child(_button("Surrender duel round", _surrender_round))
	menu_rows.add_child(_button("Watch / stop demo", func():
		if _campaign_battle() != null:
			_notice("Finish or surrender the campaign battle first.")
			return
		demo = not demo
		if demo and profile != null: _start(profile.id, match_options)
		menu.hide()
		_refresh()))
	menu_rows.add_child(_button("Game files…", _content_menu))
	menu_rows.add_child(_button("Options…", _open_battle_options))
	menu_rows.add_child(_button("Remake settings…", _open_settings))
	menu_rows.add_child(_button("Show / hide battle log [L]", func():
		log_text.visible = not log_text.visible
		menu.hide()))
	menu_rows.add_child(_label("Right-drag: orbit   Wheel: zoom\nR: reset camera   Space: end phase", 13, MUTED))
	log_text = RichTextLabel.new()
	ui.add_child(log_text)
	log_text.position = Vector2(20, 56)
	log_text.size = Vector2(470, 145)
	log_text.add_theme_font_size_override("normal_font_size", 14)
	log_text.add_theme_color_override("default_color", Color("e5e7d9"))
	log_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	log_text.add_theme_constant_override("shadow_offset_x", 1)
	log_text.add_theme_constant_override("shadow_offset_y", 1)
	log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_text.visible = false
	hud_root = Control.new()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_root)
	hud = ELHudFrame.new()
	hud_root.add_child(hud)
	rail = ELCombatRail.new()
	hud_root.add_child(rail)
	rail.tab_selected.connect(func(_artifacts: bool): _refresh())
	rail.strip_selected.connect(func(graveyard: bool):
		inspect_graveyard = graveyard
		_refresh())
	rail.strip_item.connect(_strip_pressed)
	for side in 2:
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_SCALE
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(portrait)
		portraits.append(portrait)
		var button := _button("", _target.bind(side))
		# The original portraits show no hover or press highlight.
		for style: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.focus_mode = Control.FOCUS_NONE
		button.set_meta("hero_side", side)
		hud_root.add_child(button)
		hero_buttons.append(button)
		var values := _label("", 13)
		values.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		values.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The rail draws the values in the original's boxes; this text stays
		# as the values' plain record.
		values.visible = false
		hud_root.add_child(values)
		hero_values.append(values)
		var name_label := _label("", 12)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(name_label)
		hero_names.append(name_label)
	# Godot's own tooltips stay invisible over the battle panel; ELCombatTooltip
	# draws them in the original frame.
	hud_root.theme = ELCombatTooltip.hidden_theme()
	phase_label = _label("DUEL", 15, ELCombatRail.COUNT_COLOR)
	# The original caption: bold Arial in the counts' gold, cap height 10 px
	# at 1024x768 ("Фаза атаки" in the second game's oval).
	var phase_font := SystemFont.new()
	phase_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	phase_font.font_weight = 700
	phase_label.add_theme_font_override("font", phase_font)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_root.add_child(phase_label)
	attack_button = ELCutPartButton.new()
	attack_button.pressed.connect(func():
		for c: Dictionary in duel.army(duel.active_side()):
			if duel.can_attack(c.id) and not duel.attacks.has(c.id): duel.toggle_attack(c.id))
	attack_button.tooltip_text = "Attack with all ready creatures"
	end_face = ELCutPartButton.new()
	end_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(end_face)
	end_button = _button("", _end_phase)
	auto_button = ELCutPartButton.new()
	auto_button.pressed.connect(_toggle_auto)
	auto_button.disabled = true
	hud_root.add_child(auto_button)
	auto_off_button = ELCutPartButton.new()
	auto_off_button.pressed.connect(func(): _set_auto(false))
	auto_off_button.visible = false
	hud_root.add_child(auto_off_button)
	game_menu_button = ELCutPartButton.new()
	game_menu_button.visible = false
	# Neither original battle screen has a menu control (no Controls entry
	# under CombatScreen); the remake's access stays in the corner but its art
	# shows only while the pointer is over it.
	game_menu_button.modulate.a = 0.0
	game_menu_button.mouse_entered.connect(func(): game_menu_button.modulate.a = 1.0)
	game_menu_button.mouse_exited.connect(func(): game_menu_button.modulate.a = 0.0)
	game_menu_button.pressed.connect(_open_game_menu)
	game_menu_button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			menu.visible = not menu.visible
			game_menu_button.accept_event())
	hud_root.add_child(game_menu_button)
	attack_button.disabled = true
	end_button.disabled = true
	end_face.mirror = end_button
	for button: ELCutPartButton in [attack_button, auto_button, end_face]:
		button.shutter = true
		button.push_on_hover = true
		button.dim_disabled = false
		button.focus_mode = Control.FOCUS_NONE
	hud_root.add_child(attack_button)
	end_button.focus_mode = Control.FOCUS_NONE
	hud_root.add_child(end_button)
	notice = _label("", 12, INK)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice.add_theme_constant_override("shadow_offset_y", 1)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(notice)
	hand_frames = Control.new()
	hand_frames.clip_contents = true
	hand_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_frames.draw.connect(_draw_hand_frames)
	hud_root.add_child(hand_frames)
	card_scroll = ScrollContainer.new()
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud_root.add_child(card_scroll)
	card_scroll.get_h_scroll_bar().value_changed.connect(func(_value: float): hand_frames.queue_redraw())
	hand = HBoxContainer.new()
	# Cards sit on the panel's 53 px slots.
	hand.add_theme_constant_override("separation", 3)
	card_scroll.add_child(hand)
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	rail.hand_scroll = card_scroll
	combat_tip = ELCombatTooltip.new()
	combat_tip.describe = _tip_content
	hud_root.add_child(combat_tip)
	ui.resized.connect(_layout_hud)
	# 4:3 windows share one stretched canvas size; the pixel floor follows the window.
	get_window().size_changed.connect(_layout_hud)
	inspector = PanelContainer.new()
	ui.add_child(inspector)
	inspector.add_theme_stylebox_override("panel", _style(Color("111710ed")))
	inspector.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	inspector.offset_left = 20
	inspector.offset_right = 350
	inspector.offset_top = -430
	inspector.offset_bottom = -180
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(inspector_scroll)
	inspector_rows = VBoxContainer.new()
	inspector_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector_rows)
	inspector.hide()
	power_dialog = ELCombatManaPanel.new()
	power_dialog.name = "ManaPanel"
	hud_root.add_child(power_dialog)
	power_amount = power_dialog.amount
	# The spell and value the choice is for, and what it will do, are remake
	# readouts on the X/limit tooltip.
	power_heading = _label("", 15)
	power_heading.hide()
	power_preview = _label("", 15)
	power_preview.hide()
	hud_root.add_child(power_heading)
	hud_root.add_child(power_preview)
	power_dialog.changed.connect(func(_value: int):
		_preview_power()
		_power_tooltip())
	power_dialog.confirmed.connect(_confirm_power)
	power_dialog.cancelled.connect(_cancel_power)
	_layout_hud()

func _overlay_open() -> bool:
	return (first_tutorial != null and first_tutorial.visible) or (options_host != null and options_host.is_visible_in_tree()) or movie_player != null or (front_menu != null and front_menu.is_visible_in_tree()) or (setup_panel != null and setup_panel.visible) or (menu != null and menu.visible) or (settings_dialog != null and settings_dialog.visible) or (campaign_setup != null and campaign_setup.visible) or (power_dialog != null and power_dialog.visible) or (tutorial_quit != null and tutorial_quit.visible) or (esc_menu != null and esc_menu.visible) or (replay_quit != null and replay_quit.visible) or replay_inventory != null

## First game: the tutorial panel of battles (one per view, sharing the
## settings' tutorial with the map).
func _first_tutorial_panel() -> ELFirstTutorialPanel:
	if first_tutorial == null or first_tutorial.profile != profile:
		if first_tutorial != null: first_tutorial.queue_free()
		first_tutorial = ELFirstTutorialPanel.new()
		ui.add_child(first_tutorial)
		first_tutorial.build(profile, ELFirstTutorial.for_settings(settings), ELFirstTutorial.COMBAT)
	first_tutorial.set_volume(float(settings.values.get("effects", 1.0)))
	return first_tutorial

## A battle opened for a player (campaign, Duel mode, practice): the first
## game's combat screen event.
func _first_tutorial_battle() -> void:
	if first_tutorial != null: first_tutorial.close()
	if duel == null or profile == null or profile.id != "el1" or demo: return
	_first_tutorial_panel().fire("COMBAT_SCREEN")

func _open_settings() -> void:
	menu.hide()
	if settings_dialog != null: settings_dialog.queue_free()
	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Remake settings"
	settings_dialog.exclusive = true
	ui.add_child(settings_dialog)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	settings_dialog.add_child(rows)
	for key: String in ["music", "ambience", "effects"]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := _label(key.capitalize(), 16)
		label.custom_minimum_size.x = 120
		row.add_child(label)
		var slider := HSlider.new()
		slider.custom_minimum_size.x = 240
		slider.min_value = 0
		slider.max_value = 100
		slider.value = float(settings.values[key]) * 100
		row.add_child(slider)
		var number := _label("%d%%" % slider.value, 16)
		number.custom_minimum_size.x = 50
		row.add_child(number)
		slider.value_changed.connect(func(value: float):
			settings.values[key] = value / 100.0
			number.text = "%d%%" % value
			if is_instance_valid(battle_audio): battle_audio.apply_volumes(settings.values)
			if front_menu != null: front_menu.apply_volumes(settings.values))
	var shadows := CheckButton.new()
	shadows.name = "Shadows"
	shadows.text = "Shadows"
	shadows.button_pressed = settings.values.shadows
	shadows.toggled.connect(func(enabled: bool):
		settings.values.shadows = enabled
		_apply_settings())
	rows.add_child(shadows)
	var soft_shadows := CheckButton.new()
	soft_shadows.name = "SoftShadows"
	soft_shadows.text = "Soft shadows"
	soft_shadows.tooltip_text = "Softens sun-shadow edges in battles and on Etherlords II maps. May reduce performance on slower devices. Requires shadows to be enabled."
	soft_shadows.button_pressed = bool(settings.values.soft_shadows)
	soft_shadows.disabled = not bool(settings.values.shadows)
	shadows.toggled.connect(func(enabled: bool): soft_shadows.disabled = not enabled)
	soft_shadows.toggled.connect(func(enabled: bool):
		settings.values.soft_shadows = enabled
		_apply_settings())
	rows.add_child(soft_shadows)
	var weather := CheckButton.new()
	weather.text = "Adventure weather effects"
	weather.button_pressed = settings.values.weather
	weather.toggled.connect(func(enabled: bool): settings.values.weather = enabled)
	rows.add_child(weather)
	var blood_toggle := CheckButton.new()
	blood_toggle.text = "Combat blood"
	blood_toggle.button_pressed = settings.values.blood
	blood_toggle.toggled.connect(func(enabled: bool):
		settings.values.blood = enabled
		if is_instance_valid(blood): blood.set_enabled(enabled))
	rows.add_child(blood_toggle)
	var tooltip_toggle := CheckButton.new()
	tooltip_toggle.text = "Map tooltips on hover"
	tooltip_toggle.tooltip_text = "Second game: show an object's tooltip when the cursor rests on it. The right mouse button shows it either way."
	tooltip_toggle.button_pressed = settings.values.map_tooltips
	tooltip_toggle.toggled.connect(func(enabled: bool): settings.values.map_tooltips = enabled)
	rows.add_child(tooltip_toggle)
	# The originals' Video key: no movies, own size, or fitted (shipped).
	var movie_row := HBoxContainer.new()
	rows.add_child(movie_row)
	var movie_label := _label("Movies", 16)
	movie_label.custom_minimum_size.x = 120
	movie_row.add_child(movie_label)
	var movie_mode := OptionButton.new()
	movie_mode.name = "MovieMode"
	for caption: String in ["Off", "Original size", "Fit to screen"]: movie_mode.add_item(caption)
	movie_mode.select(int(settings.values.movies))
	movie_mode.item_selected.connect(func(index: int):
		settings.values.movies = index
		ELMoviePlayer.mode = index)
	movie_row.add_child(movie_mode)
	# Optional smoothing of 3D edges; automatic keeps it off on software rendering.
	var smoothing_row := HBoxContainer.new()
	rows.add_child(smoothing_row)
	var smoothing_label := _label("Anti-aliasing", 16)
	smoothing_label.custom_minimum_size.x = 120
	smoothing_row.add_child(smoothing_label)
	var smoothing := OptionButton.new()
	smoothing.name = "Antialiasing"
	smoothing.tooltip_text = "Smooths the edges of the 3D map and battle scenes. Automatic uses 2x unless the graphics are rendered in software."
	for caption: String in ["Automatic", "Off", "2x", "4x"]: smoothing.add_item(caption)
	smoothing.select(int(settings.values.antialiasing) + 1)
	smoothing.item_selected.connect(func(index: int):
		settings.values.antialiasing = index - 1
		ELSettings.apply_display(get_viewport(), settings.values))
	smoothing_row.add_child(smoothing)
	var sharpen_row := HBoxContainer.new()
	rows.add_child(sharpen_row)
	var sharpen_label := _label("Sharpening", 16)
	sharpen_label.custom_minimum_size.x = 120
	sharpen_row.add_child(sharpen_label)
	var sharpen := OptionButton.new()
	sharpen.name = "Sharpening"
	sharpen.tooltip_text = "Sharpens the textures of the 3D map and battle scenes. The interface is not changed."
	for caption: String in ["Off", "Light", "Strong"]: sharpen.add_item(caption)
	sharpen.select(int(settings.values.sharpening))
	sharpen.item_selected.connect(func(index: int): settings.values.sharpening = index)
	sharpen_row.add_child(sharpen)
	var terrain_detail := CheckButton.new()
	terrain_detail.name = "TerrainDetail"
	terrain_detail.text = "Terrain detail"
	terrain_detail.tooltip_text = "Adds subtle surface detail to adventure terrain and battle ground. May reduce performance on slower devices."
	terrain_detail.button_pressed = bool(settings.values.terrain_detail)
	terrain_detail.toggled.connect(func(enabled: bool):
		settings.values.terrain_detail = enabled
		if is_instance_valid(arena): arena.set_detail(enabled)
		if campaign_view != null: campaign_view.apply_settings())
	rows.add_child(terrain_detail)
	var helper_toggle := CheckButton.new()
	helper_toggle.name = "HelperOverlay"
	helper_toggle.text = "Show remake helper overlay"
	helper_toggle.tooltip_text = "Remake-only readouts, hints and shortcut buttons over the original screens."
	helper_toggle.button_pressed = helper_overlay()
	helper_toggle.toggled.connect(func(enabled: bool):
		settings.values.helper_overlay = enabled
		_apply_settings())
	rows.add_child(helper_toggle)
	var export_log := Button.new()
	export_log.name = "ExportLog"
	export_log.text = "Export log…"
	export_log.tooltip_text = "Save or copy the game's log with the system information, to send it with a bug report."
	export_log.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	export_log.pressed.connect(func(): ELCrashReportBox.open(settings_dialog, {}))
	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 10)
	rows.add_child(tools_row)
	tools_row.add_child(export_log)
	# Adding, removing or switching games, outside a running campaign.
	if campaign_view == null and _campaign_battle() == null:
		var game_files := Button.new()
		game_files.name = "GameFiles"
		game_files.text = "Game files…"
		game_files.tooltip_text = "Add Etherlords or Etherlords II, remove one, or switch between them."
		game_files.pressed.connect(func():
			settings_dialog.hide()
			_open_content_setup())
		tools_row.add_child(game_files)
	settings_dialog.visibility_changed.connect(func():
		if not settings_dialog.visible:
			ELCrashReport.trace("settings: " + _options_summary())
			if not settings.save_file(): _notice("Could not save preferences.")
		_refresh())
	settings_dialog.popup_centered(Vector2i(500, 610))
	_refresh()

## The active game's preferences (each original keeps its own settings).
func _use_edition(edition: String) -> void:
	settings.use_edition(edition)
	ELMoviePlayer.mode = int(settings.values.movies)

## Options (or the remake dialog) changed the preferences: every running part
## takes the new values.
func _apply_settings() -> void:
	ELMoviePlayer.mode = int(settings.values.movies)
	ELSettings.apply_display(get_viewport(), settings.values)
	if is_instance_valid(arena) and arena.light != null:
		arena.light.shadow_enabled = settings.values.shadows
		arena.light.shadow_blur = 2.0 if settings.values.soft_shadows else 1.0
		arena.set_detail(bool(settings.values.terrain_detail))
	if is_instance_valid(blood): blood.set_enabled(bool(settings.values.blood))
	_preview_volumes(settings.values)
	if campaign_view != null: campaign_view.apply_settings()
	_refresh()

func _preview_volumes(values: Dictionary) -> void:
	if is_instance_valid(battle_audio): battle_audio.apply_volumes(values)
	if front_menu != null: front_menu.apply_volumes(values)
	if campaign_view != null: campaign_view.preview_volumes(values)

## The original Options screen over the battle, on its combat page; its
## Surrender concedes the campaign battle or the Duel mode round.
func _open_battle_options() -> void:
	menu.hide()
	var host := _battle_host()
	if host == null: return
	host.open_hosted("options", true, "combat")
	options_layer.show()
	host.show()

## The original screens hosted over the battle (Options, and in the second
## game the Esc menu's Load, Encyclopaedia and questions).
func _battle_host() -> ELFrontMenu:
	if profile == null or not ELFrontMenu.supports(profile):
		_notice("The original Options art is unavailable.")
		return null
	if options_host != null and options_host.edition != profile.id:
		options_layer.queue_free()
		options_host = null
	if options_host == null:
		options_layer = CanvasLayer.new()
		options_layer.layer = 6
		add_child(options_layer)
		options_host = ELFrontMenu.new()
		options_host.settings = settings
		options_layer.add_child(options_host)
		if not options_host.build({profile.id: profile}, profile.id):
			options_layer.queue_free()
			options_host = null
			return
		options_host.settings_previewed.connect(_preview_volumes)
		options_host.hosted_closed.connect(func():
			options_host.hide()
			options_layer.hide()
			_apply_settings()
			var command := options_host.options_ui.last_command
			options_host.options_ui.last_command = ""
			if command == "Surrender": _surrender_battle()
			# Another box replaced a waiting hand-over: show it again.
			if hot_pending: call_deferred("_show_handover"))
		options_host.slot_chosen.connect(_load_slot)
	options_host.options_ui.last_command = ""
	return options_host

func _surrender_battle() -> void:
	if _campaign_battle() != null: _surrender_encounter()
	elif duel_match != null: _surrender_round()
	else: _notice("Surrender ends campaign battles and Duel mode rounds.")

func _open_setup() -> void:
	if _campaign_battle() != null:
		_notice("Finish or surrender the campaign battle first.")
		return
	if profiles.is_empty():
		_content_menu()
		return
	menu.hide()
	if setup_panel != null:
		ui.remove_child(setup_panel)
		setup_panel.queue_free()
	setup_panel = ELDuelSetup.new()
	ui.add_child(setup_panel)
	setup_panel.add_theme_stylebox_override("panel", _style(Color("111710fc"), ACCENT))
	setup_panel.build(profiles, profile.id if profile != null else launch_profile, match_options)
	setup_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	setup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	setup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	setup_panel.begin.connect(func(edition: String, options: Dictionary, mode: int):
		demo = false
		mode_select.select(0)
		_start(edition, options)
		_first_tutorial_battle())
	setup_panel.resume_requested.connect(_load_duel)
	setup_panel.campaign_requested.connect(_open_campaigns)
	setup_panel.visibility_changed.connect(_refresh)
	_refresh()

func _open_campaigns() -> void:
	if _campaign_battle() != null:
		_notice("Finish or surrender the campaign battle first.")
		return
	if profiles.is_empty(): return
	menu.hide()
	if setup_panel != null: setup_panel.hide()
	if campaign_setup != null: campaign_setup.queue_free()
	campaign_setup = ELCampaignSetup.new()
	ui.add_child(campaign_setup)
	campaign_setup.build(profiles, profile.id if profile != null else launch_profile)
	campaign_setup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	campaign_setup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	campaign_setup.grow_vertical = Control.GROW_DIRECTION_BOTH
	campaign_setup.begin.connect(_begin_campaign)
	campaign_setup.resume_requested.connect(func(): _resume_campaign(false, ELSingleScenario.campaign_file(campaign_setup.chosen_edition())))
	campaign_setup.closed.connect(func(): campaign_setup.hide())

func _begin_campaign(edition: String, scenario: Dictionary, difficulty: int, restored: Dictionary = {}) -> void:
	ELCrashReport.trace("map load %s %s (difficulty %d%s)" % [edition, scenario.get("script", scenario.get("file_name", "?")), difficulty, ", from a save" if not restored.is_empty() else ""])
	ELCrashReport.where("map %s %s" % [edition, scenario.get("script", scenario.get("file_name", "?"))])
	if campaign_setup != null: campaign_setup.hide()
	_notice("Loading chapter…")
	# The original goes straight from the briefing to the map: no battle
	# scene or earlier map stays on screen while the chapter builds.
	var cover := _loading_cover()
	var stage_was_visible := stage.visible
	stage.hide()
	set_process(false)
	set_process_unhandled_input(false)
	# A second-game chapter chosen from the chapter list joins the campaign
	# order at its row (no carried data); menu chapters bring their progress.
	if edition == "el2" and restored.is_empty() and not scenario.has(ELSecondCampaign.KEY) and scenario.has("campaign") and profiles.has(edition):
		var progress := ELSecondCampaign.for_chapter(profiles[edition], str(scenario.campaign), scenario, difficulty)
		if not progress.is_empty():
			scenario = scenario.duplicate()
			scenario[ELSecondCampaign.KEY] = progress
	var previous := campaign_view
	if previous != null: previous.paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	campaign_view = ELAdventureView.new()
	add_child(campaign_view)
	_use_edition(edition)
	if not campaign_view.build(profiles[edition], scenario, settings, difficulty, restored):
		cover.queue_free()
		stage.visible = stage_was_visible
		_notice(campaign_view.error)
		campaign_view.queue_free()
		campaign_view = previous
		if previous != null: previous.paused = false
		else:
			set_process(true)
			set_process_unhandled_input(true)
		return
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	cover.queue_free()
	stage.hide()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	for player: Node in battle_audio.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D: player.stream_paused = true
	ui.hide()
	campaign_view.leave_requested.connect(_leave_campaign)
	campaign_view.resume_requested.connect(func(): _resume_campaign(false, ELSaveSlots.quick_load_path(campaign_view.state), edition))
	campaign_view.slot_requested.connect(_load_slot)
	campaign_view.encounter_requested.connect(_begin_encounter)
	campaign_view.chapter_requested.connect(func(next: Dictionary):
		if edition == "el1": _show_chapter_info(next, campaign_view.state.difficulty)
		else: _begin_campaign(edition, next, campaign_view.state.difficulty))
	campaign_view.campaign_map_requested.connect(_show_campaign_map)
	if campaign_view.director.encounter != null:
		var encounter := campaign_view.director.encounter
		_begin_encounter(encounter.hero_id, encounter.opponent_id)
		var combat_view: Dictionary = restored.camera.get("battle", {})
		var session := ELMatchSave.session(combat_view)
		_restore_orbit(session.camera)

## Black screen with a small caption over everything while a chapter loads.
func _loading_cover() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "ChapterLoading"
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	var caption := Label.new()
	caption.text = "Loading…"
	caption.add_theme_color_override("font_color", Color(0.85, 0.8, 0.68, 0.8))
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caption.grow_vertical = Control.GROW_DIRECTION_BOTH
	black.add_child(caption)
	add_child(layer)
	return layer

## True while a campaign battle is on screen.
func director_battle_open() -> bool:
	return _campaign_battle() != null and stage.visible

func _campaign_battle() -> ELDuel:
	return campaign_view.director.encounter.battle if campaign_view != null and campaign_view.director != null and campaign_view.director.encounter != null else null

func _begin_encounter(_hero: int, _opponent: int) -> void:
	var battle := _campaign_battle()
	if battle == null: return
	campaign_view.set_suspended(true)
	demo = false
	menu.hide()
	mode_select.select(0)
	mode_select.disabled = true
	profile_select.disabled = true
	_start(battle.profile.id, battle.setup, battle)
	ui.show()
	_first_tutorial_battle()
	set_process(true)
	set_process_unhandled_input(true)
	_notice("Defeat %s to continue. F5 saves both the battle and campaign." % _side_name(1) if helper_overlay() else "")
	if not battle.load_note.is_empty(): _notice(battle.load_note)

func _return_from_encounter() -> void:
	if _campaign_battle() == null or (duel.phase != ELDuel.Phase.FINISHED and campaign_view.state.outcome.is_empty()): return
	if not campaign_view.director.finish_encounter():
		_notice(campaign_view.director.error)
		return
	menu.hide()
	stage.hide()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	for player: Node in battle_audio.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D: player.stream_paused = true
	ui.hide()
	mode_select.disabled = false
	profile_select.disabled = false
	set_process(false)
	set_process_unhandled_input(false)
	campaign_view.set_suspended(false)
	ELCrashReport.where("map %s (after a battle)" % campaign_view.state.map.profile.id)

func _surrender_encounter() -> void:
	if _campaign_battle() == null:
		_notice("There is no active campaign battle.")
		return
	if duel.phase != ELDuel.Phase.FINISHED:
		duel.heroes[0].health = 0
		duel._check_winner()
	_return_from_encounter()

## `newest` (the front menu's Load) also considers the second game's
## between-chapter autosave and opens whichever save is more recent.
## `manual` is a campaign or single-mission save; empty means the campaign
## save of `edition` (each edition keeps its own).
func _resume_campaign(newest := false, manual := "", edition := "") -> void:
	if edition.is_empty(): edition = front_menu.edition if front_menu != null and not front_menu.edition.is_empty() else (profile.id if profile != null else "el1")
	if manual.is_empty(): manual = ELSingleScenario.campaign_file(edition)
	var automatic := ELSecondCampaign.AUTOSAVE
	if newest and edition == "el2" and profiles.has("el2") and FileAccess.file_exists(automatic) and (not FileAccess.file_exists(manual) or FileAccess.get_modified_time(automatic) >= FileAccess.get_modified_time(manual)):
		var progress := ELSecondCampaign.read(automatic)
		if not progress.is_empty():
			_show_campaign_map(progress)
			return
	var codec := ELAdventureSave.new()
	var restored := codec.read(manual, profiles)
	if restored.is_empty():
		if campaign_view != null: campaign_view.notice.text = codec.error
		else: _notice(codec.error)
		return
	_begin_campaign(restored.state.map.profile.id, {"file_name": restored.state.map.id, "script": restored.state.script_name}, restored.state.difficulty, restored)

## A row of a save list (ELSaveSlots): an adventure save, or the second game's
## between-chapter campaign autosave, which opens the next chapter's map.
func _load_slot(row: Dictionary) -> void:
	ELCrashReport.trace("load %s" % String(row.get("path", "?")).get_file())
	if row.get("type") == ELSaveSlots.PROGRESS:
		var progress := ELSecondCampaign.read(str(row.path))
		if not progress.is_empty():
			_show_campaign_map(progress)
			return
		if campaign_view != null: campaign_view.notice.text = "The campaign autosave could not be read."
		else: _notice("The campaign autosave could not be read.")
		return
	_resume_campaign(false, str(row.path), str(row.get("edition", "")))

## Second game: leave the finished chapter for the next chapter's global map.
## Without the original front end, the chapter starts directly.
func _show_campaign_map(progress: Dictionary) -> void:
	if campaign_view != null: _leave_campaign()
	if (front_menu != null or _show_front_menu()) and front_menu.show_campaign_map(progress):
		_show_front_menu_layer()
		return
	var row := ELSecondCampaign.chapter(profiles["el2"], progress) if profiles.has("el2") else {}
	if not row.is_empty(): _begin_campaign("el2", row, int(progress.difficulty))

## First game: the next chapter goes through the campaign info screen (its
## description, movie and voiced briefing) as after every chapter result in
## the original. Without the front end, the chapter starts directly.
func _show_chapter_info(next: Dictionary, difficulty: int) -> void:
	if campaign_view != null: _leave_campaign()
	if front_menu != null or _show_front_menu():
		if front_menu.edition != "el1": front_menu.use_edition("el1")
	if front_menu != null and front_menu.edition == "el1" and front_menu.show_chapter_info(next, difficulty):
		_show_front_menu_layer()
		return
	_begin_campaign("el1", next, difficulty)

func _show_front_menu_layer() -> void:
	menu.hide()
	if setup_panel != null: setup_panel.hide()
	if campaign_setup != null: campaign_setup.hide()
	front_layer.show()
	front_menu.show()
	ELCrashReport.where("menu")

func _leave_campaign() -> void:
	remove_child(campaign_view)
	campaign_view.queue_free()
	campaign_view = null
	stage.show()
	stage.process_mode = Node.PROCESS_MODE_INHERIT
	camera.current = true
	for player: Node in battle_audio.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D: player.stream_paused = false
	ui.show()
	set_process(true)
	set_process_unhandled_input(true)
	_refresh()
	if front_menu != null: _show_front_menu()

func _save_duel() -> void:
	if duel == null: return
	ELCrashReport.trace("battle save")
	menu.hide()
	if _campaign_battle() != null:
		var view := campaign_view.camera_state()
		view.battle = {"camera": [camera_yaw, camera_pitch, camera_distance]}
		# The original saves only on the map; the remake also keeps the battle,
		# in the quick-save slot.
		var failed := ELSaveSlots.write(ELSaveSlots.quick_name(campaign_view.state.map.profile), campaign_view.director, view)
		_notice("Campaign and battle saved. Press F9 to resume." if failed.is_empty() else failed)
		return
	if combat_tutorial != null:
		_notice("The combat tutorial cannot be saved.")
		return
	var session := {"mode": mode_select.selected, "camera": [camera_yaw, camera_pitch, camera_distance]}
	if duel_match != null: session.duel_match = duel_match.snapshot()
	_notice("Duel saved. Press F9 to resume." if duel.save_file("user://duel-save.json", session) else duel.error)
	_refresh()

func _load_duel() -> void:
	menu.hide()
	ELCrashReport.trace("battle load")
	if _campaign_battle() != null:
		_resume_campaign(false, ELSaveSlots.quick_load_path(campaign_view.state), campaign_view.state.map.profile.id)
		return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://duel-save.json")) if FileAccess.file_exists("user://duel-save.json") else null
	if document is not Dictionary:
		_notice("No readable duel save was found.")
		return
	if document.get("state") is not Dictionary:
		_notice("The duel save is incomplete.")
		return
	var edition := String(document.get("state", {}).get("profile", ""))
	if not profiles.has(edition):
		_notice("Import the original game edition used by this save.")
		return
	var restored := ELDuel.new()
	if not restored.restore(profiles[edition], document):
		_notice(restored.error)
		return
	var session := ELMatchSave.session(document.get("session"))
	mode_select.select(session.mode)
	demo = false
	# A Duel mode match saved mid-round continues with its tallies.
	var saved_match: Variant = document.get("session", {}).get("duel_match") if document.get("session") is Dictionary else null
	var restored_match: ELDuelMatch = null
	if saved_match is Dictionary:
		restored_match = ELDuelMatch.new()
		if not restored_match.restore(profiles[edition], saved_match) or restored_match.finished(): restored_match = null
	_match_starting = restored_match != null
	_start(edition, restored.setup, restored)
	_restore_orbit(session.camera)
	_match_starting = false
	duel_match = restored_match
	# The original opens the report only when a match starts, not on a load.
	_drop_duel_report()
	# Hot seat: a load always hands the screen over again (the box first).
	hot_side = -1
	hot_pending = false
	_refresh()
	# A round that had already ended was recorded before the save.
	match_round_recorded = restored.phase == ELDuel.Phase.FINISHED
	match_clock = 0.0
	match_result_shown = false
	_notice(restored.load_note if not restored.load_note.is_empty() else "Saved duel restored.")

func _refresh_inspector() -> void:
	_fill_strip()
	if inspector == null: return
	for child in inspector_rows.get_children():
		inspector_rows.remove_child(child)
		child.queue_free()
	var entity := duel.entity(selected_creature)
	# Remake readout: every command it offers is also on the strip, rails or field.
	inspector.visible = not entity.is_empty() and not _overlay_open() and helper_overlay()
	if entity.is_empty(): return
	var title := _side_name(selected_creature) if selected_creature < 2 else duel.card_name(entity.card)
	inspector_rows.add_child(_label(title, 18, ACCENT))
	if selected_creature < 2 and entity.get("spec", "NONE") != "NONE":
		var row: Dictionary = profile.table("HeroesSpecs").get(entity.spec, {})
		var spec_line := _label("Specialization: %s\n%s" % [_spec_name(entity.spec), profile.text(str(row.get("Desc", "")))], 13)
		spec_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spec_line.custom_minimum_size.x = 290
		spec_line.set_meta("spec", entity.spec)
		inspector_rows.add_child(spec_line)
	if selected_creature >= 2:
		var flags: Array[String] = []
		for flag: String in entity.flags: flags.append(ELCatalog.flag_name(flag))
		var stats := "%d / %d · %s" % [entity.power, entity.toughness - entity.damage, ", ".join(flags)]
		if duel.in_plane(selected_creature): stats += "\nPale aspect: common magic cannot affect it; it cannot attack or block."
		var line := _label(stats, 13)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 290
		inspector_rows.add_child(line)
		if duel.can_attack(selected_creature):
			var compulsory := duel.has_flag(selected_creature, "Berserk") and duel.attacks.has(selected_creature)
			var attack_price := duel.attack_cost(selected_creature)
			var attack_text := "Attack" + (" · %d ether" % attack_price if attack_price > 0 else "")
			var command := _button("Must attack" if compulsory else ("Recall" if duel.attacks.has(selected_creature) else attack_text), func():
				if _human_turn() and not duel.toggle_attack(selected_creature): _hint(duel.error))
			command.set_meta("attack", selected_creature)
			command.tooltip_text = "Ether is paid when the creature is sent to attack. Recalling it does not refund the cost." if attack_price > 0 else ""
			command.disabled = not _human_turn() or compulsory
			inspector_rows.add_child(command)
		for ability: Dictionary in duel.abilities(selected_creature):
			var price := " · %d ether" % ability.cost if ability.cost >= 0 else " · X ether"
			if ability.has("health_cost"): price += " + %d health" % ability.health_cost
			var button := _button("%s%s" % [ability.name, price], _select_ability.bind(selected_creature, ability))
			button.set_meta("ability", ability.key)
			button.disabled = not _human_turn() or not duel.can_use_ability(selected_creature, ability.key)
			inspector_rows.add_child(button)
		for effect: Dictionary in entity.get("temporary", []):
			if effect.kind == "illusion": inspector_rows.add_child(_label("Shadows: until the opponent's turn ends", 12, ACCENT))
	else:
		# While a graveyard entry or enchantment is being chosen here, the hero's
		# commands are hidden so the choices stay in view on compact screens.
		var choosing: bool = (inspect_graveyard and (not ability_selection.is_empty() or selection >= 0)) or ability_selection.get("target") == "enchantment"
		for ability: Dictionary in ([] if choosing else duel.abilities(selected_creature)):
			var text := "%s · %d ether" % [ability.name, ability.cost]
			if ability.effect == "artifact": text = "%s · artifact · %d charges" % [ability.name, ability.charges]
			var button := _button(text, _select_ability.bind(selected_creature, ability))
			button.set_meta("ability", ability.key)
			button.disabled = not _human_turn() or not duel.can_use_ability(selected_creature, ability.key)
			if ability.effect == "artifact":
				var reason := duel.artifact_error(selected_creature, int(ability.artifact))
				button.tooltip_text = duel.profile.text(String(duel.profile.table("CombatSpells")[ability.card].get("ToolTip", ""))) + ("\n" + reason if not reason.is_empty() else "")
			inspector_rows.add_child(button)
		inspector_rows.add_child(_button("Enchantments" if inspect_graveyard else "Graveyard (%d)" % entity.grave.size(), func():
			inspect_graveyard = not inspect_graveyard
			_refresh_inspector()))
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(290, 90)
	inspector_rows.add_child(list_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(rows)
	if inspect_graveyard and selected_creature < 2:
		for index in range(entity.grave.size() - 1, -1, -1):
			var card: String = entity.grave[index]
			var choice := _grave_choice(index)
			var row: Control = _label(duel.card_name(card), 14) if choice.is_empty() else _button(duel.card_name(card), choice.action)
			if not choice.is_empty():
				row.set_meta("grave_index", index)
				(row as Button).disabled = not choice.enabled
			row.tooltip_text = profile.card_description(card)
			rows.add_child(row)
	else:
		for enchantment: Dictionary in entity.enchantments:
			var row := _button(duel.card_name(enchantment.card), _remove_selected_enchantment.bind(selected_creature, int(enchantment.id)))
			row.set_meta("enchantment", enchantment.id)
			if enchantment.card == "STSI":
				var next_turn := duel.turn_serial + (2 if enchantment.owner == duel.attacker else 1)
				row.text += "\nNext upkeep: %d ether" % duel.stasis_upkeep(enchantment, next_turn)
			row.tooltip_text = profile.card_description(enchantment.card)
			row.disabled = not _removal_allowed(enchantment)
			row.add_theme_color_override("font_disabled_color", INK)
			rows.add_child(row)

## What a click on graveyard entry `index` of the selected hero does while a
## spell or ability waits for one: {action, enabled}, or {} when nothing does.
func _grave_choice(index: int) -> Dictionary:
	var held: String = duel.heroes[duel.active_side()].hand[selection] if selection >= 0 and selection < duel.heroes[duel.active_side()].hand.size() else ""
	var revival: bool = not held.is_empty() and ELCatalog.rule(profile, held).get("effect") == "pale_revival"
	if selection >= 0 and exchange_target >= 2 and (selected_creature == duel.active_side() or revival):
		return {"action": _select_grave_creature.bind(index), "enabled": _human_turn() and duel.valid_grave_targets(held).has(selected_creature * ELDuel.GRAVE_SIDE + index if revival else index)}
	if ability_selection.get("target") == "grave":
		return {"action": _select_grave_entry.bind(index), "enabled": _human_turn() and duel.grave_ability_targets(ability_selection.source, ability_selection.key, selected_creature).has(index)}
	if ability_selection.is_empty() and not held.is_empty() and ELCatalog.rule(profile, held).get("effect") in ["reanimate", "repair"]:
		return {"action": _reanimate.bind(index), "enabled": _human_turn() and duel.valid_grave_targets(held, selected_creature).has(index)}
	return {}

## Whether the pending spell or ability may take this enchantment of the
## selected character.
func _removal_allowed(enchantment: Dictionary) -> bool:
	var spell_card: String = duel.heroes[duel.active_side()].hand[selection] if selection >= 0 and selection < duel.heroes[duel.active_side()].hand.size() else ""
	var spell_effect: String = ELCatalog.rule(profile, spell_card).get("effect", "") if not spell_card.is_empty() else ""
	var dispelling: bool = spell_effect == "dispel" or (spell_effect == "trade" and exchange_target >= 2) or ability_selection.get("target") == "enchantment"
	# Weaving copies a caster's enchantment without removing it.
	var copying: bool = ability_selection.get("key") == "weave" and not enchantment.get("fixed", false)
	return _human_turn() and dispelling and (ability_selection.get("key") == "disenchant" or copying or duel.dispellable(selected_creature, enchantment)) and not (spell_effect == "trade" and selected_creature == exchange_target)

## Enchantments whose own ability a creature uses from the strip.
const ENCHANTMENT_ABILITIES := {"ENFL": "wake", "WNPZ": "unparalyze", "IMMB": "awaken"}

## The ability an enchantment of the selected character grants, or {}.
func _enchantment_ability(enchantment: Dictionary) -> Dictionary:
	for ability: Dictionary in duel.abilities(selected_creature):
		if selected_creature < 2 and int(ability.get("enchantment", -1)) == int(enchantment.id): return ability
		if selected_creature >= 2 and ability.key == ENCHANTMENT_ABILITIES.get(enchantment.card, ""): return ability
	return {}

## A selected creature's own abilities, shown on the upper strip after its
## enchantments with the card's AbilityIcon; those an enchantment grants are
## reached through that enchantment's icon instead.
func _strip_abilities() -> Array[Dictionary]:
	var subject := _strip_subject()
	var result: Array[Dictionary] = []
	if subject < 2 or not duel.creatures.has(subject): return result
	for ability: Dictionary in duel.abilities(subject):
		# An enchantment's ability starts from its icon; first-game
		# enfeeblement is no enchantment, so its break ability is listed here.
		var granted_by: String = ENCHANTMENT_ABILITIES.find_key(ability.key) if ENCHANTMENT_ABILITIES.values().has(ability.key) else ""
		if granted_by.is_empty() or duel._enchantment_count(subject, granted_by) == 0: result.append(ability)
	return result

## The CombatSpells row whose ability icon and text stand for `ability`.
func _ability_card(ability: Dictionary) -> String:
	var subject := _strip_subject()
	if ability.key == "dissipate": return "AOUP"
	if ability.key == "courtesy": return "AOLS"
	if ENCHANTMENT_ABILITIES.values().has(ability.key): return String(ENCHANTMENT_ABILITIES.find_key(ability.key))
	var manifest: Dictionary = ELCatalog.PALE_RACE_ABILITIES.get(duel.race(subject), {})
	if manifest.get("key", "") == ability.key: return String(manifest.text)
	return String(duel.creatures[subject].card)

## The upper icon strip: the selected character's enchantments, or the
## selected hero's graveyard, oldest first. An entry is offered while the
## pending spell or ability can take it; with nothing pending, an
## enchantment that grants the character's own ability starts that ability.
## Whose list the upper strip shows: the selection, or while the right
## button is held (without turning the camera) the character under the
## pointer; in Graveyard mode only a hero (EL2, EL1).
func _strip_subject() -> int:
	if strip_preview >= 0 and duel.entity(strip_preview).size() > 0 and (not inspect_graveyard or strip_preview < 2): return strip_preview
	return selected_creature

## Right button: held still it previews the hovered character's strip
## list; dragged past 6 px it turns the camera (remake convenience, as on
## the adventure map; the original turns the battle camera at the edges).
func _right_button(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		right_down = event.pressed
		right_from = event.position
		orbiting = false
		_set_strip_preview(combat_hover if event.pressed else -1)
	elif event is InputEventMouseMotion and right_down:
		if not orbiting and event.position.distance_to(right_from) > 6.0:
			orbiting = true
			_set_strip_preview(-1)
		elif not orbiting:
			_set_strip_preview(combat_hover)

func _set_strip_preview(id: int) -> void:
	if id == strip_preview: return
	strip_preview = id
	_fill_strip()

func _fill_strip() -> void:
	var subject := _strip_subject()
	if rail == null or rail.strip == null or duel == null: return
	rail.show_strip(inspect_graveyard)
	var list: Array[Dictionary] = []
	var entity := duel.entity(subject) if subject >= 0 else {}
	var shown := -1 if entity.is_empty() or (inspect_graveyard and subject >= 2) or (_hot_seat() and hot_pending) else subject
	if shown >= 0 and inspect_graveyard:
		for index in entity.grave.size():
			var card: String = entity.grave[index]
			var choice := _grave_choice(index)
			list.append({"icon": profile.card_icon(card), "tooltip": "%s\n%s" % [duel.card_name(card), profile.card_description(card)],
				"enabled": choice.get("enabled", false), "meta": {"grave_index": index, "card": card}})
	elif shown >= 0:
		var pending := selection >= 0 or not ability_selection.is_empty()
		for enchantment: Dictionary in entity.enchantments:
			var ability := _enchantment_ability(enchantment)
			var tip := duel.card_name(enchantment.card)
			if profile.id == "el2" and not ability.is_empty() and int(ability.get("cost", -1)) >= 0 and profile.text("T_ENCHANTMENT_COST_TT").count("%") == 2:
				tip = profile.text("T_ENCHANTMENT_COST_TT") % [tip, int(ability.cost)]
			var own: bool = subject == duel.active_side() or (subject >= 2 and int(entity.get("owner", -1)) == duel.active_side())
			var enabled: bool = _removal_allowed(enchantment) if pending else (not ability.is_empty() and own and _human_turn() and duel.can_use_ability(subject, ability.key))
			list.append({"icon": profile.card_icon(enchantment.card), "tooltip": tip, "enabled": enabled, "meta": {"enchantment": int(enchantment.id), "card": enchantment.card}})
		var owned: bool = subject >= 2 and int(entity.get("owner", -1)) == duel.active_side()
		for ability: Dictionary in _strip_abilities():
			var card := _ability_card(ability)
			var tip := String(ability.name)
			var about := profile.text(str(profile.table("CombatSpells").get(card, {}).get("AbilityText", "")))
			if profile.id == "el2" and int(ability.get("cost", -1)) >= 0 and profile.text("T_ENCHANTMENT_COST_TT").count("%") == 2:
				tip = profile.text("T_ENCHANTMENT_COST_TT") % [tip, int(ability.cost)]
			if not about.is_empty() and about != tip: tip += "\n" + about
			var icon := int(profile.table("CombatSpells").get(card, {}).get("AbilityIcon", 0))
			list.append({"icon": profile.icon_at(icon) if icon > 0 else profile.card_icon(card), "tooltip": tip,
				"enabled": not pending and owned and _human_turn() and duel.can_use_ability(subject, ability.key), "meta": {"ability": ability.key, "card": card}})
	var signature := "%d:%s:" % [shown, inspect_graveyard]
	for item: Dictionary in list: signature += str(item.meta.get("card", "")) + ","
	rail.strip.set_items(list, signature)

func _strip_pressed(index: int) -> void:
	var subject := _strip_subject()
	var entity := duel.entity(subject) if subject >= 0 else {}
	if entity.is_empty(): return
	if inspect_graveyard:
		if subject >= 2 or index >= entity.grave.size(): return
		var choice := _grave_choice(index)
		if not choice.is_empty() and choice.enabled: choice.action.call()
		return
	if index >= entity.enchantments.size():
		var own := _strip_abilities()
		if index - entity.enchantments.size() >= own.size() or selection >= 0 or not ability_selection.is_empty(): return
		var chosen: Dictionary = own[index - entity.enchantments.size()]
		if subject >= 2 and int(entity.owner) == duel.active_side() and _human_turn() and duel.can_use_ability(subject, chosen.key): _select_ability(subject, chosen)
		return
	var enchantment: Dictionary = entity.enchantments[index]
	if selection >= 0 or not ability_selection.is_empty():
		if _removal_allowed(enchantment): _remove_selected_enchantment(subject, int(enchantment.id))
		return
	var ability := _enchantment_ability(enchantment)
	if not ability.is_empty() and _human_turn() and duel.can_use_ability(subject, ability.key): _select_ability(subject, ability)

func _select_ability(source: int, ability: Dictionary) -> void:
	selection = -1
	selection_power = 0
	exchange_target = -1
	ability_selection.clear()
	if ability.get("variable", false):
		_open_ability_power(source, ability)
		return
	if ability.target == "none":
		if not duel.use_ability(source, ability.key): _hint(duel.error)
	else:
		ability_selection = {"source": source, "key": ability.key, "target": ability.target, "second": ability.get("second", "")}
		var wanted := "a creature or hero" if ability.target == "any" else ("a hero's graveyard" if ability.target == "grave" else "a " + str(ability.target))
		_hint("%s: choose %s. Esc cancels." % [ability.name, wanted])
	_refresh()

func _select_grave_entry(index: int) -> void:
	if not _human_turn() or ability_selection.get("target") != "grave": return
	if duel.use_ability(ability_selection.source, ability_selection.key, selected_creature, index):
		ability_selection.clear()
		inspect_graveyard = false
	else: _hint(duel.error)
	_refresh()

func _reanimate(index: int) -> void:
	if not _human_turn() or selection < 0: return
	if duel.cast(selection, selected_creature, index):
		selection = -1
		inspect_graveyard = false
		_hint("Creature returned to play.")
	else: _hint(duel.error)
	_refresh()

func _select_grave_creature(index: int) -> void:
	if not _human_turn() or selection < 0 or exchange_target < 2: return
	var hand_index := selection
	var sacrifice := exchange_target
	# Pale revival names the graveyard as well as the entry.
	var revival: bool = ELCatalog.rule(profile, duel.heroes[duel.active_side()].hand[hand_index]).get("effect") == "pale_revival"
	selection = -1
	exchange_target = -1
	if duel.cast(hand_index, sacrifice, selected_creature * ELDuel.GRAVE_SIDE + index if revival else index):
		_hint("Creature returned to play.")
	else:
		selection = hand_index
		exchange_target = sacrifice
		_hint(duel.error)
	_refresh()

func _remove_selected_enchantment(target: int, enchantment_id: int) -> void:
	if selection >= 0 and ability_selection.is_empty():
		var hand_index := selection
		var effect: String = ELCatalog.rule(profile, duel.heroes[duel.active_side()].hand[hand_index]).get("effect", "")
		var holder := exchange_target if effect == "trade" else target
		if duel.cast(hand_index, holder, enchantment_id):
			selection = -1
			exchange_target = -1
			_hint("Enchantment removed.")
		else: _hint(duel.error)
		_refresh()
		return
	if ability_selection.is_empty(): return
	if duel.use_ability(ability_selection.source, ability_selection.key, target, enchantment_id):
		ability_selection.clear()
	else: _hint(duel.error)
	_refresh()

func _layout_hud() -> void:
	if hud_root == null:
		return
	var factor := clampf(ui.size.x / 1100.0, 1.0, 1.5)
	# Never below the original's one-to-one pixel size: a 1024x768 window
	# gets the original 1024 panel (six card slots, full-size digits) and
	# 800x600 its 800 panel, as the originals draw them.
	var window := get_window()
	if window != null and window.size.x > 0 and ui.size.x > 0:
		factor = maxf(factor, ui.size.x / float(window.size.x))
	hud_root.scale = Vector2.ONE * factor
	if notices != null: notices.ui_scale = factor
	hud_root.size = ui.size / factor
	hud.size = hud_root.size
	hud.queue_redraw()
	rail.size = hud_root.size
	rail.layout()
	if power_dialog != null:
		power_dialog.size = hud_root.size
		power_dialog.layout()
	var w := hud_root.size.x
	var h := hud_root.size.y
	for side in 2:
		var x := 0.0 if side == 0 else w - 80
		portraits[side].position = Vector2(x + 3, h - 111)
		portraits[side].size = Vector2(74, 55)
		hero_buttons[side].position = Vector2(x, h - 115)
		hero_buttons[side].size = Vector2(80, 115)
		hero_values[side].position = Vector2(x + 1, h - 20)
		hero_values[side].size = Vector2(77, 20)
		hero_names[side].position = Vector2(x - 5, h - 137)
		hero_names[side].size = Vector2(90, 20)
	if ELHudFrame.wide_layout(profile, w):
		# The original's 1024 layout: the oval (488,535)-(729,600) beside the buttons.
		phase_label.position = Vector2(w - 524, h - 57)
		phase_label.size = Vector2(217, 46)
	else:
		phase_label.position = Vector2(w - 296, h - 109)
		phase_label.size = Vector2(118, 43)
	# The original 1024 places: CombatMenu1 (509,542) and CombatMenu2
	# (564,544) of the 800 panel moved right by 224 and down by 168.
	attack_button.position = Vector2(w - 291, h - 58)
	end_face.position = Vector2(w - 236, h - 56)
	auto_button.position = Vector2(w - 181, h - 58)
	# The original top-right place (735,10 of 800) holds the remake's Menu
	# button, so the stop control sits just to its left.
	auto_off_button.position = Vector2(w - 165, 10)
	game_menu_button.position = Vector2(w - 16 - game_menu_button.size.x, 10)
	_place_end_button()
	# The remake's notice line sits above the upper icon strip.
	notice.position = Vector2(134, h - 160)
	notice.size = Vector2(w - 445, 37)
	var rail_rect := rail.hand_rect()
	card_scroll.position = rail_rect.position
	card_scroll.size = rail_rect.size
	hand_frames.position = rail_rect.position
	hand_frames.size = rail_rect.size
	hand_frames.queue_redraw()

func _place_end_button() -> void:
	if hud_root == null or end_button == null: return
	var w := hud_root.size.x
	var h := hud_root.size.y
	var plain := end_button.text.is_empty()
	# The socket's art (end_face) shows its states; only the text control is styled.
	end_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new() if plain else _style(Color("111710ed"), ACCENT))
	end_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new() if plain else _style(Color(0.9, 0.7, 0.3, 0.13), ACCENT))
	end_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new() if plain else _style(Color(0.9, 0.7, 0.3, 0.3), ACCENT))
	end_button.add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new() if plain else _style(Color(0.9, 0.7, 0.3, 0.3), ACCENT))
	end_button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new() if plain else _style(Color(0, 0, 0, 0.3), Color.TRANSPARENT))
	if end_face != null: end_face.visible = plain
	if end_button.text.is_empty():
		end_button.position = Vector2(w - 235, h - 55)
		end_button.size = Vector2(46, 46)
	else:
		# Above the panel, clear of the sockets and the enemy portrait.
		end_button.size = Vector2(maxf(150, end_button.get_minimum_size().x), 34)
		end_button.position = Vector2(w - 182 - end_button.size.x, h - 154)

## Game files screen: which games are present, adding or removing one, and
## switching between them.
func _content_menu() -> void:
	_open_content_setup()

## Game files import screen (ELContentSetup) over everything else; `edition`
## is the game shown first.
func _open_content_setup(edition := "") -> void:
	if content_setup != null: return
	if campaign_view != null or _campaign_battle() != null:
		_notice("Leave the campaign before changing game files.")
		return
	if menu != null: menu.hide()
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	content_setup = ELContentSetup.new()
	for each: String in profiles: content_setup.mounted[each] = profiles[each].root
	if edition.is_empty(): edition = profile.id if profile != null else launch_profile
	content_setup.selected = edition if edition in ELContentLibrary.EDITIONS else "el1"
	layer.add_child(content_setup)
	var changed := [false]
	var close := func():
		layer.queue_free()
		content_setup = null
	content_setup.closed.connect(func():
		close.call()
		# With nothing mounted the screen comes back; after a removal the
		# front end is built again for the games that are left.
		if profiles.is_empty(): _content_menu.call_deferred()
		elif changed[0] or profile == null: _restart_after_content_change(profile.id if profile != null else ""))
	content_setup.removed.connect(func(removed_edition: String):
		changed[0] = true
		profiles.erase(removed_edition)
		if profile != null and profile.id == removed_edition: profile = null)
	content_setup.chosen.connect(func(chosen: String):
		close.call()
		_restart_after_content_change(chosen))
	content_setup.opened.connect(func(opened_edition: String, folder: String):
		var imported := ELProfile.new()
		if not imported.mount(opened_edition, folder):
			status.text = imported.error
			content_setup._status.text = imported.error
			return
		profiles[opened_edition] = imported
		close.call()
		if profile_select != null: profile_select.set_item_disabled(0 if opened_edition == "el1" else 1, false)
		_restart_after_content_change(opened_edition))

## After an import, a removal or a choice: a fresh start on the chosen edition,
## which is remembered for the next start.
func _restart_after_content_change(edition := "") -> void:
	if profiles.is_empty():
		_content_menu.call_deferred()
		return
	if not profiles.has(edition): edition = String(profiles.keys()[0])
	# The front end lists the mounted editions; build it again for the new set.
	if front_layer != null:
		front_layer.queue_free()
		front_layer = null
		front_menu = null
	if profile_select != null:
		for i in 2: profile_select.set_item_disabled(i, not profiles.has("el1" if i == 0 else "el2"))
	_start(edition)
	_remember_edition()
	if not _show_front_menu(): _open_setup()

## The game in use is the one the next start opens.
func _remember_edition() -> void:
	if not settings.save_file(): _notice("Could not save preferences.")

## Original front end (ELFrontMenu) over the remake's duel and campaign flows.
func _show_front_menu() -> bool:
	if campaign_view != null or profiles.is_empty(): return false
	var edition := profile.id if profile != null else launch_profile
	if not profiles.has(edition) or not ELFrontMenu.supports(profiles[edition]): return false
	if front_menu == null:
		front_layer = CanvasLayer.new()
		front_layer.layer = 5
		add_child(front_layer)
		front_menu = ELFrontMenu.new()
		front_menu.interface_music = true
		front_menu.music_owner_changed.connect(_pause_battle_audio)
		front_layer.add_child(front_menu)
		if not front_menu.build(profiles, edition):
			front_layer.queue_free()
			front_layer = null
			front_menu = null
			return false
		front_menu.duel_requested.connect(func():
			_hide_front_menu()
			_open_setup())
		front_menu.duel_match_requested.connect(_begin_duel_match)
		front_menu.combat_tutorial_requested.connect(_begin_combat_tutorial)
		front_menu.replay_requested.connect(_begin_replay)
		front_menu.duel_round_closed.connect(_duel_round_closed)
		front_menu.campaign_requested.connect(func(chosen: String, scenario: Dictionary, difficulty: int):
			_hide_front_menu()
			await _begin_campaign(chosen, scenario, difficulty)
			if campaign_view == null: _show_front_menu())
		front_menu.load_requested.connect(func():
			_hide_front_menu()
			_resume_campaign(true, "", front_menu.edition))
		front_menu.single_load_requested.connect(func():
			_hide_front_menu()
			_resume_campaign(false, ELSingleScenario.SAVE, front_menu.edition))
		front_menu.slot_load_requested.connect(func(row: Dictionary):
			_hide_front_menu()
			_load_slot(row))
		front_menu.settings = settings
		front_menu.settings_requested.connect(_open_settings)
		front_menu.settings_previewed.connect(_preview_volumes)
		front_menu.options_closed.connect(func(_applied: bool, _command: String): _apply_settings())
		front_menu.quit_requested.connect(func(): ELAudio.quiet_quit(get_tree()))
		front_menu.edition_requested.connect(func(chosen: String):
			demo = false
			_start(chosen)
			_remember_edition())
		front_menu.content_requested.connect(func(chosen: String): _open_content_setup(chosen))
	elif front_menu.edition != edition: front_menu.use_edition(edition)
	else: front_menu.show_screen("main")
	menu.hide()
	if setup_panel != null: setup_panel.hide()
	if campaign_setup != null: campaign_setup.hide()
	front_layer.show()
	front_menu.show()
	_refresh()
	return true

## The menu's interface music replaces the battle's music and ambience behind
## an opaque menu screen; the map's own pause rules apply during a campaign.
func _pause_battle_audio(paused: bool) -> void:
	if campaign_view != null or not is_instance_valid(battle_audio): return
	battle_audio.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	for player: Node in battle_audio.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D: player.stream_paused = paused

func _hide_front_menu() -> void:
	if front_menu == null: return
	front_menu.hide()
	front_layer.hide()

# --- Original Duel mode match ------------------------------------------------

## Opens the original Duel screen (the remake practice setup when the
## edition's front-end art is missing).
func _open_duel_screen(hot_seat := false) -> void:
	if _campaign_battle() != null:
		_notice("Finish or surrender the campaign battle first.")
		return
	if not _show_front_menu():
		_open_setup()
		return
	# After a hot-seat duel: the hot-seat Duel screen for player 1.
	if hot_seat: front_menu.duel_ui.start_hot_seat()
	else: front_menu.show_screen("duel")

func _begin_duel_match(started: ELDuelMatch) -> void:
	duel_match = started
	# The second game records every round of a Duel mode match.
	match_recording = ELDuelRecording.new() if started.edition == "el2" else null
	# The report opens only at a match's start, when the option is on.
	_drop_duel_report()
	if bool(settings.values.get("visual_log", false)): duel_report = ELDuelReport.new()
	demo = false
	mode_select.select(0)
	_hide_front_menu()
	_play_match_round()

## Every round is a fresh battle from the same presets; its first attacker
## is the round's own coin flip (ELDuelMatch.round_first_side).
func _play_match_round() -> void:
	var edition := duel_match.edition
	hot_side = -1
	hot_pending = false
	match_round_recorded = false
	match_clock = 0.0
	match_result_shown = false
	var previous := duel
	_match_starting = true
	var battle_seed := (duel_match.seed_value + duel_match.played * 0x39) & 0x7fffffff
	_start(edition, duel_match.round_options(profiles[edition]), null, battle_seed)
	_match_starting = false
	if match_recording != null and duel != null and duel != previous:
		match_recording.track(duel, battle_seed)
		if duel_match.played == 0: _label_recording()
	if duel_report != null and duel != null and duel != previous:
		if duel_match.played == 0: duel_report.open(profiles[edition], duel_match, duel, _match_names())
		duel_report.round_start(duel_match.played + 1, duel)
	_first_tutorial_battle()
	if duel == null or duel == previous:
		duel_match = null
		_open_duel_screen()

func _match_names() -> Array:
	if duel_match.hot_seat: return duel_match.names.duplicate()
	return [String(duel_match.presets[0].get("name", "")), String(duel_match.presets[1].get("name", ""))]

## Records a finished round once, then shows its result after a short pause.
func _watch_match_round(delta: float) -> void:
	if not match_round_recorded:
		match_round_recorded = true
		match_clock = 0.0
		match_result_shown = false
		duel_match.record(duel.winner)
		if match_recording != null: match_recording.finish_round(duel)
		if duel_report != null:
			duel_report.round_end(duel.winner)
			if duel_match.finished(): _finish_duel_report()
		_refresh()
		return
	# The second game shows the round result after every round.
	if (duel_match.rounds < 2 and duel_match.edition != "el2") or front_menu == null or front_menu.is_visible_in_tree(): return
	match_clock += delta
	# The result follows the end of the battle (the winner's clip), and
	# never sooner than the remake's short pause.
	if match_clock >= ROUND_RESULT_DELAY and ending_over() and not match_result_shown:
		match_result_shown = true
		_show_round_result()

func _show_round_result() -> void:
	if duel_match == null or not match_round_recorded: return
	if front_menu == null and not _show_front_menu(): return
	var last := 0 if duel.winner < 0 else (1 if duel.winner == 0 else -1)
	if duel_match.edition == "el2":
		front_menu.replay_ui.recording = match_recording
		front_menu.duel_ui.show_round(duel_match, _match_names(), last, duel_match.finished())
	elif duel_match.finished(): front_menu.duel_ui.show_result(duel_match, _match_names())
	else: front_menu.duel_ui.show_round(duel_match, _match_names(), last)
	_show_front_menu_layer()

## Continue after a finished round (end button / Space): the result panel for
## a multi-round match, the Duel screen after a single-round duel.
func _continue_match() -> void:
	if duel_match == null: return
	if duel_match.rounds < 2 and duel_match.edition != "el2":
		var hot := duel_match.hot_seat
		duel_match = null
		_open_duel_screen(hot)
	else: _show_round_result()

func _duel_round_closed(proceed: bool) -> void:
	if duel_match == null: return
	if proceed and not duel_match.finished():
		_hide_front_menu()
		_play_match_round()
		return
	# Second game: OK on the end-of-duel panel, then the match summary.
	if proceed and duel_match.edition == "el2" and front_menu.screen == "duel_round" and duel_match.rounds >= 2:
		front_menu.duel_ui.show_result(duel_match, _match_names())
		return
	if not proceed and not duel_match.finished():
		# Ending early still shows the summary of the rounds played.
		duel_match.rounds = maxi(duel_match.played, 1)
		_finish_duel_report()
		if duel_match.rounds >= 2:
			front_menu.duel_ui.show_result(duel_match, _match_names())
			return
	var hot := duel_match.hot_seat
	duel_match = null
	_open_duel_screen(hot)

func _finish_duel_report() -> void:
	if duel_report != null and duel_match != null: duel_report.finish(duel_match)
	duel_report = null

func _drop_duel_report() -> void:
	if duel_report != null: duel_report.close()
	duel_report = null

## Surrender concedes only the current round.
func _surrender_round() -> void:
	menu.hide()
	if duel_match == null or duel == null or duel.phase == ELDuel.Phase.FINISHED:
		_notice("There is no Duel mode round in progress.")
		return
	# Hot seat: the player holding the screen concedes.
	var side := (hot_side if hot_side >= 0 else duel.active_side()) if _hot_seat() else 0
	if match_recording != null: match_recording.note_surrender(duel, side)
	duel.heroes[side].health = 0
	duel._check_winner()
	_refresh()

# --- Second-game combat tutorial ------------------------------------------------

## Tutorial screen -> Combat: the recorded battle in tutorial mode.
## The computer side replays its commands; only the awaited command is
## accepted from the player; each command's note is the panel text.
func _begin_combat_tutorial() -> void:
	if not profiles.has("el2"): return
	if _campaign_battle() != null:
		_notice("Finish or surrender the campaign battle first.")
		return
	var tutorial := ELCombatTutorial.new()
	var battle := ELDuel.new()
	if not tutorial.load_from(profiles.el2) or not tutorial.begin(battle):
		_notice(tutorial.error)
		return
	_hide_front_menu()
	demo = false
	mode_select.select(0)
	_start("el2", {}, battle)
	if duel != battle: return
	combat_tutorial = tutorial
	tutorial.note_changed.connect(func(): call_deferred("_tutorial_note"))
	tutorial.diverged.connect(func(message: String):
		_log(message)
		_notice(message))
	if tutorial_panel == null:
		tutorial_panel = ELCombatTutorialPanel.new()
		ui.add_child(tutorial_panel)
		tutorial_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tutorial_panel.build(profiles.el2)
		tutorial_panel.close_requested.connect(_ask_quit_combat_tutorial)
		tutorial_quit = ConfirmationDialog.new()
		tutorial_quit.exclusive = true
		ui.add_child(tutorial_quit)
		tutorial_quit.confirmed.connect(_leave_combat_tutorial)
	tutorial_panel.show()
	_tutorial_note()

## The awaited command's note; "#d" also selects that spell.
func _tutorial_note() -> void:
	if combat_tutorial == null or tutorial_panel == null: return
	tutorial_panel.set_text(combat_tutorial.note_text())
	var index := combat_tutorial.preselected_index()
	if index >= 0 and not combat_tutorial.opponent_due() and duel.active_side() == 0:
		var card: String = duel.heroes[0].hand[index]
		if duel.target_kind(card) != "none" and not duel.variable_power(card): selection = index
	if duel.phase == ELDuel.Phase.FINISHED: _tutorial_result()
	_refresh()

## The original's round-result text for the local hero (T_RR_DUEL_*).
func _tutorial_result() -> void:
	var key := "T_RR_DUEL_WIN" if duel.winner == 0 else ("T_RR_DUEL_DRAW" if duel.winner < 0 else "T_RR_DUEL_LOSE")
	_notice(profiles.el2.text(key).strip_edges())

## Close button: T_COMBAT_TUTORIAL_QUIT confirmation.
func _ask_quit_combat_tutorial() -> void:
	if combat_tutorial == null: return
	tutorial_quit.dialog_text = profiles.el2.text(ELCombatTutorial.QUIT_TEXT)
	tutorial_quit.popup_centered()

## Leaving or finishing returns to the Tutorial screen.
func _leave_combat_tutorial() -> void:
	_close_combat_tutorial()
	if front_menu != null: front_menu.set_return_screen("tutorial")
	if not _show_front_menu(): _open_setup()

func _close_combat_tutorial() -> void:
	if combat_tutorial != null and duel == combat_tutorial.duel: duel.gate = null
	combat_tutorial = null
	if tutorial_panel != null: tutorial_panel.hide()
	if tutorial_quit != null: tutorial_quit.hide()

## Names and portraits the replay list shows: my hero, the enemy hero.
func _label_recording() -> void:
	var names := _match_names()
	for side in 2:
		var template := String(duel.heroes[side].template)
		match_recording.labels[side] = names[side] if not String(names[side]).is_empty() else template
		match_recording.labels[side + 2] = template
		match_recording.faces[side] = int(profile.table("HeroTemplates").get(template, {}).get("Face", -1))

# --- Second-game duel replays ---------------------------------------------------

## Duel -> Replay -> Load: the recorded battle plays back with the original
## replay player panel; nothing else acts on it.
func _begin_replay(path: String) -> void:
	if not profiles.has("el2"): return
	if _campaign_battle() != null:
		_notice("Finish or surrender the campaign battle first.")
		return
	var player := ELDuelReplayPlayer.new()
	var battle := ELDuel.new()
	if not player.load_file(profiles.el2, path) or not player.begin(battle):
		if front_menu != null and front_menu.is_visible_in_tree(): front_menu.duel_ui.show_message(player.error, Callable(), false, 300.0)
		else: _notice(player.error)
		return
	_hide_front_menu()
	demo = false
	mode_select.select(0)
	_start("el2", {}, battle)
	if duel != battle: return
	replay_player = player
	player.changed.connect(_replay_changed)
	player.diverged.connect(func(message: String):
		_log(message)
		_notice(message))
	if replay_panel == null:
		replay_panel = ELCombatTutorialPanel.new()
		replay_panel.name = "ReplayPanel"
		ui.add_child(replay_panel)
		replay_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		replay_panel.build(profiles.el2, true)
		replay_panel.close_requested.connect(_ask_quit_replay)
		replay_panel.play_toggled.connect(func(on: bool):
			if replay_player != null: replay_player.set_playing(on))
		replay_panel.rewind_requested.connect(_rewind_replay)
		replay_panel.inventory_requested.connect(_open_replay_inventory.bind(0))
		replay_panel.comment_edited.connect(func(text: String):
			if replay_player != null and replay_player.set_comment(text): replay_panel.text_box.text = text)
		replay_panel.save_requested.connect(_save_replay_copy)
		replay_panel.comment_pause_toggled.connect(func(on: bool):
			if replay_player != null: replay_player.pause_at_comment = on)
		replay_panel.step_requested.connect(func(mode: int):
			if replay_player != null: replay_player.play_step(mode))
		replay_quit = ConfirmationDialog.new()
		replay_quit.exclusive = true
		ui.add_child(replay_quit)
		replay_quit.confirmed.connect(_leave_replay)
	player.pause_at_comment = bool(replay_panel.checked.get("TP_TextPause", false))
	replay_panel.editor = false
	replay_panel.set_text("")
	replay_panel.show()
	_replay_changed()

## Rewind (TP_Back): the same battle from its start, paused.
func _rewind_replay() -> void:
	if replay_player == null: return
	var battle := ELDuel.new()
	if not replay_player.begin(battle):
		_notice(replay_player.error)
		return
	_start("el2", {}, battle)
	_replay_changed()

func _replay_changed() -> void:
	if replay_player == null or replay_panel == null: return
	replay_panel.set_at_start(replay_player.index == 0 and replay_player.duel == duel)
	# The comment of the next command (recorded or written in the editor).
	replay_panel.set_text(replay_player.comment())
	replay_panel.set_editable(replay_player.error.is_empty() and not replay_player.done())
	replay_panel.set_checked("TP_Play", replay_player.playing)
	for mode in 3: replay_panel.set_checked("TP_Pause%dE" % (mode + 1), replay_player.playing and replay_player.step_mode == mode + 1)
	if replay_player.duel == duel and duel.phase == ELDuel.Phase.FINISHED:
		var key := "T_RR_DUEL_WIN" if duel.winner == 0 else ("T_RR_DUEL_DRAW" if duel.winner < 0 else "T_RR_DUEL_LOSE")
		_notice(profiles.el2.text(key).strip_edges())
	_refresh()

## Close (TP_Close / TP_CloseE): T_REPLAY_QUIT, then the Duel menu.
func _ask_quit_replay() -> void:
	if replay_player == null: return
	replay_player.set_playing(false)
	replay_quit.dialog_text = profiles.el2.text("T_REPLAY_QUIT").strip_edges()
	replay_quit.popup_centered()

func _leave_replay() -> void:
	_close_replay()
	if _show_front_menu(): front_menu.show_screen("duel_menu")
	else: _open_setup()

## Inventory (TP_Inventory): the first hero's round-end screen,
## read-only; its Close shows the second hero, whose Close returns to the
## replay. Playback stays paused meanwhile.
func _open_replay_inventory(side: int) -> void:
	_close_replay_inventory()
	if replay_player == null or duel != replay_player.duel or side > 1: return
	replay_player.set_playing(false)
	var labels: Array = replay_player.data.get("labels", [])
	var players: Array = replay_player.data.get("options", {}).get("players", [])
	var title := str(labels[side]) if side < labels.size() and not str(labels[side]).is_empty() else str(duel.heroes[side].template)
	var reserve: Dictionary = players[side].get("reserve", {}) if side < players.size() and players[side] is Dictionary else {}
	var screen := ELRoundEndDuelView.new()
	if not screen.build(profiles.el2, duel.heroes[side], reserve, title):
		screen.free()
		_notice("The original round-end screen art is unavailable.")
		return
	ui.add_child(screen)
	replay_inventory = screen
	replay_inventory_side = side
	screen.closed.connect(func():
		if side == 0: _open_replay_inventory(1)
		else: _close_replay_inventory())

## Save changes (TP_SaveE): the replay save screen over the battle, saving
## the replay with its edited comments under a chosen name.
func _save_replay_copy() -> void:
	if replay_player == null: return
	replay_player.set_playing(false)
	var host := _battle_host()
	if host == null: return
	options_layer.show()
	host.show()
	host.replay_ui.recording = replay_player.to_recording()
	host.open_hosted("replay_save", true)

func _close_replay_inventory() -> void:
	if replay_inventory != null: replay_inventory.queue_free()
	replay_inventory = null
	replay_inventory_side = -1

func _close_replay() -> void:
	_close_replay_inventory()
	if replay_player != null: replay_player.release()
	replay_player = null
	if replay_panel != null: replay_panel.hide()
	if replay_quit != null: replay_quit.hide()

# --- Second-game Esc menu --------------------------------------------------------

## Esc opens the original game menu once nothing is being chosen (a half-made
## choice is cancelled first). The first game's battle screen has no menu of its
## own: the original reaches Options only from the map panel's wrench (AdvPanel
## command 0x7c), so its battles open Options on the combat page, which holds
## Surrender, Save, Load and the exits.
func _wants_esc_menu() -> bool:
	if profile == null or profile.id not in ["el1", "el2"] or demo or _overlay_open(): return false
	return selection < 0 and exchange_target < 0 and selected_creature < 0 and ability_selection.is_empty()

func _open_game_menu() -> void:
	if profile == null: return
	if profile.id == "el1": _open_battle_options()
	elif esc_menu != null and esc_menu.visible: _close_esc_menu()
	else: _open_esc_menu()

func _open_esc_menu() -> void:
	if esc_menu == null or esc_menu.profile != profile:
		if esc_menu != null: esc_menu.queue_free()
		esc_menu = ELCombatEscMenu.new()
		if not esc_menu.build(profile):
			esc_menu.free()
			esc_menu = null
			_notice("The original Esc menu art is unavailable.")
			return
		ui.add_child(esc_menu)
		esc_menu.closed.connect(_close_esc_menu)
		esc_menu.surrender_requested.connect(func(): _ask_battle("T_MB_SURRENDER", _esc_surrender))
		esc_menu.load_requested.connect(_esc_load)
		esc_menu.encyclopaedia_requested.connect(func():
			var host := _battle_host()
			if host == null: return
			host.open_hosted("encyclopaedia", true)
			options_layer.show()
			host.show())
		esc_menu.options_requested.connect(_open_battle_options)
		esc_menu.exit_requested.connect(func(): _ask_battle("T_MB_QUIT_TO_MM", _esc_exit_to_menu))
		esc_menu.quit_requested.connect(func(): _ask_battle("T_MB_QUIT_TO_WIN", func(): ELAudio.quiet_quit(get_tree())))
		esc_menu.remake_menu_requested.connect(func():
			_close_esc_menu()
			menu.show())
	menu.hide()
	# Surrender is disabled while a replay plays.
	esc_menu.open(replay_player == null)
	_refresh()

func _close_esc_menu() -> void:
	if esc_menu != null: esc_menu.hide()
	_refresh()

## The original question box over the battle; OK runs `on_ok`.
func _ask_battle(key: String, on_ok: Callable) -> void:
	var host := _battle_host()
	if host == null: return
	host.ask_hosted(profile.text(key).strip_edges(), on_ok)
	options_layer.show()
	host.show()

func _esc_surrender() -> void:
	_close_esc_menu()
	if _campaign_battle() != null or duel_match != null: _surrender_battle()
	elif duel != null and duel.phase != ELDuel.Phase.FINISHED and replay_player == null and combat_tutorial == null:
		# A practice battle: the player's side concedes.
		duel.heroes[0].health = 0
		duel._check_winner()
		_refresh()

## Load: the save list of the running kind of game (campaign or single mission).
func _esc_load() -> void:
	var host := _battle_host()
	if host == null: return
	var kind := ELSaveSlots.kind_of(campaign_view.state) if campaign_view != null else ELSaveSlots.KIND_SINGLE
	host.open_hosted("load_game", true, kind)
	options_layer.show()
	host.show()

func _esc_exit_to_menu() -> void:
	_close_esc_menu()
	if campaign_view != null:
		_leave_campaign()
		return
	_close_combat_tutorial()
	_close_replay()
	duel_match = null
	# Which original quit paths write the result block is unconfirmed: the report stops.
	_drop_duel_report()
	_set_auto(false)
	_show_front_menu()
