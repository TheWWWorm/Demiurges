class_name ELAutochessScreen
extends Control
## The Etherlords II autochess mode: nine heroes, a shared creature pool,
## real-time battles on Etherlords battlefields. The layout follows the
## Cursed Lands autochess: live recruits along the top with the refresh and
## level buttons, ether, health and Start battle beside them, the round panel
## and standings on the right, damage, alliances and artifacts on the left,
## reserves along the bottom and the watched hero's bust in the corner. The
## board stays open: most of the interface is outlined text over the scene.

signal left
## The remake's settings asked for from the menu.
signal remake_settings_requested

const H := preload("res://src/autochess/hud.gd")
const DESIGN := Vector2(1440, 900)
const SPEEDS := [1.0, 2.0]
const PULSE_SECONDS := 1.6
const STANDINGS_WIDTH := 200.0
## Seconds from a board's end until the survivors' bolts have struck its hero.
const BOLTS_LAND := 1.6

var profile: ELProfile
var settings: Dictionary = {}
var game: ELAutochessMatch
var me := 0
var watched := 0
var online: ELAutochessOnline
var stage: Node3D
var board: ELAutochessBoardView
var camera: Camera3D
var overlay: Control
var hud: Control
var portraits: ELAutochessPortraits
var ui_scale := 1.0
var _shown_board := -1
var _shown_team := 0
## Home view: from behind the watched hero's half, looking across the
## field toward the other half and the horizon.
const HOME_YAW := -PI * 0.5
const HOME_PITCH := 0.62
const HOME_DISTANCE := 25.0
const HOME_TARGET := Vector3(-6.0, 0, 0)
var _camera_yaw := HOME_YAW
var _camera_pitch := HOME_PITCH
var _camera_distance := HOME_DISTANCE
var _camera_target := HOME_TARGET
var _orbiting := false
var _orbit_from := Vector2.ZERO
var _orbit_moved := false
var _drag_from := Vector2.INF

# Interface
var _shop_panel: HBoxContainer
var _offers: Array = []
var _recruited: Array[Label] = []
var _refresh_button: H.RoundButton
var _level_button: H.RoundButton
var _actions: VBoxContainer
var _ether: Label
var _income: Label
var _health: Label
var _start: Button
var _speed: Button
var _round_panel: H.Frame
var _round_title: Label
var _phase: Label
var _clock: Label
var _encounter: Label
var _menu_button: Button
var _shop_toggle: Button
var _standings: VBoxContainer
var _sidebar: VBoxContainer
var _damage_heading: Label
var _damage_list: VBoxContainer
var _badges := {}
var _items_heading: Label
## The right column: the player list with the artifacts and spells under it.
var _right_column: VBoxContainer
var _items: HFlowContainer
var _bench: HBoxContainer
var _army_label: Label
var _reserve_label: Label
var _reserves: Array = []
var _sell_target: Button
var _hover_key := ""
var _hover_wait := 0.0
var path_tracing: ELPathTracing
var _traced_arena: Object
var _rail: H.Frame
var _rail_box: VBoxContainer
var _notice: H.Notice
var _message: Label
var _banner: VBoxContainer
var _banner_title: Label
var _banner_detail: Label
var _banner_left := 0.0
var _modal: Control
var _modal_panel: H.Frame
var _modal_box: VBoxContainer
var _overview: Control

var _selected := {}
## The original cursor this screen asks for: the open hand over a creature
## that can be moved, the closed one while carrying it.
var cursor_name := "default"
## The loading screen's remaining tasks and its parts.
signal loaded
var loaded_all := false
var _load_tasks: Array = []
var _load_total := 0
var _load_wait := 0
var _settle_frames := 0
var _load_kind := ""
var _clip_jobs: Array = []
var _clip_task := -1
var _loading: ColorRect
var _loading_text: Label
var _loading_bar: ProgressBar
var _framing: Array = []
var _warm_holder: Node3D
var _message_left := 0.0
var _last_stage := ""
const SummonTable := preload("res://src/duel/combat_sound_table.gd")
var _known_level := -1
## Creatures that stepped onto the board and wait for their summon entrance.
var _arriving: Dictionary = {}
var _last_round := -1
var _pulses := {}
var _stats_cache := {}
var _reward_shown := ""
var _shop_open := true
var _signatures := {}

func _t(text: String) -> String:
	return ELAutochessText.t(profile, text)

## The Options volumes now: music, ambience and effects of the battlefield
## and the interface sounds (later battlefields are built with them too).
func apply_volumes(values: Dictionary) -> void:
	settings = values
	if board == null: return
	board.settings = values
	if is_instance_valid(board.audio): board.audio.apply_volumes(values)

func build(data: ELProfile, values: Dictionary) -> void:
	profile = data
	settings = values
	H.sound_profile = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var look := Theme.new()
	look.default_font_size = 16
	look.set_color("font_color", "Label", H.PAPER)
	look.set_color("font_color", "Button", H.PAPER)
	theme = look
	stage = Node3D.new()
	add_child(stage)
	board = ELAutochessBoardView.new()
	stage.add_child(board)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = 400.0
	stage.add_child(camera)
	board.build(profile, "Green.001", settings)
	board.set_listener(camera)
	portraits = ELAutochessPortraits.new()
	portraits.profile = profile
	add_child(portraits)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_build_shade()
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	_build_shop()
	_build_round_panel()
	_build_standings()
	_build_sidebar()
	_build_bench()
	_build_rail()
	_build_banner()
	_build_modal()
	_build_overview()
	resized.connect(_layout)
	_layout()
	_update_camera()

# --- Construction -------------------------------------------------------------

## Darkened top and bottom edges under the HUD, as in the Cursed Lands
## autochess, so the shop row and the reserves read over any battlefield.
func _build_shade() -> void:
	for top: bool in [true, false]:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.62 if top else 0.7))
		gradient.set_color(1, Color(0, 0, 0, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 4
		texture.height = 64
		texture.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
		texture.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
		var shade := TextureRect.new()
		shade.texture = texture
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top: shade.offset_bottom = 0
		else: shade.offset_top = 0
		shade.set_meta("top", top)
		shade.name = "ShadeTop" if top else "ShadeBottom"

func _build_shop() -> void:
	_shop_panel = HBoxContainer.new()
	_shop_panel.position = Vector2(24, 12)
	_shop_panel.add_theme_constant_override("separation", 12)
	hud.add_child(_shop_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(row)
	for index in ELAutochessRules.SHOP_SLOTS:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(148, 156)
		row.add_child(holder)
		var offer := H.Offer.new()
		holder.add_child(offer)
		offer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		offer.pressed.connect(_buy.bind(index))
		offer.lock_toggled.connect(func(): _act("lock", [index]))
		offer.gui_input.connect(_offer_input.bind(index))
		_offers.append(offer)
		var bought := H.label(holder, "", 13, H.MUTED)
		bought.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bought.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_recruited.append(bought)
	var tools := VBoxContainer.new()
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_theme_constant_override("separation", 4)
	_shop_panel.add_child(tools)
	_refresh_button = H.RoundButton.new()
	_refresh_button.kind = "refresh"
	_refresh_button.pressed.connect(func(): _act("refresh", []))
	tools.add_child(_refresh_button)
	_level_button = H.RoundButton.new()
	_level_button.kind = "level"
	_level_button.pressed.connect(func(): _act("train", []))
	tools.add_child(_level_button)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	hud.add_child(_actions)
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.add_theme_constant_override("separation", 10)
	_actions.add_child(purse)
	H.label(purse, "◈", 22, H.ETHER)
	var treasury := VBoxContainer.new()
	treasury.add_theme_constant_override("separation", 0)
	purse.add_child(treasury)
	_ether = H.label(treasury, "", 19, H.GOLD)
	_income = H.label(treasury, "", 12, H.MUTED)
	_income.mouse_filter = Control.MOUSE_FILTER_PASS
	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	purse.add_child(gap)
	H.label(purse, "♥", 20, H.PAPER)
	_health = H.label(purse, "", 17, H.PAPER)
	_start = H.button(_actions, "", _start_pressed, true)
	_start.custom_minimum_size = Vector2(196, 44)
	_start.add_theme_font_size_override("font_size", 21)
	_start.add_theme_font_override("font", H.serif())
	_speed = H.button(_actions, "", _toggle_speed)
	_speed.custom_minimum_size = Vector2(66, 40)
	_speed.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _build_round_panel() -> void:
	_round_panel = H.Frame.new()
	_round_panel.surface = Color(0.055, 0.055, 0.04, 0.85)
	hud.add_child(_round_panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 3)
	lines.custom_minimum_size.x = 160
	_round_panel.add_child(lines)
	_round_title = H.label(lines, "", 20, H.PAPER, true)
	_phase = H.label(lines, "", 14, H.MUTED)
	_clock = H.label(lines, "", 16, H.GOLD)
	_encounter = H.wrap(lines, "", 14, H.GOLD)
	_encounter.custom_minimum_size.x = 150
	_menu_button = H.button(hud, _t("Menu"), _toggle_menu)
	_menu_button.add_theme_font_override("font", H.serif())
	_menu_button.add_theme_font_size_override("font_size", 20)
	_shop_toggle = H.button(hud, _t("Shop"), func():
		_shop_open = not _shop_open
		_refresh())

func _build_standings() -> void:
	_right_column = VBoxContainer.new()
	_right_column.add_theme_constant_override("separation", 12)
	_right_column.custom_minimum_size.x = STANDINGS_WIDTH
	_right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_right_column)
	_standings = VBoxContainer.new()
	_standings.add_theme_constant_override("separation", 2)
	_standings.custom_minimum_size.x = STANDINGS_WIDTH
	_right_column.add_child(_standings)

func _build_sidebar() -> void:
	_sidebar = VBoxContainer.new()
	_sidebar.position = Vector2(28, 182)
	_sidebar.custom_minimum_size.x = 250
	_sidebar.add_theme_constant_override("separation", 10)
	hud.add_child(_sidebar)
	_damage_heading = H.label(_sidebar, _t("Damage"), 21, H.GOLD, true)
	_damage_list = VBoxContainer.new()
	_damage_list.add_theme_constant_override("separation", 5)
	_sidebar.add_child(_damage_list)
	H.label(_sidebar, _t("Alliances"), 21, H.GOLD, true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_sidebar.add_child(grid)
	for key: String in ELAutochessAlliances.ORDER:
		var badge := H.Badge.new()
		badge.key = key
		badge.picture = ELAutochessAlliances.icon(profile, key)
		grid.add_child(badge)
		_badges[key] = badge
	# Artifacts and spells sit under the player list, where the right side
	# has room; under the alliances they ran into the army count.
	_items_heading = H.label(_right_column, _t("Artifacts and spells"), 21, H.GOLD, true)
	# Long translations wrap instead of widening the column past the edge.
	_items_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_items_heading.custom_minimum_size.x = STANDINGS_WIDTH
	_items = HFlowContainer.new()
	_items.add_theme_constant_override("h_separation", 6)
	_items.add_theme_constant_override("v_separation", 6)
	_items.custom_minimum_size.x = STANDINGS_WIDTH
	_right_column.add_child(_items)

## Each alliance is pictured by the card of one of its lines' strongest
## form, a different line for every alliance.
func _signature(key: String) -> String:
	if _signatures.is_empty():
		var taken := {}
		for alliance: String in ELAutochessAlliances.ORDER:
			var best := -1
			for line in ELAutochessRules.FAMILIES.size():
				if taken.has(line) or not alliance in ELAutochessAlliances.traits(profile, line): continue
				# Prefer lines that belong to this alliance alone.
				if best < 0 or ELAutochessAlliances.traits(profile, line).size() < ELAutochessAlliances.traits(profile, best).size(): best = line
			if best >= 0:
				taken[best] = true
				_signatures[alliance] = ELAutochessRules.form(best, 2)
	return String(_signatures.get(key, ""))

func _build_bench() -> void:
	_bench = HBoxContainer.new()
	_bench.add_theme_constant_override("separation", 14)
	hud.add_child(_bench)
	var status := VBoxContainer.new()
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.custom_minimum_size.x = 96
	_bench.add_child(status)
	_army_label = H.label(status, "", 16, H.PAPER)
	_army_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reserve_label = H.label(status, "", 13, H.PAPER)
	_reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for slot in ELAutochessRules.BENCH_LIMIT:
		var reserve := H.Reserve.new()
		reserve.pressed.connect(_reserve_pressed.bind(slot))
		reserve.gui_input.connect(_reserve_input.bind(slot))
		_bench.add_child(reserve)
		_reserves.append(reserve)
	_message = H.label(hud, "", 14, H.PAPER)
	# As in the Cursed Lands autochess: selecting a creature reveals the sell
	# area above the reserves' right end.
	_sell_target = H.button(hud, "", _sell_selected, true)
	_sell_target.add_theme_font_size_override("font_size", 17)
	_sell_target.hide()

func _build_rail() -> void:
	_rail = H.Frame.new()
	_rail.accented = true
	hud.add_child(_rail)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_rail.add_child(scroll)
	_rail_box = VBoxContainer.new()
	_rail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_box.add_theme_constant_override("separation", 5)
	scroll.add_child(_rail_box)
	_rail.hide()
	_notice = H.Notice.new()
	_notice.profile = profile
	hud.add_child(_notice)

func _build_banner() -> void:
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", 2)
	hud.add_child(_banner)
	_banner_title = H.label(_banner, "", 36, Color("ffe3a1"), true)
	_banner_title.add_theme_constant_override("outline_size", 9)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_detail = H.label(_banner, "", 15, H.PAPER)
	_banner_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.hide()

func _build_modal() -> void:
	_modal = Control.new()
	hud.add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.03, 0.025, 0.65)
	_modal.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _modal.has_meta("locked"): _close_modal())
	_modal_panel = H.Frame.new()
	_modal_panel.surface.a = 1.0
	_modal.add_child(_modal_panel)
	_modal_box = VBoxContainer.new()
	_modal_box.add_theme_constant_override("separation", 12)
	_modal_panel.add_child(_modal_box)
	_modal.hide()

func _build_overview() -> void:
	_overview = Control.new()
	_overview.visible = false
	_overview.draw.connect(_draw_overview)
	_overview.gui_input.connect(_overview_input)
	hud.add_child(_overview)
	var bar := HBoxContainer.new()
	bar.position = Vector2(24, 16)
	bar.add_theme_constant_override("separation", 16)
	_overview.add_child(bar)
	H.button(bar, _t("Your board"), func(): _watch(me))
	var hint := H.label(bar, _t("Click a board to watch it."), 16, H.PAPER)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# --- Layout ---------------------------------------------------------------------

## One logical 1440×900 canvas; type, figures and spacing scale together.
func _layout() -> void:
	if hud == null: return
	ui_scale = maxf(0.75, minf(size.x / DESIGN.x, size.y / DESIGN.y))
	hud.scale = Vector2.ONE * ui_scale
	hud.size = size / ui_scale
	var w := hud.size.x
	var h := hud.size.y
	($ShadeTop as Control).offset_bottom = 230 * ui_scale
	($ShadeBottom as Control).offset_top = -260 * ui_scale
	_menu_button.position = Vector2(w - 104, 16)
	_menu_button.size = Vector2(88, 44)
	_shop_toggle.position = Vector2(w - 104, 68)
	_shop_toggle.size = Vector2(88, 40)
	var round_size := _round_panel.get_combined_minimum_size()
	_round_panel.size = Vector2(maxf(184, round_size.x), round_size.y)
	_round_panel.position = Vector2(w - 116 - _round_panel.size.x, 16)
	var actions_size := _actions.get_combined_minimum_size()
	_actions.size = Vector2(maxf(196, actions_size.x), actions_size.y)
	_actions.position = Vector2(_round_panel.position.x - _actions.size.x - 16, 18)
	_right_column.position = Vector2(w - 16 - STANDINGS_WIDTH, _round_panel.position.y + _round_panel.size.y + 12)
	_sell_target.size = Vector2(200, 44)
	_sell_target.position = Vector2(w - 16 - 200, h - 44 - 120 - 56)
	_bench.position = Vector2(24, h - 44 - 120)
	_message.position = Vector2(24, h - 28)
	_banner.size = Vector2(560, 0)
	_banner.position = Vector2((w - 560) * 0.5, 300)
	_overview.position = Vector2.ZERO
	_overview.size = hud.size
	_modal.position = Vector2.ZERO
	_modal.size = hud.size
	var modal_size := _modal_panel.get_combined_minimum_size()
	_modal_panel.size = modal_size
	_modal_panel.position = (hud.size - modal_size) * 0.5
	_layout_rail()
	_notice.size = Vector2(300, 0)
	_notice.position = Vector2(_sidebar.position.x + _sidebar.size.x + 12, _sidebar.position.y)

func _layout_rail() -> void:
	# The sell area stays above the inspector (and under the dialogs).
	hud.move_child(_sell_target, _rail.get_index() + 1)
	var top := _round_panel.position.y + _round_panel.size.y + 12
	var bottom := (_sell_target.position.y - 8) if _sell_target.visible else (_bench.position.y - 8)
	var content := maxf(80.0, _rail_box.get_combined_minimum_size().y + 24)
	# The whole card always shows: a card taller than the room is drawn
	# smaller instead of scrolling.
	var room := maxf(120.0, bottom - top)
	var fit := minf(1.0, room / content)
	# The scroll's minimum first, so the frame can also shrink.
	(_rail.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(296, content - 20)
	_rail.scale = Vector2(fit, fit)
	_rail.position = Vector2(hud.size.x - 16 - 320 * fit, top)
	_rail.size = Vector2(320, content)

# --- Match ----------------------------------------------------------------------

## Starts showing `value` from `seat` (0 alone or as host, a guest's seat online).
func show_match(value: ELAutochessMatch, seat := 0, link: ELAutochessOnline = null) -> void:
	game = value
	me = seat
	watched = seat
	online = link
	_selected.clear()
	_shown_board = -1
	_last_stage = ""
	_last_round = -1
	_reward_shown = ""
	_pulses.clear()
	_known_level = company().capacity()
	if not game.changed.is_connected(_queue_refresh): game.changed.connect(_queue_refresh)
	if not game.fight_started.is_connected(_on_fight): game.fight_started.connect(_on_fight)
	if not game.board_finished.is_connected(_on_board_finished): game.board_finished.connect(_on_board_finished)
	if not game.player_eliminated.is_connected(_on_eliminated): game.player_eliminated.connect(_on_eliminated)
	if online != null:
		online.message.connect(func(text: String): _say(text, 4.0))
		online.closed.connect(func(reason: String):
			_say(_t(reason), 6.0)
			_show_end(_t("The connection was lost.")))
	_close_modal()
	_overview.hide()
	hud.show()
	stage.show()
	board.set_muted(false)
	camera.current = true
	_home_camera()
	_refresh()

## The landing: only the chosen hero's battlefield, slowly circling, with
## no match and no interface.
func show_backdrop(character: String) -> void:
	game = null
	online = null
	hud.hide()
	stage.show()
	board.set_muted(false)
	board.clear_units()
	board.set_arena(ELAutochessCharacters.arena(profile, character))
	camera.current = true
	_home_camera()
	board.set_fire(true)
	board.set_hero(0, character)
	board.set_hero(1, "")

## Leaves the mode until it is opened again: the battlefield hidden and
## silent, everything loaded kept.
func suspend() -> void:
	game = null
	online = null
	hud.hide()
	board.clear_units()
	board.set_muted(true)
	stage.hide()
	_traced_arena = null

func company() -> ELAutochessCompany:
	return game.companies[me]

func viewed() -> ELAutochessCompany:
	return game.companies[watched]

func _act(op: String, args: Array) -> void:
	if game == null: return
	if online != null and not online.is_host:
		online.send_command(op, args)
		_sound(op, "")
		return
	_known_level = company().capacity()
	var fielded := company().army.filter(func(entry: Dictionary) -> bool: return entry.deployed).map(func(entry: Dictionary) -> int: return int(entry.uid))
	var error := ELAutochessCommands.apply(game, me, op, args)
	if error.is_empty():
		# A creature is summoned as in the original (its entrance clip, its
		# colour's summon effect and Summon sound) whenever it steps onto the
		# board, bought or brought from the reserve. The reserve just shows it.
		for entry: Dictionary in company().army:
			var uid := int(entry.uid)
			if entry.deployed and not fielded.has(uid): _arriving[uid] = true
		board.arriving = _arriving
		if op == "buy":
			for uid: int in company().last_evolutions: _arriving[uid] = true
	if not error.is_empty(): _say(_t(error))
	_sound(op, error)
	if op == "buy" and error.is_empty():
		for uid: int in company().last_evolutions:
			var entry := company().unit(uid)
			if entry.is_empty() or int(entry.rank) < 1: continue
			_notice.present({"family": int(entry.family), "rank": int(entry.rank), "uid": uid})
			_pulses[uid] = PULSE_SECONDS
			board.hero_react(0, "usummon")
	_refresh()

## Moving creatures plays nothing (the original's put-on clicks grate when
## repeated).
const SOUNDS := {
	"buy": "Buttons/Buy.wav", "sell": "Buttons/Sell.wav", "refresh": "Buttons/CardTurn.wav",
	"train": "Buttons/SkillBut.wav", "lock": "Buttons/CheckBox.wav", "choose_item": "Buttons/Accept.wav",
	"undo": "Buttons/Cancel.wav",
}
const EVOLUTION_SOUND := "Magic/Specialization.wav"
const LEVEL_SOUND := "Magic/Gift.wav"

## The original interface sound of an action (or the error sound).
func _sound(op: String, error: String) -> void:
	if not error.is_empty():
		H.play_sound(ELUiSounds.ERROR)
		return
	if op == "buy" and not company().last_evolutions.is_empty():
		H.play_sound(EVOLUTION_SOUND)
		return
	if op == "train" and company().capacity() != _known_level:
		_known_level = company().capacity()
		H.play_sound(LEVEL_SOUND)
		return
	H.play_sound(String(SOUNDS.get(op, "")))

func _say(text: String, seconds := 3.0) -> void:
	_message.text = text
	_message_left = seconds

func _banner_text(title: String, detail := "", seconds := 2.0, color := Color("ffe3a1")) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_detail.text = detail
	_banner_detail.visible = not detail.is_empty()
	_banner_left = seconds
	_banner.show()

## Every creature the mode can show: recruit forms, neutral creeps and
## creatures abilities call up.
func _all_codes() -> Array[String]:
	var codes: Array[String] = []
	for line: Dictionary in ELAutochessRules.FAMILIES:
		for code: String in line.forms:
			if code not in codes: codes.append(code)
	for wave: Array in ELAutochessRules.CREEPS:
		for row: Array in wave:
			if String(row[0]) not in codes: codes.append(String(row[0]))
	if "RDKN" not in codes: codes.append("RDKN")
	return codes.filter(func(code: String) -> bool: return profile.table("CombatCreatures").has(code))

## The loading screen: builds and shows every battlefield, hero and
## creature once, frames every creature's figure and portrait, and decodes
## the interface sounds, so play never stops to load. `loaded` follows.
func load_everything() -> void:
	if loaded_all or not _load_tasks.is_empty(): return
	_build_loading()
	# Quiet while battlefields and effects are prepared.
	board.set_muted(true)
	_warm_holder = Node3D.new()
	stage.add_child(_warm_holder)
	var arenas: Array[String] = []
	for character: String in ELAutochessCharacters.choices(profile):
		var scene := ELAutochessCharacters.arena(profile, character)
		if scene not in arenas: arenas.append(scene)
	# Creature and hero skins decode on every processor core meanwhile.
	_load_tasks.append(["prefetch", ""])
	_load_tasks.append(["prefetched", ""])
	for scene: String in arenas: _load_tasks.append(["arena", scene])
	for character: String in ELAutochessCharacters.choices(profile):
		_load_tasks.append(["hero", character])
		_load_tasks.append(["bust", character])
	var codes := _all_codes()
	for code: String in codes: _load_tasks.append(["model", code])
	_load_tasks.append(["clips", ""])
	_load_tasks.append(["clips_done", ""])
	for code: String in codes: _load_tasks.append(["creature", code])
	_load_tasks.append(["effects", ""])
	for code: String in codes: _load_tasks.append(["figure", code])
	for code: String in codes: _load_tasks.append(["portrait", code])
	_load_tasks.append(["sounds", ""])
	_load_tasks.append(["settle", ""])
	_load_total = _load_tasks.size()

func _build_loading() -> void:
	_loading = ColorRect.new()
	_loading.color = Color("0b0d0e")
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position -= Vector2(260, 60)
	box.add_theme_constant_override("separation", 14)
	_loading.add_child(box)
	var title := H.label(box, _t("Autochess"), 40, H.GOLD)
	title.add_theme_font_override("font", H.serif())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_text = H.label(box, _t("Loading…"), 17, H.MUTED)
	_loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(520, 10)
	_loading_bar.add_theme_stylebox_override("background", H.style(Color("1d2222"), Color("4b5143"), Vector2.ZERO))
	_loading_bar.add_theme_stylebox_override("fill", H.style(H.GOLD.darkened(0.2), H.GOLD, Vector2.ZERO))
	box.add_child(_loading_bar)
	_home_camera()
	_update_camera()

func _load_step() -> void:
	if _load_tasks.is_empty(): return
	# Figures and portraits in flight settle over several frames.
	_framing = _framing.filter(func(figure: Control) -> bool:
		var busy := false
		if figure is ELAutochessFigure: busy = not ELAutochessFigure.is_framed(figure.code) and int(figure.get("_framed")) < 24
		elif figure is ELAutochessBust: busy = not ELAutochessBust.is_measured(figure.hero) and int(figure.get("_framed")) <= 6
		if is_instance_valid(figure) and busy: return true
		if figure is ELAutochessFigure: figure.release()
		if is_instance_valid(figure): figure.queue_free()
		return false)
	if _load_wait > 0:
		_load_wait -= 1
		return
	var started := Time.get_ticks_usec()
	while not _load_tasks.is_empty() and Time.get_ticks_usec() - started < 12000:
		var task: Array = _load_tasks.front()
		var kind := String(task[0])
		if kind in ["figure", "bust"] and _framing.size() >= 12: break
		if kind == "portrait" and portraits.settling() >= 16: break
		if kind == "prefetched" and not profile.finish_textures(): break
		if kind == "clips_done" and not _clips_finished(): break
		if kind == "settle" and (not _framing.is_empty() or portraits.settling() > 0):
			# Whatever has not settled in ten seconds settles on its own later.
			_settle_frames += 1
			if _settle_frames < 600: break
		_load_tasks.pop_front()
		if OS.get_cmdline_user_args().has("--autochess-load-times") and kind != _load_kind:
			print("load phase ", _load_kind, " ended at ", Time.get_ticks_msec())
			_load_kind = kind
		match kind:
			"prefetch":
				var skins := []
				for code: String in _all_codes():
					var row: Dictionary = profile.table("CombatCreatures").get(code, {})
					skins.append("Creatures/" + String(row.get("Texture", "")))
					if row.has("SecTexture"): skins.append("Creatures/" + String(row.SecTexture))
				for character: String in ELAutochessCharacters.choices(profile):
					skins.append("Heroes/" + String(ELAutochessCharacters.row(profile, character).get("Texture", "")).replace("\\", "/"))
				# The battlefields' ground, scenery and backdrop sheets too.
				for character: String in ELAutochessCharacters.choices(profile):
					var scene: Dictionary = profile.table("CombatSceneDB").get(ELAutochessCharacters.arena(profile, character), {})
					for name: Variant in [scene.get("SurfaceTexture", ""), scene.get("Background", "")] + Array(scene.get("Textures", [])):
						if not String(name).is_empty() and "CombatScenes/" + String(name) not in skins: skins.append("CombatScenes/" + String(name))
				profile.prefetch_textures(skins)
			"prefetched", "clips_done":
				pass
			"model":
				var row: Dictionary = profile.table("CombatCreatures").get(String(task[1]), {})
				ELModel.prepare(profile, String(row.get("Model", "")))
			"clips":
				_start_clips()
			"arena":
				board.set_arena(String(task[1]))
				# Drawn for a few frames, so its materials are ready too.
				_load_wait = 3
			"hero":
				board.set_hero(0, String(task[1]))
				_load_wait = 1
			"creature":
				# A dozen at a time stand in view (behind the loading screen).
				if _warm_holder.get_child_count() >= 12: _warm_holder.get_child(0).free()
				var row: Dictionary = profile.table("CombatCreatures").get(String(task[1]), {})
				var model := ELModel.new()
				_warm_holder.add_child(model)
				if model.build(profile, String(row.get("Model", "")), "Creatures/" + String(row.get("Texture", "")), "Creatures/" + String(row.SecTexture) if row.has("SecTexture") else ""):
					model.scale = Vector3.ONE * float(row.get("Scale", 1.0))
					for clip: String in [board._move_clip(model), "uattack", "uhit", "udeath", "usummon", "uinstant", "cidle"]:
						if model.has_clip(clip): model.play(clip)
				var slot := _warm_holder.get_child_count() - 1
				model.position = HOME_TARGET + Vector3(2.0 * (slot / 4), 0, 3.0 * (slot % 4) - 4.5)
				if is_instance_valid(board.effects):
					board.effects.attach(model)
					# Its ability effects once, so the first fight is smooth too.
					board.effects.trigger(String(task[1]), {"Start": [model], "Finish": [model], "Target": [model]})
			"figure":
				var figure := ELAutochessFigure.new()
				figure.size = Vector2(160, 160)
				figure.position = Vector2(-400, -400)
				_loading.add_child(figure)
				figure.show_code(profile, String(task[1]))
				_framing.append(figure)
			"portrait":
				portraits.texture(String(task[1]))
			"bust":
				var bust := ELAutochessBust.new()
				bust.size = Vector2(330, 220)
				bust.position = Vector2(-800, -800)
				_loading.add_child(bust)
				bust.show_hero(profile, String(task[1]))
				_framing.append(bust)
			"effects":
				var target: Node = _warm_holder.get_child(0) if _warm_holder.get_child_count() > 0 else null
				if target != null and is_instance_valid(board.effects):
					var names := {}
					for name: String in ELAutochessBoardView.ABILITY_EFFECTS.values(): names[name] = true
					# The creatures' own ability and summon effects.
					for code: String in _all_codes():
						for item: Array in SummonTable.ability_effects("el2", code) + SummonTable.ability_effects("el1", code) + SummonTable.trigger_effects("el2", code).map(func(e): return [e]):
							names[String(item[0])] = true
						for effect: String in SummonTable.card_effects(profile, code): names[effect] = true
					for name: String in names:
						board.effects.play(name, {"Start": [target], "Finish": [target], "Target": [target]})
						if is_instance_valid(board.audio): ELAudio.sound(profile, board.audio.effect_sound(name))
				_load_wait = 2
			"sounds":
				for path: String in SOUNDS.values() + [EVOLUTION_SOUND, LEVEL_SOUND, ELUiSounds.DEFAULT, ELUiSounds.ERROR, "Buttons/StartCombat.wav", "Buttons/Victory.wav", "Buttons/Retreat.wav", "Buttons/ChooseHero.wav"]:
					ELAudio.sound(profile, path)
			"settle":
				for old: Node in _warm_holder.get_children(): old.queue_free()
				_finish_loading()
				return
		if _load_wait > 0: break
	var done := _load_total - _load_tasks.size()
	_loading_bar.value = 100.0 * done / maxf(1.0, _load_total)
	var current := String(_load_tasks.front()[0]) if not _load_tasks.is_empty() else ""
	_loading_text.text = _t({"prefetch": "Decoding textures…", "prefetched": "Decoding textures…", "arena": "Loading battlefields…", "hero": "Loading heroes…", "creature": "Loading creatures…", "model": "Loading creatures…", "clips": "Loading creatures…", "clips_done": "Loading creatures…",
		"figure": "Preparing creature figures…", "portrait": "Preparing portraits…"}.get(current, "Loading…"))

const WARM_CLIPS := ["crun", "cwalk", "uattack", "uhit", "udeath", "usummon", "uinstant", "uvictory", "cidle"]

## Decodes every prepared creature's clips on worker threads.
func _start_clips() -> void:
	_clip_jobs = []
	for code: String in _all_codes():
		var template := ELArchive.key(String(profile.table("CombatCreatures").get(code, {}).get("Model", "")))
		var resources: Dictionary = profile.model_resources.get(template, {})
		if resources.is_empty() or resources.animations == null: continue
		for clip: String in WARM_CLIPS:
			if resources.clips.has(clip) or not resources.animations.has(clip): continue
			if _clip_jobs.any(func(job: Dictionary) -> bool: return job.resources == resources and job.clip == clip): continue
			_clip_jobs.append({"resources": resources, "clip": clip, "animations": resources.animations, "links": resources.links})
	var jobs := _clip_jobs
	_clip_task = WorkerThreadPool.add_group_task(func(index: int): jobs[index].tracks = ELModel.decode_clip(jobs[index].animations, jobs[index].clip, jobs[index].links), jobs.size()) if not jobs.is_empty() else -1

func _clips_finished() -> bool:
	if _clip_task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_clip_task): return false
		WorkerThreadPool.wait_for_group_task_completion(_clip_task)
		_clip_task = -1
	for job: Dictionary in _clip_jobs:
		if job.has("tracks") and not job.resources.clips.has(job.clip): job.resources.clips[job.clip] = job.tracks
	_clip_jobs = []
	return true

func _finish_loading() -> void:
	_load_tasks.clear()
	loaded_all = true
	# The framed figures stay ready for the shop and reserves.
	for figure: Variant in _framing:
		if is_instance_valid(figure): figure.release()
	if is_instance_valid(_loading): _loading.queue_free()
	if is_instance_valid(_warm_holder): _warm_holder.queue_free()
	loaded.emit()

func _exit_tree() -> void:
	ELAutochessFigure.free_spares()

func _process(delta: float) -> void:
	_load_step()
	if is_instance_valid(board.arena) and camera.environment != board.arena.environment_settings: camera.environment = board.arena.environment_settings
	if path_tracing != null and is_instance_valid(board.arena) and _traced_arena != board.arena and camera.is_current():
		_traced_arena = board.arena
		path_tracing.register(camera, stage, board.arena.light, board.arena.environment_settings, board.effects, board.arena)
	_board_arrivals()
	if game == null:
		if visible:
			_camera_yaw += delta * 0.05
			_update_camera()
		return
	if online != null: online.poll(delta)
	if game == null: return
	if online == null or online.is_host: game.process(delta)
	else: online.process_guest(delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0: _message.text = ""
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(_banner_left * 4.0, 0.0, 1.0)
		if _banner_left <= 0.0: _banner.hide()
	for uid: int in _pulses.keys():
		_pulses[uid] = float(_pulses[uid]) - delta
		if float(_pulses[uid]) <= 0.0: _pulses.erase(uid)
	if _modal.visible or _overview.visible: _notice.modulate.a = 0.0
	_step_camera(delta)
	_hover(delta)
	_update_cursor()
	_update_clock()
	_sync_board()
	if is_instance_valid(board.arena) and camera.environment != board.arena.environment_settings: camera.environment = board.arena.environment_settings
	if game.stage == "fight": _refresh_damage()
	overlay.queue_redraw()
	if _overview.visible: _overview.queue_redraw()

func _update_cursor() -> void:
	var wanted := "default"
	if game != null and watched == me and game.stage == "prepare" and board.battle == null and not _modal.visible and not _overview.visible:
		if _drag_from != Vector2.INF and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var held := board.pick(camera, _drag_from)
			if not held.is_empty() and str(held.key).begins_with("p"): wanted = "grap2"
		if wanted == "default":
			var control := get_viewport().gui_get_hovered_control()
			var node: Node = control
			while node != null and node != self:
				if node is H.Reserve:
					var slot := _reserves.find(node)
					var slots := company().reserve_slots()
					if slot >= 0 and slot < slots.size() and not slots[slot].is_empty(): wanted = "grap1"
					break
				node = node.get_parent()
			if wanted == "default" and _on_board:
				var hit := board.pick(camera, _board_mouse)
				if not hit.is_empty() and str(hit.key).begins_with("p"): wanted = "grap1"
	cursor_name = wanted

func _hover(delta: float) -> void:
	if not _selected.is_empty() or _modal.visible or _overview.visible or _orbiting:
		_hover_key = ""
		# Turning the camera or opening a window ends a hover's details.
		if not (_modal.visible or _overview.visible or _orbiting) or not _rail.get_meta("hover", false): return
		_hide_rail()
		return
	var key := ""
	var control := get_viewport().gui_get_hovered_control() if not _touch_pointer else null
	var node: Node = control
	while node != null and node != self:
		# The key names what the slot holds, so a bought offer or a moved
		# reserve creature ends its details even with the pointer still.
		if node is H.Offer:
			var index := _offers.find(node)
			var shop := company().shop
			if index >= 0 and index < shop.size() and int(shop[index].family) >= 0: key = "offer:%d:%d:%d" % [index, int(shop[index].family), int(shop[index].get("rank", 0))]
			break
		if node is H.Reserve:
			var index := _reserves.find(node)
			var slots := viewed().reserve_slots()
			if index >= 0 and index < slots.size() and not slots[index].is_empty(): key = "reserve:%d:%d:%d" % [index, int(slots[index].get("uid", -1)), int(slots[index].get("rank", 0))]
			break
		node = node.get_parent()
	if key.is_empty() and _on_board and not _touch_pointer:
		var hit := board.pick(camera, _board_mouse)
		if not hit.is_empty(): key = "unit:" + str(hit.key)
	if key != _hover_key:
		_hover_key = key
		_hover_wait = 0.18
		return
	if _hover_wait <= 0.0: return
	_hover_wait -= delta
	if _hover_wait > 0.0: return
	if key.is_empty():
		if _rail.get_meta("hover", false): _hide_rail()
		return
	var parts := key.split(":")
	var index := int(parts[1]) if parts[0] != "unit" else -1
	_rail.set_meta("shown", "")
	if parts[0] == "offer":
		var own := company()
		if index < 0 or index >= own.shop.size() or int(own.shop[index].family) < 0: return
		_inspect(int(own.shop[index].family), int(own.shop[index].get("rank", 0)), {}, index)
	elif parts[0] == "reserve":
		var slots := viewed().reserve_slots()
		if index < 0 or index >= slots.size() or slots[index].is_empty(): return
		_inspect(int(slots[index].family), int(slots[index].rank), slots[index])
	else:
		var hit := board.pick(camera, _board_mouse)
		if hit.is_empty(): return
		_inspect_hit(hit)
	_rail.set_meta("hover", true)

func _update_clock() -> void:
	match game.stage:
		"prepare":
			_phase.text = _t("Preparing")
			_clock.text = _t("Battle in %ds") % ceili(game.prepare_left)
			var urgent := game.prepare_left <= 10.0
			_clock.add_theme_color_override("font_color", H.LOSS.lerp(H.GOLD, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)) if urgent else H.GOLD)
		"fight":
			_phase.text = _t("Battle")
			var info := game.board_of(watched)
			var seconds := 0.0
			if not info.is_empty(): seconds = (game.boards[int(info.index)].battle as ELAutochessBattle).time
			_clock.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
			_clock.add_theme_color_override("font_color", H.GOLD)
		"result":
			_phase.text = _t("Round over")
			_clock.text = ""
		"over":
			_phase.text = _t("Tournament over")
			_clock.text = ""

## Puts the watched hero's board on screen: the formation while preparing, or
## the battle that hero is fighting.
## A Synthet's nickname without its serial ("Alpha-200E "Insidious"").
static func _short_name(name: String) -> String:
	for marks: Array in [["«", "»"], ["\"", "\""]]:
		var start := name.find(marks[0])
		var end := name.find(marks[1], start + 1)
		if start > 0 and end > start + 1: return name.substr(start + 1, end - start - 1) + name.substr(end + 1)
	return name

func _name_of(player: int) -> String:
	return ELAutochessCharacters.shown(profile, game.names[player])

func _sync_board() -> void:
	var owner := viewed()
	board.set_arena(ELAutochessCharacters.arena(profile, owner.character))
	board.set_hero(0, owner.character)
	var rival := game.opponent_for(watched)
	board.set_hero(1, game.companies[rival].character if rival >= 0 and rival != watched and not game.is_creep_round() else "")
	# A hero out of health falls once the bolts have landed, and stays down.
	var finished := game.stage != "fight"
	board.set_fallen(0, owner.health <= 0, BOLTS_LAND, finished and _shown_board < 0)
	if rival >= 0 and rival != watched and not game.is_creep_round(): board.set_fallen(1, game.companies[rival].health <= 0, BOLTS_LAND)
	board.set_fire(game.stage == "prepare")
	if game.stage == "fight" or (game.stage in ["result", "over"] and not game.boards.is_empty()):
		var info := game.board_of(watched)
		if info.is_empty():
			if _shown_board != -2:
				board.clear_units()
				board.show_preparation(owner.army)
				_shown_board = -2
			return
		if _shown_board != int(info.index) or _shown_team != int(info.team) or board.battle != game.boards[int(info.index)].battle:
			_shown_board = int(info.index)
			_shown_team = int(info.team)
			board.show_battle(game.boards[_shown_board].battle, _shown_team)
		return
	if _shown_board != -1:
		board.clear_units()
		_shown_board = -1
	board.flip = false
	board.show_preparation(owner.army)

func _on_fight() -> void:
	_close_modal()
	_shown_board = -3
	_banner_text(_round_name(), _t("Battle begins"), 1.0)
	H.play_sound("Buttons/StartCombat.wav")
	_refresh()

func _on_board_finished(index: int) -> void:
	var row: Dictionary = game.boards[index]
	# The survivors' fire at the losing hero on the board being watched.
	if board.battle == row.battle: board.survivors_fire((row.battle as ELAutochessBattle).winner)
	for player: int in [int(row.home), int(row.visitor)]:
		if player != watched: continue
		var result: Dictionary = game.round_results.get(player, {})
		if result.is_empty(): continue
		var winner := int(result.winner)
		var loss := int(result.health_lost)
		_banner_text(_t("Victory") if winner == 0 else _t("Draw") if winner == -1 else _t("Defeat"), _t("%d health lost") % loss if loss > 0 else "", 2.0, Color("ffe3a1") if winner == 0 else Color("ff9a8d"))
		H.play_sound("Buttons/Victory.wav" if winner == 0 else "Buttons/Retreat.wav")
		board.hero_react(0, "uvictory" if winner == 0 else "uhit")
	_queue_refresh()

func _on_eliminated(player: int, place: int) -> void:
	if player == me:
		_show_end(_t("You finished in place %d of %d") % [place, ELAutochessRules.PLAYER_COUNT])
	else: _say(_t("%s is out of the tournament (place %d).") % [_name_of(player), place], 4.0)

func _round_name() -> String:
	return _t("Round %d") % game.round_number

# --- Refresh --------------------------------------------------------------------

## Match changes (bots buying, boards finishing) refresh the screen once at
## the end of the frame, however many arrive in it.
var _refresh_queued := false
func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	(func():
		_refresh_queued = false
		_refresh()).call_deferred()

func _refresh() -> void:
	if game == null: return
	var own := company()
	var preparing := game.stage == "prepare"
	var represented := ELAutochessAlliances.counts(profile, own.army)
	_shop_panel.visible = _shop_open and game.stage != "over" and own.health > 0
	for index in _offers.size():
		var offer: H.Offer = _offers[index]
		var empty := index >= own.shop.size() or int(own.shop[index].family) < 0
		offer.visible = not empty
		_recruited[index].text = _t("Recruited") if empty else ""
		if not empty: offer.show_offer(profile, own, index, represented)
	_refresh_button.price = own.refresh_cost()
	_refresh_button.caption = ""
	_refresh_button.disabled = not own.can_shop() or own.shop.all(func(o: Dictionary) -> bool: return bool(o.locked)) or not own.spending_error(own.refresh_cost()).is_empty()
	_refresh_button.tooltip_text = _t("Refresh · ◈ %d") % own.refresh_cost() + "\n" + _t("Refresh unlocked offers. Locked offers stay.") + " (R)"
	_refresh_button.queue_redraw()
	var maxed := own.level_needed() == 0
	_level_button.value = str(own.capacity())
	_level_button.price = -1 if maxed else ELAutochessRules.TRAINING_COST
	_level_button.progress = 1.0 if maxed else float(own.level_progress()) / own.level_needed()
	_level_button.caption = _t("Max level") if maxed else _t("XP %d/%d") % [own.level_progress(), own.level_needed()]
	_level_button.disabled = not own.can_shop() or maxed or not own.spending_error(ELAutochessRules.TRAINING_COST).is_empty()
	_level_button.tooltip_text = _t("Level %d") % own.capacity() + "\n" + _t("Gain %d XP for ◈ %d. The level is how many creatures you can field; it also brings costlier offers.") % [ELAutochessRules.TRAINING_XP, ELAutochessRules.TRAINING_COST] + " (F)"
	_level_button.queue_redraw()
	_ether.text = str(own.ether)
	var income := own.income_preview()
	_income.text = _t("Income +%d") % int(income.total)
	_income.tooltip_text = _income_details(income)
	_health.text = str(own.health)
	var multi := online != null or game.controllers.count("human") + game.controllers.count("remote") > 1
	_start.visible = preparing and own.health > 0
	_start.text = (_t("Waiting…") if game.ready[me] else _t("Ready")) if multi else _t("Start battle")
	H.fit(_start, _start.text, 196 - 28, 21, 14)
	_start.disabled = own.deployed_count() == 0 and not own.army.is_empty()
	_speed.visible = game.stage == "fight" and online == null
	_speed.text = "×%d" % int(game.speed)
	_round_title.text = _round_name()
	if game.is_creep_round(): _encounter.text = _t("Neutral round")
	else:
		var opponent := game.opponent_for(watched)
		_encounter.text = ((_t("Opponent: %s (copy)") if game.ghost_for(watched) else _t("Opponent: %s")) % _name_of(opponent)) if opponent >= 0 else ""
	_refresh_standings()
	_refresh_alliances()
	_refresh_items()
	_refresh_bench()
	_refresh_damage()
	_refresh_rail()
	if not own.item_offers.is_empty() and preparing and watched == me:
		var key := "%d:%d" % [game.round_number, own.item_reward_round]
		if key != _reward_shown:
			_reward_shown = key
			_show_rewards()
	elif _modal.get_meta("kind", "") == "rewards": _close_modal()
	if game.stage != _last_stage or game.round_number != _last_round:
		if preparing and game.round_number != _last_round:
			_selected.clear()
			_banner_text(_round_name(), _income_banner(own), 2.6)
		_last_stage = game.stage
		_last_round = game.round_number
		if game.stage == "over":
			var place := game.placements[me]
			if place == 1: board.hero_react(0, "uvictory")
			_show_end(_t("Victory! You won the tournament.") if place == 1 else _t("You finished in place %d of %d") % [place, ELAutochessRules.PLAYER_COUNT])
	_layout()

func _income_details(income: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in ["base", "victory", "interest", "streak"]:
		if int(income.get(key, 0)) > 0: parts.append({"base": _t("+%d base"), "victory": _t("+%d victory"), "interest": _t("+%d interest"), "streak": _t("+%d streak")}[key] % int(income[key]))
	return "   ".join(parts)

func _income_banner(own: ELAutochessCompany) -> String:
	var result: Dictionary = own.last_result
	if result.is_empty() or not result.has("income"): return ""
	var income: Dictionary = result.income
	return _income_details(income) + "\n" + _t("◈ %d in total") % int(income.get("total", 0))

## Players by health, each with the hero's portrait from the game.
func _refresh_standings() -> void:
	for child: Node in _standings.get_children(): child.queue_free()
	var toolbar := HBoxContainer.new()
	_standings.add_child(toolbar)
	var heading := H.button(toolbar, _t("Players · %d") % game.alive_players().size(), Callable())
	heading.add_theme_font_size_override("font_size", 14)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boards := H.button(toolbar, "▦", _toggle_overview)
	boards.tooltip_text = _t("All boards") + " (Tab)"
	boards.custom_minimum_size = Vector2(30, 28)
	for player in game.standings():
		var alive := game.companies[player].health > 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_standings.add_child(row)
		var picture := TextureRect.new()
		picture.texture = ELAutochessCharacters.portrait(profile, game.companies[player].character)
		picture.custom_minimum_size = Vector2(30, 24)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.modulate = Color.WHITE if alive else Color(0.5, 0.5, 0.5, 0.6)
		row.add_child(picture)
		var name := Button.new()
		name.text = _short_name(_name_of(player))
		name.tooltip_text = _name_of(player)
		H.fit(name, name.text, STANDINGS_WIDTH - 30 - 28 - 20, 14, 10)
		name.focus_mode = Control.FOCUS_NONE
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.custom_minimum_size = Vector2(0, 24)
		name.add_theme_font_size_override("font_size", 14)
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.content_margin_left = 6
		line.border_width_left = 3 if player == watched else 0
		line.border_color = Color("f2d58f")
		name.add_theme_stylebox_override("normal", line)
		name.add_theme_stylebox_override("hover", H.style(Color.TRANSPARENT, H.GOLD, Vector2(6, 1)))
		name.add_theme_stylebox_override("pressed", H.style(Color.TRANSPARENT, H.GOLD, Vector2(6, 1)))
		name.add_theme_stylebox_override("disabled", line)
		name.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var color := H.GOLD
		var result: Dictionary = game.round_results.get(player, {})
		if not result.is_empty() and game.stage != "prepare": color = H.WIN if int(result.winner) == 0 else H.LOSS if int(result.winner) == 1 else H.GOLD
		if player == watched and color == H.GOLD: color = Color("f2d58f")
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			name.add_theme_color_override(state, color if alive else Color(H.MUTED, 0.7))
		H.outline(name)
		name.disabled = not alive
		name.tooltip_text = _t("Watch this board")
		name.pressed.connect(_watch.bind(player))
		row.add_child(name)
		var hp := game.companies[player].health
		var value := H.label(row, str(hp) if hp > 0 else "#%d" % game.placements[player] if game.placements[player] > 0 else _t("Out"), 14, H.LOSS if hp > 0 and hp < 25 else H.GOLD)
		value.custom_minimum_size.x = 28
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right_column.visible = not _rail.visible

func _watch(player: int) -> void:
	watched = player
	_selected.clear()
	_shown_board = -3
	_overview.hide()
	_hide_rail()
	_refresh()

func _refresh_alliances() -> void:
	var counts := ELAutochessAlliances.counts(profile, viewed().army)
	for key: String in _badges:
		var badge: H.Badge = _badges[key]
		badge.count = int(counts.get(key, 0))
		var level := ELAutochessAlliances.rank(key, badge.count)
		badge.tooltip_text = "%s · %d/%d\n%s\n%s" % [_t(String(ELAutochessAlliances.RULES[key].name)), badge.count, ELAutochessAlliances.next_threshold(key, badge.count), _t(String(ELAutochessAlliances.RULES[key].help)), _t(ELAutochessAlliances.effect(key, level))]
		badge.queue_redraw()

func _refresh_items() -> void:
	for child: Node in _items.get_children(): child.queue_free()
	var own := viewed()
	_items_heading.visible = not own.items.is_empty()
	for item: Dictionary in own.items:
		var kind := String(item.kind)
		var circle := H.ItemCircle.new()
		circle.picture = ELAutochessArtifacts.icon(profile, kind)
		circle.accent = H.cost_accent(ELAutochessArtifacts.tier(kind))
		var chosen := String(_selected.get("kind", "")) == "item" and int(_selected.uid) == int(item.uid)
		circle.chosen = chosen
		circle.spare = int(item.unit_uid) == 0
		var carrier := own.unit(int(item.unit_uid))
		circle.tooltip_text = _item_text(kind) + "\n" + (_t("Carried by %s") % ELAutochessRules.title(profile, String(carrier.code)) if not carrier.is_empty() else _t("Click, then click a creature to give it."))
		circle.pressed.connect(func():
			if watched != me: return
			_selected = {} if chosen else {"kind": "item", "uid": int(item.uid)}
			_say("" if chosen else _t("Choose a creature to carry %s.") % ELAutochessArtifacts.title(profile, kind))
			_refresh())
		_items.add_child(circle)

func _item_text(kind: String) -> String:
	var lines := PackedStringArray([ELAutochessArtifacts.title(profile, kind)])
	for line: String in ELAutochessArtifacts.describe(kind): lines.append(_t(line))
	return "\n".join(lines)

## A summon's sounds: its colour's summon effect (as when a hero summons it)
## and the creature's own Summon.wav where it has one.
func _summon_sound(code: String) -> void:
	if is_instance_valid(board.audio):
		for effect: String in SummonTable.card_effects(profile, code): board.audio.effect(effect)
	var row: Dictionary = profile.table("CombatCreatures").get(code, {})
	var directory := String(row.get("SndDir", ""))
	if not directory.is_empty(): H.play_sound("Creatures/" + directory + "/summon.wav")

## Entrances of the creatures that stepped onto the board. The board builds
## at most two figures a frame, so one whose figure is not built yet waits
## (checked every frame); one no longer on the board is dropped.
func _board_arrivals() -> void:
	if _arriving.is_empty() or game == null: return
	if watched != me:
		_arriving.clear()
		return
	var own := company()
	for uid: int in _arriving.keys():
		var entry := own.unit(uid)
		if entry.is_empty() or not bool(entry.deployed): _arriving.erase(uid)
	for row: Dictionary in board.preparation_rows(own.army):
		if not _arriving.has(int(row.uid)) or not is_instance_valid(row.get("model")): continue
		_arriving.erase(int(row.uid))
		var model: ELModel = row.model
		var code := String(row.code)
		# As in the duel: the colour's summon effect rises at the spot and the
		# creature appears at its summon cue, then plays its entrance clip.
		var delay := 0.0
		if is_instance_valid(board.effects):
			for effect: String in SummonTable.card_effects(profile, code): board.effects.play(effect, {"Target": [model]})
			delay = ELCombatEffects.summon_delay(profile, code)
		_summon_sound(code)
		if delay <= 0.0:
			_enter(model)
			continue
		model.visible = false
		# Held weakly: a new round may free the figure before its cue.
		var held: WeakRef = weakref(model)
		get_tree().create_timer(delay).timeout.connect(func():
			var shown: ELModel = held.get_ref()
			if shown != null: _enter(shown))

## A summoned figure shows and plays its entrance clip.
func _enter(model: ELModel) -> void:
	model.visible = true
	if model.has_clip("usummon"): model.play("usummon")

func _refresh_bench() -> void:
	var own := viewed()
	var slots := own.reserve_slots()
	var kind := String(_selected.get("kind", ""))
	var returning := kind == "field" and watched == me and game.stage == "prepare"
	for slot in _reserves.size():
		var reserve: H.Reserve = _reserves[slot]
		var entry: Dictionary = slots[slot] if slot < slots.size() else {}
		var shown := entry.duplicate()
		if not shown.is_empty(): shown["item"] = own.item_for(int(entry.uid))
		reserve.show_entry(profile, shown, kind in ["reserve", "field"] and not entry.is_empty() and int(_selected.uid) == int(entry.uid), returning)
		reserve.disabled = watched != me
	_board_arrivals()
	_army_label.text = _t("Army %d/%d") % [own.deployed_count(), own.capacity()]
	var chosen := own.unit(int(_selected.get("uid", 0))) if kind in ["field", "reserve"] and watched == me else {}
	_sell_target.visible = not chosen.is_empty() and own.can_shop() and (game.stage == "prepare" or not bool(chosen.deployed))
	if _sell_target.visible:
		_sell_target.text = _t("Sell +◈ %d") % own.sale_value(chosen) + "  (S)"
		_sell_target.tooltip_text = ELAutochessRules.title(profile, String(chosen.code))
	_reserve_label.text = _t("Reserves %d/%d") % [own.bench_count(), own.bench_limit()]

## Damage dealt this round by the watched hero's creatures: model portrait,
## name, stars, amount and a bar against the best of them.
func _refresh_damage() -> void:
	var own := viewed()
	var damage := {}
	if game.stage == "fight":
		var info := game.board_of(watched)
		if not info.is_empty(): damage = (game.boards[int(info.index)].battle as ELAutochessBattle).damage_by_uid(int(info.team))
	else: damage = game.round_results.get(watched, {}).get("damage", {})
	var entries := own.army.filter(func(e: Dictionary) -> bool: return bool(e.deployed))
	var amounts := {}
	for key: Variant in damage: amounts[int(key)] = float(damage[key])
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(amounts.get(int(a.uid), 0.0)) > float(amounts.get(int(b.uid), 0.0)))
	var top := 1.0
	for value: float in amounts.values(): top = maxf(top, value)
	var signature := JSON.stringify(entries.map(func(e: Dictionary) -> Array: return [e.uid, e.code, roundi(float(amounts.get(int(e.uid), 0.0)))]))
	if _damage_list.get_meta("signature", "") == signature: return
	_damage_list.set_meta("signature", signature)
	for child: Node in _damage_list.get_children(): child.queue_free()
	for entry: Dictionary in entries.slice(0, 8):
		var amount := float(amounts.get(int(entry.uid), 0.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		_damage_list.add_child(row)
		var picture := TextureRect.new()
		picture.texture = portraits.texture(String(entry.code))
		picture.custom_minimum_size = Vector2(34, 34)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_constant_override("separation", 3)
		row.add_child(text)
		var line := HBoxContainer.new()
		text.add_child(line)
		var title := H.label(line, ELAutochessRules.title(profile, String(entry.code)), 15)
		H.fit(title, title.text, 140, 15, 11)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var stars := H.Stars.new()
		stars.count = int(entry.rank) + 1
		stars.color = H.line_accent(int(entry.family))
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(stars)
		H.label(line, str(roundi(amount)), 15)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 4
		bar.add_theme_stylebox_override("background", H.style(Color("25342d"), Color.TRANSPARENT, Vector2.ZERO))
		bar.add_theme_stylebox_override("fill", H.style(Color("a6c981"), Color.TRANSPARENT, Vector2.ZERO))
		bar.value = amount / top * 100.0
		text.add_child(bar)
	_damage_heading.visible = not entries.is_empty()

# --- Inspector -----------------------------------------------------------------

func _inspect(line: int, rank: int, entry: Dictionary, offer := -1) -> void:
	if line < 0: return
	for child: Node in _rail_box.get_children():
		child.hide()
		child.queue_free()
	var code := ELAutochessRules.form(line, rank)
	var values := ELAutochessRules.stats(profile, code, ELAutochessRules.tier(line), rank, line)
	var accent := H.line_accent(line)
	_rail.edge = accent
	_rail.queue_redraw()
	H.wrap(_rail_box, ELAutochessRules.title(profile, code), 21, accent).add_theme_font_override("font", H.serif())
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_rail_box.add_child(header)
	var figure := ELAutochessFigure.new()
	figure.custom_minimum_size = Vector2(84, 84)
	header.add_child(figure)
	figure.show_code(profile, code)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	header.add_child(details)
	var names := HFlowContainer.new()
	names.add_theme_constant_override("h_separation", 8)
	details.add_child(names)
	for key: String in ELAutochessAlliances.traits(profile, line):
		H.label(names, _t(String(ELAutochessAlliances.RULES[key].name)), 13, H.ALLIANCE[key])
	H.wrap(details, _t("Tier %d · ◈ %d") % [ELAutochessRules.tier(line), int(ELAutochessRules.family(line).cost)], 12, H.MUTED)
	var left: Dictionary = company().pool_left()
	if left.has(line): H.wrap(details, _t("Shared pool: %d/%d left") % [maxi(0, int(left[line])), ELAutochessRules.pool_size(line)], 12, H.MUTED)
	var stars := H.Stars.new()
	stars.count = rank + 1
	stars.color = accent
	details.add_child(stars)
	_rule(_rail_box)
	H.wrap(_rail_box, _t(String(values.role)), 13, H.MUTED)
	# Every evolution's values, the shown one in bold, as in the Cursed
	# Lands autochess.
	var tiers: Array[Dictionary] = []
	for star in 3: tiers.append(ELAutochessRules.stats(profile, ELAutochessRules.form(line, star), ELAutochessRules.tier(line), star, line))
	_series(_t("Health"), tiers.map(func(v: Dictionary) -> String: return str(int(v.health))), rank)
	_series(_t("Attack"), tiers.map(func(v: Dictionary) -> String: return str(roundi(float(v.damage)))), rank)
	_series(_t("Defense"), tiers.map(func(v: Dictionary) -> String: return str(roundi(float(v.defense)))), rank)
	_series(_t("Attack every"), tiers.map(func(v: Dictionary) -> String: return "%.1f %s" % [float(v.interval), _t("s")]), rank)
	# Each keyword with what it does in these battles, in brackets.
	var flags: Array[String] = []
	for flag: String in values.flags: flags.append(flag)
	if int(values.regen) > 0: flags.append("Regeneration")
	for flag: String in flags:
		var help := String(FLAG_HELP.get(flag, ""))
		H.wrap(_rail_box, _t(_flag_name(flag)) + (" (%s)" % _t(help) if not help.is_empty() else ""), 13, H.GOLD)
	var ability := ELAutochessAbilities.describe(code, float(values.ability_power))
	if not ability.is_empty(): H.wrap(_rail_box, _t(ability), 13)
	if not entry.is_empty():
		_rule(_rail_box)
		var kind := viewed().item_for(int(entry.uid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rail_box.add_child(row)
		if not kind.is_empty():
			var icon := TextureRect.new()
			icon.texture = ELAutochessArtifacts.icon(profile, kind)
			icon.custom_minimum_size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
		H.wrap(row, ELAutochessArtifacts.title(profile, kind) if not kind.is_empty() else _t("Empty item slot"), 14, H.GOLD).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not kind.is_empty():
			for line_text: String in ELAutochessArtifacts.describe(kind): H.wrap(_rail_box, _t(line_text), 13)
	_rule(_rail_box)
	var path := H.Path.new()
	_rail_box.add_child(path)
	path.show_path(profile, portraits, line, viewed().owned_counts(line))
	if offer >= 0:
		if company().shop_completes_upgrade(offer): H.wrap(_rail_box, _t("The highlighted shop copies complete an evolution."), 12, H.ACCENT)
		var error := company().purchase_error(offer)
		if not error.is_empty(): H.wrap(_rail_box, _t(error), 12, H.MUTED)
	_rail.show()
	_rail.set_meta("hover", false)
	_right_column.hide()
	_layout_rail.call_deferred()

## "Health 40 / 76 / 140": the three evolutions with the shown one in bold.
func _series(caption: String, parts: Array, rank: int) -> void:
	var marked := PackedStringArray()
	for index in parts.size():
		marked.append(("[b][color=#f2d58f]%s[/color][/b]" if index == rank else "%s") % String(parts[index]))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("normal_font_size", 14)
	text.add_theme_font_size_override("bold_font_size", 14)
	text.add_theme_color_override("default_color", H.PAPER)
	text.add_theme_color_override("font_outline_color", Color("161616"))
	text.add_theme_constant_override("outline_size", 3)
	text.text = "[color=#b7c0bd]%s[/color]  %s" % [caption, " / ".join(marked)]
	_rail_box.add_child(text)

func _rule(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = Color(H.GOLD, 0.35)
	line.custom_minimum_size.y = 1
	parent.add_child(line)

func _hide_rail() -> void:
	_rail.hide()
	_right_column.show()

func _refresh_rail() -> void:
	var kind := String(_selected.get("kind", ""))
	if kind in ["field", "reserve"]:
		var entry := viewed().unit(int(_selected.uid))
		if entry.is_empty():
			_selected.clear()
			_hide_rail()
		elif _rail.get_meta("shown", "") != "%d:%s:%d" % [entry.uid, entry.code, int(entry.deployed)]:
			_rail.set_meta("shown", "%d:%s:%d" % [entry.uid, entry.code, int(entry.deployed)])
			_inspect(int(entry.family), int(entry.rank), entry)

## What each keyword does in autochess battles (ELAutochessBattle, ELAutochessRules).
const FLAG_HELP := {
	"Fly": "flies; enemies cannot dodge its blows",
	"FS": "its first blow on each enemy lands at once and delays that enemy's swing",
	"Trample": "a killing blow carries on into the next enemy",
	"Berserk": "attacks 10% faster and keeps hitting its target until it falls",
	"Restless": "attacks 5% faster and uses abilities without pausing",
	"Lifetap": "heals a quarter of the damage it deals",
	"Elusive": "slips past the front line to reach archers and casters",
	"UB": "slips past the front line to reach archers and casters",
	"Disenchant": "each blow removes the target's enchantments",
	"TeamAttack": "+15% damage for each ally attacking the same enemy, up to two",
	"NoUntap": "attacks 45% slower but hits 45% harder",
	"Destroy": "no effect in autochess battles",
	"NSS": "moves faster and uses its first ability sooner",
	"NoTarget": "enemy abilities and poisons do not affect it",
	"NoAffect": "enemy abilities and poisons do not affect it",
	"Outerplanar": "takes 25% less damage from abilities and artifacts",
	"Regeneration": "recovers health after two seconds without taking damage",
}

func _flag_name(flag: String) -> String:
	return {"Fly": "Flying", "FS": "First strike", "Trample": "Trample", "Berserk": "Bloodthirsty", "Restless": "Tireless",
		"Lifetap": "Vampire", "Elusive": "Evasive", "UB": "Unblockable", "Disenchant": "Breaks enchantments",
		"TeamAttack": "Guard", "NoUntap": "Lazy", "Destroy": "Poisonous", "NSS": "Swift", "NoTarget": "Ether protection",
		"NoAffect": "Magic screen", "Outerplanar": "Colorless"}.get(flag, flag)

# --- Modals ---------------------------------------------------------------------

func _open_modal(title: String, kind: String, width := 360.0, locked := false) -> void:
	for child: Node in _modal_box.get_children():
		child.hide()
		child.queue_free()
	_modal.set_meta("kind", kind)
	if locked: _modal.set_meta("locked", true)
	elif _modal.has_meta("locked"): _modal.remove_meta("locked")
	_modal_box.custom_minimum_size.x = width
	var heading := H.label(_modal_box, title, 26, H.GOLD, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal.show()
	_layout.call_deferred()

func _close_modal() -> void:
	_modal.hide()
	_modal.set_meta("kind", "")
	if game != null and online == null: game.paused = false

## Three spells or artifacts after a neutral round; the choice joins the
## artifact list on the left.
func _show_rewards() -> void:
	_open_modal(_t("Choose a spell or artifact"), "rewards", 760.0, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_modal_box.add_child(row)
	var own := company()
	for index in own.item_offers.size():
		var kind := own.item_offers[index]
		var card := Button.new()
		card.custom_minimum_size = Vector2(240, 250)
		card.clip_contents = false
		card.focus_mode = Control.FOCUS_NONE
		var accent := H.cost_accent(ELAutochessArtifacts.tier(kind))
		card.add_theme_stylebox_override("normal", H.style(Color("1b2224"), accent, Vector2(10, 10)))
		card.add_theme_stylebox_override("hover", H.style(Color("2a3538"), H.GOLD, Vector2(10, 10)))
		card.add_theme_stylebox_override("pressed", H.style(Color("504a35"), H.GOLD, Vector2(10, 10)))
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.pressed.connect(func():
			_close_modal()
			_act("choose_item", [index]))
		row.add_child(card)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12; box.offset_right = -12; box.offset_top = 12; box.offset_bottom = -12
		box.add_theme_constant_override("separation", 6)
		card.add_child(box)
		var icon := TextureRect.new()
		icon.texture = ELAutochessArtifacts.icon(profile, kind)
		icon.custom_minimum_size = Vector2(0, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
		H.wrap(box, ELAutochessArtifacts.title(profile, kind), 17, accent).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		H.wrap(box, _t("Tier %d") % ELAutochessArtifacts.tier(kind), 12, H.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for line: String in ELAutochessArtifacts.describe(kind): H.wrap(box, _t(line), 13)
		for control: Control in card.find_children("*", "Control", true, false): control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The card is as tall as its text.
		box.minimum_size_changed.connect(func(): card.custom_minimum_size.y = maxf(250.0, box.get_combined_minimum_size().y + 24.0))
	H.wrap(_modal_box, _t("Give it to a creature from the artifact list on the left."), 13, H.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _toggle_menu() -> void:
	if _modal.visible and _modal.get_meta("kind", "") == "menu":
		_close_modal()
		return
	if _modal.visible: return
	_open_modal(_t("Menu"), "menu", 300.0)
	H.button(_modal_box, _t("Resume"), _close_modal)
	# The game stays paused under the settings; the menu returns after them.
	H.button(_modal_box, ELRemakeText.t("Remake settings…", profile), func(): remake_settings_requested.emit())
	H.button(_modal_box, _t("Leave (the game is saved)") if online == null else _t("Leave the online game"), _leave)
	H.button(_modal_box, _t("Concede and end the game"), _concede)
	if online == null: game.paused = true

func _show_end(text: String) -> void:
	_open_modal(text, "end", 380.0, true)
	H.button(_modal_box, _t("Watch the other boards"), _close_modal)
	H.button(_modal_box, _t("Return to the main menu"), _quit_finished)

# --- Actions --------------------------------------------------------------------

func _buy(index: int) -> void:
	if watched != me: _watch(me)
	_act("buy", [index])

func _offer_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var own := company()
		if index < own.shop.size() and int(own.shop[index].family) >= 0:
			_rail.set_meta("shown", "")
			_inspect(int(own.shop[index].family), int(own.shop[index].get("rank", 0)), {}, index)

func _start_pressed() -> void:
	if game.stage != "prepare": return
	if online != null or game.controllers.count("human") + game.controllers.count("remote") > 1:
		_act("ready", [not game.ready[me]])
		return
	if company().deployed_count() == 0 and not company().army.is_empty():
		_say(_t("Deploy at least one creature before starting."))
		return
	game.start_fight()

func _toggle_speed() -> void:
	var index := SPEEDS.find(game.speed)
	game.speed = SPEEDS[(index + 1) % SPEEDS.size()]
	_refresh()

func _sell_selected() -> void:
	if String(_selected.get("kind", "")) in ["field", "reserve"]:
		# A carried artifact is not sold: it returns to the artifacts list.
		var uid := int(_selected.uid)
		var carried := company().item_for(uid)
		_act("sell", [uid])
		_selected.clear()
		_hide_rail()
		_refresh()
		if not carried.is_empty() and company().unit(uid).is_empty(): _say(_t("%s returns to your artifacts.") % ELAutochessArtifacts.title(profile, carried))

func _select(value: Dictionary) -> void:
	if watched != me: return
	if _selected == value:
		_selected.clear()
		_hide_rail()
	else: _selected = value
	_rail.set_meta("shown", "")
	_refresh()

func _reserve_pressed(slot: int) -> void:
	if watched != me: return
	var slots := company().reserve_slots()
	var entry: Dictionary = slots[slot] if slot < slots.size() else {}
	var kind := String(_selected.get("kind", ""))
	if kind == "field" or (kind == "reserve" and int(entry.get("uid", -1)) != int(_selected.uid)):
		_act("bench", [int(_selected.uid), slot])
		_selected.clear()
		_hide_rail()
	elif kind == "item" and not entry.is_empty():
		_act("equip", [int(_selected.uid), int(entry.uid)])
		_selected.clear()
		_message.text = ""
	elif not entry.is_empty():
		_select({"kind": "reserve", "uid": int(entry.uid)})
		return
	_refresh()

func _reserve_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var slots := viewed().reserve_slots()
		if slot < slots.size() and not slots[slot].is_empty():
			_rail.set_meta("shown", "")
			_inspect(int(slots[slot].family), int(slots[slot].rank), slots[slot])

## Whether the mouse rests on the battlefield itself (its last move reached
## no interface element), and where.
var _on_board := false
var _board_mouse := Vector2.ZERO

func _notification(what: int) -> void:
	# A pointer that leaves the window no longer hovers the battlefield.
	if what == NOTIFICATION_WM_MOUSE_EXIT: _on_board = false

## The pointer comes from a touch screen: it stays where the last tap was,
## so it never hovers (a tap shows the details instead).
var _touch_pointer := false

func _input(event: InputEvent) -> void:
	# Every move first counts as over the interface; one that no control
	# takes reaches _unhandled_input and marks the battlefield.
	if event is InputEventMouseMotion: _on_board = false
	if event is InputEventMouse: _touch_pointer = event.device == InputEvent.DEVICE_ID_EMULATION

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_board = true
		_board_mouse = event.position
	if game == null or not is_visible_in_tree() or not hud.visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R: _act("refresh", [])
			KEY_F: _act("train", [])
			KEY_SPACE: _start_pressed()
			KEY_Z:
				if event.ctrl_pressed: _act("undo", [])
			KEY_S:
				if not _selected.is_empty(): _sell_selected()
			KEY_ESCAPE:
				if _modal.visible and not _modal.has_meta("locked"): _close_modal()
				elif _overview.visible: _overview.hide()
				elif not _selected.is_empty():
					_selected.clear()
					_hide_rail()
					_refresh()
				else: _toggle_menu()
			KEY_TAB: _toggle_overview()
			KEY_HOME:
				_home_camera()
			_: return
		get_viewport().set_input_as_handled()
		return
	if _modal.visible or _overview.visible: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera_distance = clampf(_camera_distance * 0.92, 14.0, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera_distance = clampf(_camera_distance * 1.08, 14.0, 60.0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_orbiting = true
				_orbit_from = event.position
				_orbit_moved = false
			else:
				_orbiting = false
				if not _orbit_moved: _right_click(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _drag_from = event.position
			else:
				var moved := _drag_from != Vector2.INF and _drag_from.distance_to(event.position) > 10.0
				if moved: _drop(_drag_from, event.position)
				else: _left_click(event.position)
				_drag_from = Vector2.INF
	elif event is InputEventMouseMotion and _orbiting:
		if (event.position - _orbit_from).length() > 4.0: _orbit_moved = true
		if _orbit_moved:
			_camera_yaw -= event.relative.x * 0.006
			_camera_pitch = clampf(_camera_pitch + event.relative.y * 0.004, 0.25, 1.35)

func _left_click(at: Vector2) -> void:
	var hit := board.pick(camera, at)
	if watched != me:
		if not hit.is_empty(): _inspect_hit(hit)
		return
	var kind := String(_selected.get("kind", ""))
	var preparing := game.stage == "prepare" and board.battle == null
	# A click on the selected creature itself nudges it to that spot.
	if not hit.is_empty() and preparing and kind == "field" and int(hit.uid) == int(_selected.uid): hit = {}
	if not hit.is_empty() and preparing and str(hit.key).begins_with("p"):
		var uid := int(hit.uid)
		if kind == "reserve":
			_act("swap", [int(_selected.uid), uid])
			_selected.clear()
			_hide_rail()
		elif kind == "item":
			_act("equip", [int(_selected.uid), uid])
			_selected.clear()
			_message.text = ""
		else:
			_select({"kind": "field", "uid": uid})
			return
		_refresh()
		return
	if not hit.is_empty():
		_inspect_hit(hit)
		return
	if not preparing:
		_selected.clear()
		_hide_rail()
		return
	var point := board.ground_point(camera, at)
	if point == Vector2.INF: return
	if kind in ["field", "reserve"]:
		_act("deploy", [int(_selected.uid), point.x, point.y])
		_selected.clear()
		_hide_rail()
		_refresh()
	elif not kind.is_empty():
		_selected.clear()
		_hide_rail()
		_refresh()

func _drop(from: Vector2, to: Vector2) -> void:
	if watched != me or game.stage != "prepare": return
	var hit := board.pick(camera, from)
	if hit.is_empty() or not str(hit.key).begins_with("p"): return
	var point := board.ground_point(camera, to)
	if point == Vector2.INF: return
	_act("deploy", [int(hit.uid), point.x, point.y])

func _right_click(at: Vector2) -> void:
	var hit := board.pick(camera, at)
	if hit.is_empty():
		_selected.clear()
		_hide_rail()
		_refresh()
		return
	_inspect_hit(hit)

func _inspect_hit(hit: Dictionary) -> void:
	_rail.set_meta("shown", "")
	var entry := viewed().unit(int(hit.uid))
	if not entry.is_empty():
		_inspect(int(entry.family), int(entry.rank), entry)
		return
	var code := String(hit.code)
	var line := ELAutochessRules.family_of(code)
	if line >= 0: _inspect(line, maxi(0, ELAutochessRules.family(line).forms.find(code)), {})

# --- Camera, overlay, overview ---------------------------------------------------

func _step_camera(delta: float) -> void:
	var pan := Vector3.ZERO
	var forward := Vector3(-sin(_camera_yaw), 0, -cos(_camera_yaw))
	var right := Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit) and not _modal.visible:
		if Input.is_key_pressed(KEY_W): pan += forward
		if Input.is_key_pressed(KEY_S) and _selected.is_empty(): pan -= forward
		if Input.is_key_pressed(KEY_A): pan -= right
		if Input.is_key_pressed(KEY_D): pan += right
		if Input.is_key_pressed(KEY_E): _camera_yaw += delta * 1.4
		if Input.is_key_pressed(KEY_Q): _camera_yaw -= delta * 1.4
	if pan != Vector3.ZERO:
		_camera_target += pan.normalized() * delta * 16.0
		_camera_target.x = clampf(_camera_target.x, -16, 16)
		_camera_target.z = clampf(_camera_target.z, -12, 12)
	_update_camera()

func _home_camera() -> void:
	_camera_yaw = HOME_YAW
	_camera_pitch = HOME_PITCH
	_camera_distance = HOME_DISTANCE
	_camera_target = HOME_TARGET

func _update_camera() -> void:
	var direction := Vector3(sin(_camera_yaw) * cos(_camera_pitch), sin(_camera_pitch), cos(_camera_yaw) * cos(_camera_pitch))
	camera.position = _camera_target + direction * _camera_distance
	camera.look_at(_camera_target + Vector3(0, 1.0, 0), Vector3.UP)

func _stats(code: String, line: int, rank: int) -> Dictionary:
	var key := "%s|%d" % [code, rank]
	if not _stats_cache.has(key): _stats_cache[key] = ELAutochessRules.stats(profile, code, ELAutochessRules.tier(line), rank, line)
	return _stats_cache[key]

## Above every creature: its stars, its health as a number and a thin bar
## (blue for the watched hero's side, red for the other); the deployment
## area while preparing; evolution marks; floating damage numbers.
func _draw_overlay() -> void:
	if game == null or not is_instance_valid(board) or _overview.visible: return
	var font := get_theme_default_font()
	var s := ui_scale
	if board.battle == null:
		var prepared := _placed(board.preparation_rows(viewed().army), s)
		for row: Dictionary in prepared:
			# A creature being summoned is labelled once it has appeared.
			if not row.model.visible: continue
			var at: Vector2 = row.screen
			var values := _stats(String(row.code), int(row.family), int(row.rank))
			_draw_head(font, at, int(row.rank), H.line_accent(int(row.family)), "%d/%d" % [int(values.health), int(values.health)], 1.0, Color("5aa6c8"), s)
			_draw_item(at, viewed().item_for(int(row.uid)), s)
			var outline := board.screen_rect(camera, row.model)
			if String(_selected.get("kind", "")) == "field" and int(_selected.uid) == int(row.uid): _draw_frame(outline, 0.0, H.GOLD, s)
			if _pulses.has(int(row.uid)): _draw_pulse(outline, float(_pulses[int(row.uid)]), s)
	var rival := game.opponent_for(watched)
	for row: Dictionary in _placed(board.health_rows(), s):
		var at: Vector2 = row.screen
		var color := Color("5aa6c8") if row.friend else Color("c8574f")
		_draw_head(font, at, int(row.rank), H.cost_accent(int(row.tier)), str(ceili(float(row.hp))), float(row.hp) / maxf(1.0, float(row.max)), color, s, float(row.shield) / maxf(1.0, float(row.max)))
		var carrier := viewed() if row.friend else (game.companies[rival] if rival >= 0 else null)
		if carrier != null: _draw_item(at, carrier.item_for(int(row.uid)), s, float(row.get("pop", 0.0)))
	# The heroes on the sideline: their name and the tournament health left.
	for row: Dictionary in board.hero_rows():
		if camera.is_position_behind(row.at): continue
		var player := watched if int(row.side) == 0 else rival
		if player < 0 or player >= game.companies.size(): continue
		var hero_health := maxi(0, game.companies[player].health)
		var at := camera.unproject_position(row.at)
		var color := Color("5aa6c8") if int(row.side) == 0 else Color("c8574f")
		var width := 70.0 * s
		var bar_top := at + Vector2(-width * 0.5, 0)
		overlay.draw_rect(Rect2(bar_top - Vector2(1, 1), Vector2(width + 2, 7 * s)), Color(0.05, 0.06, 0.06, 0.8))
		overlay.draw_rect(Rect2(bar_top, Vector2(width * clampf(hero_health / float(ELAutochessRules.START_HEALTH), 0.0, 1.0), 5 * s)), color)
		H.centered(overlay, font, "♥ %d" % hero_health, at + Vector2(0, -6 * s), roundi(16 * s), Color("eef2f2"), 4)
		H.centered(overlay, font, _name_of(player), at + Vector2(0, -28 * s), roundi(14 * s), Color("ffe3a1"), 4)
	for number: Array in board.floating_numbers():
		if camera.is_position_behind(number[0]): continue
		var at := camera.unproject_position(number[0])
		var tint: Color = number[2]
		tint.a = float(number[3])
		var size := roundi(20 * s)
		overlay.draw_string_outline(font, at + Vector2(-40, 0) * s, String(number[1]), HORIZONTAL_ALIGNMENT_CENTER, 80 * s, size, 5, Color(0, 0, 0, tint.a))
		overlay.draw_string(font, at + Vector2(-40, 0) * s, String(number[1]), HORIZONTAL_ALIGNMENT_CENTER, 80 * s, size, tint)

## Rows with their head marks' screen points ("screen"), the nearer
## figures' first; a mark that would cover another is lifted above it.
func _placed(rows: Array, s: float) -> Array:
	var result := []
	for row: Dictionary in rows:
		if camera.is_position_behind(row.at): continue
		row.screen = camera.unproject_position(row.at)
		result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.screen.y > b.screen.y)
	var taken: Array[Rect2] = []
	var size := Vector2(58, 42) * s
	var anchor := Vector2(29, 38) * s
	# Beside the figure first, then above it: a mark stays close to its owner.
	var moves := [Vector2.ZERO, Vector2(-0.55, 0), Vector2(0.55, 0), Vector2(0, -1), Vector2(-0.55, -1), Vector2(0.55, -1)]
	for row: Dictionary in result:
		var at: Vector2 = row.screen
		var chosen := Rect2(at - anchor, size)
		for move: Vector2 in moves:
			var mark := Rect2(at - anchor + move * size, size)
			var free := true
			for other: Rect2 in taken:
				if mark.intersects(other):
					free = false
					break
			if free:
				chosen = mark
				break
		row.screen = chosen.position + anchor
		taken.append(chosen)
	return result

func _draw_head(font: Font, at: Vector2, rank: int, star_color: Color, text: String, share: float, bar: Color, s: float, shield := 0.0) -> void:
	var width := 46.0 * s
	var bar_top := at + Vector2(-width * 0.5, 0)
	overlay.draw_rect(Rect2(bar_top - Vector2(1, 1), Vector2(width + 2, 6 * s)), Color(0.05, 0.06, 0.06, 0.8))
	overlay.draw_rect(Rect2(bar_top, Vector2(width * clampf(share, 0.0, 1.0), 4 * s)), bar)
	if shield > 0.0: overlay.draw_rect(Rect2(bar_top - Vector2(0, 2 * s), Vector2(width * clampf(shield, 0.0, 1.0), 2 * s)), Color(0.9, 0.93, 1.0))
	H.centered(overlay, font, text, at + Vector2(0, -5 * s), roundi(15 * s), Color("eef2f2"), 4)
	var count := clampi(rank + 1, 1, 3)
	H.draw_stars(overlay, at + Vector2(-count * 7.0 * s - 6 * s, -38 * s), count, star_color, s)

## The carried artifact or spell: its icon in a small ring right of the bar.
## `pop` (1 down to 0) flashes it as just used: the ring swells and glows
## and a larger copy of the icon rises from it and fades.
func _draw_item(at: Vector2, kind: String, s: float, pop := 0.0) -> void:
	if kind.is_empty(): return
	var center := at + Vector2(23 * s + 13 * s, -2 * s)
	var radius := 12.0 * s
	var accent := H.cost_accent(ELAutochessArtifacts.tier(kind))
	var icon := ELAutochessArtifacts.icon(profile, kind)
	var swell := 1.0 + 0.35 * sin(clampf(pop, 0.0, 1.0) * PI) if pop > 0.0 else 1.0
	if pop > 0.0:
		var age := 1.0 - pop
		overlay.draw_circle(center, radius * (1.2 + age * 1.3), Color(accent, 0.35 * pop))
		overlay.draw_arc(center, radius * (1.1 + age * 1.8), 0, TAU, 32, Color(accent, pop), 2.5 * s, true)
	var r := radius * swell
	overlay.draw_circle(center, r + 1.5 * s, Color(0.03, 0.04, 0.05, 0.9))
	if icon != null: overlay.draw_texture_rect(icon, Rect2(center - Vector2.ONE * r * 0.78, Vector2.ONE * r * 1.56), false)
	overlay.draw_arc(center, r, 0, TAU, 24, accent.lightened(0.5 * pop), 2.0 * s, true)
	if pop > 0.0 and icon != null:
		var age := 1.0 - pop
		var size := 34.0 * s
		var rise := at + Vector2(0, -58 * s - age * 34 * s)
		var alpha := clampf(pop * 1.6, 0.0, 1.0)
		overlay.draw_circle(rise, size * 0.62, Color(0.03, 0.04, 0.05, 0.75 * alpha))
		overlay.draw_texture_rect(icon, Rect2(rise - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, Color(1, 1, 1, alpha))
		overlay.draw_arc(rise, size * 0.62, 0, TAU, 32, Color(accent, alpha), 2.0 * s, true)

## Corner brackets around a figure's outline on screen, `grow` pixels out.
func _draw_frame(outline: Rect2, grow: float, color: Color, s: float) -> void:
	if outline.size == Vector2.ZERO: return
	var box := outline.grow(8.0 * s + grow)
	# A square at least as wide as the figure is tall reads as a frame.
	var side := maxf(box.size.x, box.size.y * 0.8)
	box = Rect2(Vector2(box.get_center().x - side * 0.5, box.position.y), Vector2(side, box.size.y))
	var length := minf(box.size.x, box.size.y) * 0.24
	var width := maxf(2.0, 2.5 * s)
	var shadow := Color(0, 0, 0, color.a * 0.55)
	for pass_color: Color in [shadow, color]:
		var offset := Vector2(1, 1) * s if pass_color == shadow else Vector2.ZERO
		for corner: Vector2 in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
			var inward := Vector2(-signf(corner.x - box.get_center().x), -signf(corner.y - box.get_center().y))
			var points := PackedVector2Array([corner + offset + Vector2(inward.x * length, 0), corner + offset, corner + offset + Vector2(0, inward.y * length)])
			overlay.draw_polyline(points, pass_color, width + (1.5 * s if pass_color == shadow else 0.0), true)

## Corners that open out around a creature that just evolved.
func _draw_pulse(outline: Rect2, remaining: float, s: float) -> void:
	var color := Color(H.GOLD, minf(1.0, remaining))
	_draw_frame(outline, (PULSE_SECONDS - remaining) * 14.0 * s, color, s)

func _toggle_overview() -> void:
	_overview.visible = not _overview.visible

func _overview_cells() -> Array[Rect2]:
	var cells: Array[Rect2] = []
	var side := minf(hud.size.x - 200, hud.size.y - 120) / 3.0
	var origin := (hud.size - Vector2(side * 3, side * 3)) * 0.5 + Vector2(0, 20)
	for player in ELAutochessRules.PLAYER_COUNT:
		cells.append(Rect2(origin + Vector2(player % 3, player / 3) * side, Vector2(side, side)).grow(-6))
	return cells

func _draw_overview() -> void:
	_overview.draw_rect(Rect2(Vector2.ZERO, _overview.size), Color(0.08, 0.09, 0.08, 0.86))
	var font := get_theme_default_font()
	var cells := _overview_cells()
	for player in cells.size():
		var cell := cells[player]
		_overview.draw_rect(cell, Color(0.62, 0.86, 1.0, 0.9) if player == watched else Color(1, 1, 1, 0.08), false, 1.0)
		var portrait := ELAutochessCharacters.portrait(profile, game.companies[player].character)
		if portrait != null: _overview.draw_texture_rect(portrait, Rect2(cell.position + Vector2(8, 8), Vector2(40, 32)), false, Color(1, 1, 1, 0.9))
		var scale := cell.size.x / ELAutochessRules.FIELD.size.x
		var center := cell.get_center() - Vector2(0, 12)
		var info := game.board_of(player)
		if game.stage == "fight" and not info.is_empty():
			var battle: ELAutochessBattle = game.boards[int(info.index)].battle
			var flip := int(info.team) == 1
			for u: ELAutochessBattle.Fighter in battle.units:
				if u.dead: continue
				var p := -u.pos if flip else u.pos
				_overview.draw_arc(center + p * scale * 0.85, 4.0, 0, TAU, 12, Color("6fd0ff") if (u.team == 1) == flip else Color("ef6b5b"), 1.6, true)
		else:
			for entry: Dictionary in game.companies[player].army:
				if entry.deployed: _overview.draw_arc(center + Vector2(float(entry.point[0]), float(entry.point[1])) * scale * 0.85, 4.0, 0, TAU, 12, Color("6fd0ff"), 1.6, true)
		var hp := game.companies[player].health
		H.centered(_overview, font, _name_of(player), Vector2(cell.get_center().x, cell.end.y - 26), 15, H.GOLD, 3)
		H.centered(_overview, font, str(hp) if hp > 0 else "#%d" % game.placements[player], Vector2(cell.get_center().x, cell.end.y - 8), 15, H.GOLD, 3)

func _overview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cells := _overview_cells()
		for player in cells.size():
			if cells[player].has_point(event.position):
				_watch(player)
				return

func _leave() -> void:
	if online != null: online.close()
	elif game.stage != "over": game.save()
	game.paused = false
	camera.current = false
	left.emit()

func _concede() -> void:
	if online != null:
		online.send_command("concede", [])
		online.close()
	else: ELAutochessMatch.delete_save()
	game.auto_save = false
	camera.current = false
	left.emit()

func _quit_finished() -> void:
	if online != null: online.close()
	else: ELAutochessMatch.delete_save()
	camera.current = false
	left.emit()
