class_name ELArenaScreen
extends Control
## Arena front end. The run owns all decisions and saves; this screen only
## presents its current phase and emits the player's intent.
signal started(seed: int, rules: int, level: int)
signal hero_chosen(faction: String)
signal card_picked(index: int)
signal battle_requested
signal continued
signal retired
signal resumed
signal save_retried
signal left

const INK := Color("eee6d7")
const MUTED := Color("c5b69c")
const GOLD := Color("dfbc82")
const TEAL := Color("a1c4bc")
const RED := Color("db8f80")
const BACKGROUND := Color("150e0a")
const PANEL := Color("20201e")
const LINE := Color("74654c")
const BACKDROP := preload("res://assets/arena/draft-arena.webp")
const FACTIONS := {
	"Red": ["Chaots", "Хаоты", Color("ce886c")],
	"Green": ["Vitals", "Виталы", Color("a9c48c")],
	"Blue": ["Kinets", "Кинеты", Color("8eb8ce")],
	"Black": ["Synthets", "Синтеты", Color("bbb0cb")],
}
const KINDS := {
	"Creature": ["Creature", "Создание"],
	"Sorcery": ["Sorcery", "Колдовство"],
	"Enchantment": ["Enchantment", "Чары"],
}

var profile: ELProfile
var profile_generation := 0
var run: ELArenaRun
var _kit: ELMenuKit
var _tile_look: ELListLook
var _music: AudioStreamPlayer
var _menu_frame: StyleBox
var _column_style: StyleBox
var _nameplate: StyleBox
var _ether_icon: Texture2D
var _channel_icon: Texture2D
var _symbols: Texture2D
var _heading_font: SystemFont
var _russian := false
var _save_error := ""
var _busy := false
var _margin: MarginContainer
var _layout: VBoxContainer
var _title: Label
var _record: HFlowContainer
var _notice: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _body_grid: GridContainer
var _offer_grid: GridContainer
var _sidebar: Control
var _hub_main: Control
var _landing_panel: PanelContainer
var _seed_field: LineEdit
var _seed_error: Label
var _pool_choice: OptionButton
var _player_level: OptionButton
var _action_buttons: Array[BaseButton] = []
var _modal: ColorRect
var _modal_panel: PanelContainer
var _modal_rows: VBoxContainer
var _modal_scroll: ScrollContainer
var _modal_focus: Control


func build(data: ELProfile) -> void:
	profile = data
	profile_generation = data.generation
	_russian = ELRemakeText.language(profile) == "ru"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_kit = ELMenuKit.for_profile(profile)
	_tile_look = ELListLook.load(profile)
	var look := _kit.theme()
	if look == null: look = Theme.new()
	else:
		_menu_frame = _kit.panel_style("frame", Vector4(27, 23, 27, 27))
		_column_style = _kit.panel_style("box", Vector4(13, 12, 13, 12))
		_nameplate = look.get_stylebox("tab_selected", "TabContainer")
	var hud := profile.texture("Interface/black/combat_panel_1")
	_ether_icon = _atlas(hud, Rect2(31, 192, 20, 20))
	_channel_icon = _atlas(hud, Rect2(55, 192, 20, 20))
	_symbols = profile.texture("Interface/combatsymbols")
	var body_font := SystemFont.new()
	body_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	body_font.multichannel_signed_distance_field = true
	look.default_font = body_font
	look.default_font_size = 18
	look.set_color("font_color", "Label", INK)
	look.set_color("font_color", "Button", INK)
	look.set_color("font_focus_color", "Button", INK)
	look.set_color("font_color", "LineEdit", INK)
	look.set_color("font_placeholder_color", "LineEdit", MUTED)
	if not look.has_stylebox("normal", "LineEdit"):
		look.set_stylebox("normal", "LineEdit", _plate(Color("1b120d"), LINE, 12))
		look.set_stylebox("focus", "LineEdit", _plate(Color("1b120d"), GOLD, 12))
	theme = look
	var backdrop := _image(BACKDROP, Vector2.ZERO)
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.035, 0.03, 0.53)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _menu_frame is ELMenuKit.FrameBox:
		var rim := Panel.new()
		var rim_style := _menu_frame.duplicate() as ELMenuKit.FrameBox
		rim_style.fill = null
		rim.add_theme_stylebox_override("panel", rim_style)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rim)
		rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heading_font = body_font.duplicate() as SystemFont
	_heading_font.font_weight = 700
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 15)
	_margin.add_child(_layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	_layout.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)
	_title = _heading(_text("Draft Arena", "Арена драфта"), 42)
	heading.add_child(_title)
	var back := _button(_text("Main menu", "Главное меню"))
	back.name = "ArenaMenu"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): left.emit())
	header.add_child(back)
	_record = HFlowContainer.new()
	_record.add_theme_constant_override("h_separation", 10)
	_record.add_theme_constant_override("v_separation", 8)
	_layout.add_child(_record)
	_notice = _label("", 17, RED)
	_notice.hide()
	_layout.add_child(_notice)
	_scroll = ScrollContainer.new()
	_scroll.name = "ArenaContentScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_layout.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	_scroll.add_child(_content)
	_modal = ColorRect.new()
	_modal.name = "ArenaDetails"
	_modal.color = Color(0.025, 0.035, 0.04, 0.91)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.hide()
	_music = AudioStreamPlayer.new()
	_music.name = "ArenaMusic"
	add_child(_music)
	visibility_changed.connect(_sync_music)
	apply_volumes({})
	_sync_music()
	resized.connect(_relayout)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	show_run(null)


func uses_current_language() -> bool:
	return _russian == (ELRemakeText.language(profile) == "ru")


func apply_volumes(values: Dictionary) -> void:
	_music.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(float(values.get("music", 0.8)), profile.id))) - 6.0


func _sync_music() -> void:
	if not is_visible_in_tree():
		_music.stop()
		return
	if _music.playing: return
	if _music.stream == null:
		var path := profile.file("Resources/Music/interface.mp3")
		if path.is_empty(): return
		var track := AudioStreamMP3.load_from_file(path)
		if track == null: return
		track.loop = true
		_music.stream = track
	_music.play()


func show_run(active: ELArenaRun, save_error := "") -> void:
	run = active
	_save_error = save_error
	_busy = false
	_action_buttons.clear()
	_body_grid = null
	_offer_grid = null
	_sidebar = null
	_hub_main = null
	_landing_panel = null
	_seed_field = null
	_seed_error = null
	_pool_choice = null
	_player_level = null
	_close_modal()
	_clear(_content)
	_clear(_record)
	_scroll.scroll_vertical = 0
	_notice.text = _save_error
	_notice.visible = not _save_error.is_empty()
	_record.visible = run != null
	if run != null:
		_record.add_child(_chip(_text("Wins %d / %d", "Победы %d / %d") % [run.wins, ELArenaRules.WIN_LIMIT], GOLD))
		_record.add_child(_chip(_text("Losses %d / %d", "Поражения %d / %d") % [run.losses, ELArenaRules.LOSS_LIMIT], RED))
		_record.add_child(_chip(_pool_text(run.rules_version), MUTED))
		var levels := _text("Level %d", "Уровень %d") % run.hero_levels.x
		if run.hero_levels.x != run.hero_levels.y:
			levels = _text("Levels %d vs %d", "Уровни %d и %d") % [run.hero_levels.x, run.hero_levels.y]
		_record.add_child(_chip(levels, MUTED))
		if run.draws > 0: _record.add_child(_chip(_text("%d draws", "Ничьи: %d") % run.draws, MUTED))
		if not run.faction.is_empty(): _record.add_child(_chip(_faction_name(run.faction), _faction_color(run.faction)))
	if not _save_error.is_empty():
		var retry := _button(_text("Retry saving", "Повторить сохранение"), GOLD)
		retry.name = "ArenaRetrySave"
		retry.pressed.connect(func(): save_retried.emit())
		_content.add_child(retry)
	if run == null: _landing()
	else:
		match run.phase:
			"hero": _hero_choices()
			"draft": _draft()
			_: _hub()
	_relayout.call_deferred()


func message(value: String) -> void:
	_busy = false
	_notice.text = ELRemakeText.t(value, profile)
	_notice.visible = not value.is_empty()
	for button: BaseButton in _action_buttons:
		if is_instance_valid(button): button.disabled = not _save_error.is_empty()


func _landing() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(center)
	_landing_panel = _framed_panel()
	center.add_child(_landing_panel)
	var rows := _rows(_landing_panel, 15)
	rows.add_child(_heading(_text("Start an Arena run", "Начать заход на арену"), 29))
	rows.add_child(_label(_text("Choose a hero, then pick one of three cards sixteen times. Play that deck until twelve wins or three losses.", "Выберите героя, затем 16 раз возьмите одну карту из трёх. Играйте этой колодой до 12 побед или 3 поражений."), 19, MUTED))
	rows.add_child(_label(_text("%d uses per card · Up to %d copies", "%d применения каждой карты · До %d копий") % [ELSpellCharges.providence(ELArenaRules.SKILLS), ELArenaRules.COPY_LIMIT], 16, GOLD))
	_add_pool_choice(rows)
	_add_level_choice(rows)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 10)
	rows.add_child(actions)
	var start := _action(_text("Start a new run", "Начать новый заход"), _request_start, GOLD)
	start.name = "ArenaNewRun"
	actions.add_child(start)
	if ELArenaRun.has_save():
		var resume := _action(_text("Resume saved run", "Продолжить сохранённый заход"), func(): _dispatch(resumed.emit), TEAL)
		resume.name = "ArenaResume"
		actions.add_child(resume)
	var seed_toggle := CheckButton.new()
	seed_toggle.text = _text("Use a specific seed", "Указать сид")
	seed_toggle.add_theme_font_size_override("font_size", 16)
	ELUiSounds.bind(seed_toggle, profile)
	rows.add_child(seed_toggle)
	var seed_rows := VBoxContainer.new()
	seed_rows.hide()
	rows.add_child(seed_rows)
	_seed_field = LineEdit.new()
	_seed_field.name = "ArenaSeed"
	_seed_field.placeholder_text = _text("Number from 0 to 2147483647", "Число от 0 до 2147483647")
	_seed_field.custom_minimum_size.y = 43
	_seed_field.max_length = 10
	_seed_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	seed_rows.add_child(_seed_field)
	_seed_error = _label("", 15, RED)
	_seed_error.hide()
	seed_rows.add_child(_seed_error)
	seed_toggle.toggled.connect(func(enabled: bool):
		seed_rows.visible = enabled
		if not enabled: _seed_field.clear()
		else: _seed_field.grab_focus())
	_seed_field.text_changed.connect(func(_value: String): _seed_error.hide())
	_seed_field.text_submitted.connect(func(_value: String): _request_start())
	rows.add_child(_label(_text("Your progress is saved automatically.", "Прогресс сохраняется автоматически."), 15, MUTED))


func _hero_choices() -> void:
	_content.add_child(_draft_heading(_text("Choose your hero", "Выберите героя")))
	_offer_grid = GridContainer.new()
	_offer_grid.add_theme_constant_override("h_separation", 16)
	_offer_grid.add_theme_constant_override("v_separation", 16)
	_content.add_child(_offer_grid)
	for faction: String in run.hero_choices:
		var color := _faction_color(faction)
		var panel := _panel(LINE)
		var rows := _rows(panel, 10)
		var title := _heading(_faction_name(faction), 25)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(title)
		var stage := _panel(color.darkened(0.45))
		stage.name = "ArenaHeroStage"
		stage.add_theme_stylebox_override("panel", _plate(Color("141413"), color.darkened(0.55), 6))
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(stage)
		var template := ELDuelPresets.default_template(profile, faction)
		var figure := ELAutochessFigure.new()
		figure.name = "ArenaHeroPreview"
		figure.relative = false
		figure.zoom = 0.92
		if DisplayServer.get_name() != "headless": figure.show_hero(profile, template)
		if is_instance_valid(figure.view): stage.add_child(figure)
		else:
			figure.free()
			var face := int(profile.table("HeroTemplates").get(template, {}).get("Face", -1))
			if face >= 0: stage.add_child(_image(profile.portrait(face), Vector2.ZERO))
		var pick := _choice_button("ArenaHero_" + faction, _faction_name(faction), panel, func(): hero_chosen.emit(faction))
		_offer_grid.add_child(pick)


func _draft() -> void:
	var picked := run.draft.cards.size()
	_content.add_child(_draft_heading(_text("PICK %d OF 16", "ВЫБОР %d ИЗ 16") % (picked + 1)))
	var progress := ProgressBar.new()
	progress.max_value = 16
	progress.value = picked
	progress.show_percentage = false
	progress.custom_minimum_size.y = 6
	progress.add_theme_stylebox_override("background", _plate(Color("39291d"), Color.TRANSPARENT, 0))
	progress.add_theme_stylebox_override("fill", _plate(GOLD, Color.TRANSPARENT, 0))
	_content.add_child(progress)
	_content.add_child(_label(_text("Click a card to draft it.", "Нажмите на карту, чтобы взять её в колоду."), 15, MUTED))
	_body_grid = GridContainer.new()
	_body_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_grid.add_theme_constant_override("h_separation", 22)
	_body_grid.add_theme_constant_override("v_separation", 22)
	_content.add_child(_body_grid)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 12)
	_body_grid.add_child(choices)
	_offer_grid = GridContainer.new()
	_offer_grid.add_theme_constant_override("h_separation", 13)
	_offer_grid.add_theme_constant_override("v_separation", 14)
	choices.add_child(_offer_grid)
	for index in run.draft.offer.size():
		var code: String = run.draft.offer[index]
		_offer_grid.add_child(_offer_button(code, index))
	_sidebar = _deck_panel(run.draft.cards)
	_body_grid.add_child(_sidebar)


func _hub() -> void:
	_body_grid = GridContainer.new()
	_body_grid.add_theme_constant_override("h_separation", 22)
	_body_grid.add_theme_constant_override("v_separation", 22)
	_content.add_child(_body_grid)
	var main := VBoxContainer.new()
	_hub_main = main
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	_body_grid.add_child(main)
	var panel := _panel(GOLD)
	main.add_child(panel)
	var rows := _rows(panel, 10)
	var heading := _text("Your deck is ready", "Ваша колода готова")
	var note := ""
	var accent := GOLD
	if run.phase == "battle":
		heading = _text("A duel is in progress", "Дуэль продолжается")
		note = _text("Return to your saved battle whenever you are ready.", "Вернитесь к сохранённому бою, когда будете готовы.")
	elif run.phase in ["result", "finished"]:
		var outcome := str(run.matches.back().get("outcome", "")) if not run.matches.is_empty() else ""
		if outcome == "win":
			heading = _text("Victory", "Победа")
			accent = TEAL
		elif outcome == "loss":
			heading = _text("Defeat", "Поражение")
			accent = RED
		elif outcome == "draw": heading = _text("Draw", "Ничья")
		note = _text("Your deck stays with you. Prepare for the next challenger.", "Колода остаётся с вами. Готовьтесь к следующему сопернику.")
		if outcome == "draw": note = _text("A draw costs no life. Your record is unchanged.", "Ничья не считается поражением. Счёт побед и поражений не изменился.")
	if run.phase == "finished":
		if run.outcome == "victory":
			heading = _text("Arena champion", "Чемпион арены")
			note = _text("Twelve wins complete the run.", "Двенадцать побед. Арена пройдена.")
			accent = GOLD
		elif run.outcome == "retired":
			heading = _text("Run retired", "Заход завершён")
			note = ""
		else:
			heading = _text("Run complete", "Заход окончен")
			note = _text("Three defeats end the run.", "Три поражения завершили заход.")
	var heading_label := _heading(heading, 25)
	heading_label.add_theme_color_override("font_color", accent)
	rows.add_child(heading_label)
	if not note.is_empty(): rows.add_child(_label(note, 18, MUTED))
	if run.phase == "ready":
		var next := _action(_text("Enter the Arena", "Выйти на арену"), func(): _dispatch(battle_requested.emit), GOLD)
		next.name = "ArenaBattle"
		next.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rows.add_child(next)
	elif run.phase == "battle":
		var resume := _action(_text("Resume battle", "Продолжить бой"), func(): _dispatch(battle_requested.emit), GOLD)
		resume.name = "ArenaBattle"
		resume.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rows.add_child(resume)
	elif run.phase == "result":
		var next := _action(_text("Continue run", "Продолжить заход"), func(): _dispatch(continued.emit), GOLD)
		next.name = "ArenaContinue"
		next.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rows.add_child(next)
	elif run.phase == "finished":
		_add_pool_choice(rows)
		_add_level_choice(rows)
		var start := _action(_text("Draft a new deck", "Собрать новую колоду"), _request_start, GOLD)
		start.name = "ArenaNewRun"
		start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rows.add_child(start)
	if not run.matches.is_empty(): _match_history(main)
	var secondary := HFlowContainer.new()
	secondary.add_theme_constant_override("h_separation", 12)
	secondary.add_theme_constant_override("v_separation", 10)
	main.add_child(secondary)
	if run.draft != null:
		var log := _button(_text("Your draft history", "История вашего драфта"))
		log.name = "ArenaPlayerDraft"
		log.pressed.connect(func(): _show_draft_log(_text("Your draft", "Ваш драфт"), run.draft.history))
		secondary.add_child(log)
	if run.phase != "finished":
		var retire := _action(_text("Retire this run", "Завершить заход"), _request_retire, MUTED)
		retire.name = "ArenaRetire"
		secondary.add_child(retire)
	main.add_child(_label(_text("Run seed: %d", "Сид захода: %d") % run.seed_value, 14, MUTED))
	_sidebar = _deck_panel(run.draft.cards if run.draft != null else [], 8)
	_body_grid.add_child(_sidebar)


func _match_history(parent: Control) -> void:
	parent.add_child(_label(_text("This run", "Этот заход"), 22, INK))
	for i in range(run.matches.size() - 1, -1, -1):
		var result: Dictionary = run.matches[i]
		var opponent: Dictionary = result.get("opponent", {})
		var outcome := str(result.get("outcome", ""))
		var result_name := _text("Win", "Победа") if outcome == "win" else (_text("Loss", "Поражение") if outcome == "loss" else _text("Draw", "Ничья"))
		var name := _opponent_name(opponent)
		var label := "%d.  %s  ·  %s" % [i + 1, result_name, name]
		var button := _button(label, TEAL if outcome == "win" else (RED if outcome == "loss" else MUTED))
		button.name = "ArenaOpponent%d" % i
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = _text("Inspect the opponent's deck and all sixteen draft choices", "Посмотреть колоду соперника и все 16 выборов драфта")
		button.pressed.connect(func(): _show_opponent(result))
		parent.add_child(button)


func _card_panel(code: String, choice := -1) -> PanelContainer:
	var spell: Dictionary = profile.table("CombatSpells").get(code, {})
	var color := _faction_color(str(spell.get("Color", "White")))
	var panel := _panel(color.darkened(0.15))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := _rows(panel, 10)
	rows.name = "ArenaCardRows"
	var nameplate := PanelContainer.new()
	nameplate.add_theme_stylebox_override("panel", _nameplate if _nameplate != null else _plate(Color("32291e"), LINE, 6))
	rows.add_child(nameplate)
	var title := _label(ELEncyclopaedia.name(profile, code), 19, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nameplate.add_child(title)
	_card_preview(rows, code, color)
	var description := profile.card_description(code)
	if not description.is_empty() and description != code:
		var body := _label(description, 17, INK)
		if choice < 0: rows.add_child(body)
		else:
			var rules_text := ScrollContainer.new()
			rules_text.name = "ArenaOfferRules"
			rules_text.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			rules_text.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			rules_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.add_child(rules_text)
			rules_text.add_child(body)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(spacer)
	if run != null and run.draft != null:
		var copies := run.draft.cards.count(code)
		if copies > 0: rows.add_child(_label(_text("Already drafted: %d", "Уже взято: %d") % copies, 15, MUTED))
	return panel


func _offer_button(code: String, choice: int) -> Button:
	return _choice_button("ArenaPick%d" % choice, ELEncyclopaedia.name(profile, code), _card_panel(code, choice), func(): card_picked.emit(choice))


func _choice_button(key: String, caption: String, card: PanelContainer, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.accessibility_name = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = _busy or not _save_error.is_empty()
	for style: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.minimum_size_changed.connect(func(): button.custom_minimum_size = card.get_combined_minimum_size())
	button.custom_minimum_size = card.get_combined_minimum_size()
	for child: Control in card.find_children("*", "Control", true, false):
		if child is ScrollBar: continue
		child.mouse_filter = Control.MOUSE_FILTER_PASS if child is ScrollContainer or not child.tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
	_add_outline(button)
	ELUiSounds.bind(button, profile)
	button.pressed.connect(func(): _dispatch(action))
	_action_buttons.append(button)
	return button


func _add_outline(button: BaseButton, selected := false) -> void:
	var outline := Panel.new()
	outline.name = "CardOutline"
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := _plate(Color.TRANSPARENT, GOLD if not selected else TEAL, 0)
	border.set_border_width_all(2)
	outline.add_theme_stylebox_override("panel", border)
	button.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var refresh := func(): outline.visible = selected or (not button.disabled and (button.is_hovered() or button.has_focus()))
	for event: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		button.connect(event, refresh)
	outline.visible = selected


func _card_preview(parent: VBoxContainer, code: String, color: Color) -> void:
	var stage := PanelContainer.new()
	stage.name = "ArenaCardStage"
	stage.custom_minimum_size.y = 204
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := _plate(Color("141413"), color.darkened(0.60), 4)
	stage.add_theme_stylebox_override("panel", surface)
	parent.add_child(stage)
	var tray := Control.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(tray)
	var creature: Dictionary = profile.table("CombatCreatures").get(code, {})
	var traits := ELEncyclopaedia.ability_icons(profile, code)
	if creature.get("Race") == "OutSpellJammer": traits.append(20)
	var preview: Control
	if DisplayServer.get_name() != "headless" and not creature.is_empty():
		var figure := ELAutochessFigure.new()
		figure.name = "ArenaCreaturePreview"
		figure.relative = false
		figure.zoom = 0.92
		tray.add_child(figure)
		figure.show_code(profile, code)
		if is_instance_valid(figure.view): preview = figure
		else:
			tray.remove_child(figure)
			figure.queue_free()
	if preview == null:
		preview = _image(profile.card_icon(code), Vector2.ZERO)
		tray.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_top = 12 if not creature.is_empty() else 42
	preview.offset_bottom = -8 if creature.is_empty() else (-31 if traits.is_empty() else -50)
	preview.offset_left = 8
	preview.offset_right = -8

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 5
	top.offset_right = -5
	top.offset_top = 5
	top.add_child(_value_badge(_ether_icon, _card_cost(code), _text("Ether cost", "Цена в эфире"), GOLD))
	var channels := int(ELCatalog.rule(profile, code).get("channels_el2", 0))
	if channels > 0:
		top.add_child(_value_badge(_channel_icon, str(channels), _text("Ether channels sacrificed", "Расход каналов эфира"), RED))
	var kind_text := _card_kind(code)
	var faction := str(profile.table("CombatSpells").get(code, {}).get("Color", "White"))
	if run != null and run.rules_version == ELArenaRules.OPEN_RULES:
		kind_text = "%s\n%s" % [kind_text, _faction_name(faction)]
	var kind := _label(kind_text, 14, color)
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(kind)

	if not creature.is_empty():
		var readout := VBoxContainer.new()
		readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		readout.add_theme_constant_override("separation", 0)
		tray.add_child(readout)
		readout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		readout.grow_vertical = Control.GROW_DIRECTION_BEGIN
		readout.offset_bottom = -4
		_creature_readout(readout, code, creature, traits)


func _creature_readout(parent: VBoxContainer, code: String, creature: Dictionary, traits: Array[int]) -> void:
	var stats := HBoxContainer.new()
	stats.name = "ArenaCreatureStats"
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	stats.add_theme_constant_override("separation", 0)
	var strength := ELEncyclopaedia.strength(profile, code)
	stats.tooltip_text = _text("Power / toughness", "Сила / выносливость") + "  " + strength
	parent.add_child(stats)
	var power := int(creature.get("Power", -1))
	var toughness := int(creature.get("Toughness", -1))
	if _symbols == null or mini(power, toughness) < 0:
		stats.add_child(_label(strength, 20))
	else:
		for glyph: Array in ELCombatSymbols.number_row(power, toughness, false, false):
			stats.add_child(_image(_atlas(_symbols, ELCombatSymbols.cell_rect(int(glyph[0]))), Vector2(21, 21)))
	if _symbols == null or traits.is_empty(): return
	var icons := HFlowContainer.new()
	icons.name = "ArenaCreatureTraits"
	icons.alignment = FlowContainer.ALIGNMENT_CENTER
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.add_theme_constant_override("h_separation", 2)
	parent.add_child(icons)
	for bit: int in traits:
		var cell: int = ELCombatSymbols.ICON_CODES[bit]
		var icon := _image(_atlas(_symbols, ELCombatSymbols.cell_rect(cell)), Vector2(18, 18))
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		var title := profile.text("T_CREATURE_ICON_%02dC" % (bit + 1))
		var detail := profile.text("T_CREATURE_ICON_%02d" % (bit + 1))
		icon.tooltip_text = (title + "\n" + detail).strip_edges()
		icons.add_child(icon)


func _value_badge(icon: Texture2D, value: String, caption: String, ink: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.tooltip_text = "%s  •  %s" % [caption, value]
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _plate(Color("1d1d1bf5"), LINE, 4))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	if icon != null:
		row.add_child(_image(icon, Vector2(20, 19)))
	else: row.add_child(_label(caption, 13, MUTED))
	var number := _heading(value, 19)
	number.add_theme_color_override("font_color", ink)
	number.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(number)
	return panel


func _atlas(sheet: Texture2D, region: Rect2) -> Texture2D:
	if sheet == null: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _deck_panel(cards: Array, tiles_per_row := 0) -> PanelContainer:
	var panel := _panel(LINE)
	panel.name = "ArenaDeck"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var rows := _rows(panel, 9)
	rows.add_child(_label(_text("YOUR DECK  %d / 16", "ВАША КОЛОДА  %d / 16") % cards.size(), 20, GOLD))
	_cost_curve(rows, cards)
	rows.add_child(_label(_text("Select a card to inspect it.", "Нажмите на карту, чтобы прочитать её."), 14, MUTED))
	if cards.is_empty():
		rows.add_child(_label(_text("Your first choice starts the deck.", "Первый выбор положит начало колоде."), 17, MUTED))
	else: _add_deck_tiles(rows, cards, tiles_per_row)
	return panel


func _add_deck_tiles(parent: Control, cards: Array, tiles_per_row: int) -> void:
	var counts := {}
	for code: String in cards: counts[code] = int(counts.get(code, 0)) + 1
	var sorted: Array = counts.keys()
	sorted.sort_custom(func(a: String, b: String):
		var left := ELEncyclopaedia.cost(profile, a)
		var right := ELEncyclopaedia.cost(profile, b)
		return left < right if left != right else ELEncyclopaedia.name(profile, a) < ELEncyclopaedia.name(profile, b))
	var grid := _rows(parent, 6)
	grid.name = "ArenaDeckTiles"
	var tiles := _tile_grid(grid)
	for index in sorted.size():
		if tiles_per_row > 0 and index > 0 and index % tiles_per_row == 0:
			tiles = _tile_grid(grid)
		var code: String = sorted[index]
		tiles.add_child(_card_tile(code, int(counts[code])))


func _tile_grid(parent: Control) -> HFlowContainer:
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", 6)
	tiles.add_theme_constant_override("v_separation", 6)
	parent.add_child(tiles)
	return tiles


func _cost_curve(parent: Control, cards: Array) -> void:
	var curve: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for code: String in cards:
		var cost := maxi(0, ELEncyclopaedia.cost(profile, code))
		curve[7 if bool(ELCatalog.rule(profile, code).get("variable", false)) else mini(6, cost)] += 1
		total += cost
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 5)
	columns.custom_minimum_size.y = 86
	parent.add_child(columns)
	var highest := maxi(1, int(curve.max()))
	for cost in curve.size():
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 3)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(slot)
		var count := _label(str(curve[cost]), 13, MUTED)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(count)
		var holder := Control.new()
		holder.custom_minimum_size.y = 37
		slot.add_child(holder)
		var bar := ColorRect.new()
		bar.color = TEAL.darkened(0.18) if curve[cost] > 0 else LINE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.anchor_top = 1.0 - maxf(0.06, float(curve[cost]) / highest)
		var label := _label("X" if cost == 7 else ("6+" if cost == 6 else str(cost)), 14, INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(label)
	parent.add_child(_label(_text("Base ether cost  ·  Average %.1f", "Базовая цена  ·  В среднем %.1f") % (float(total) / maxi(1, cards.size())), 14, MUTED))


func _card_tile(code: String, count: int, selected := false) -> TextureButton:
	var button := TextureButton.new()
	button.name = "ArenaTile_" + code
	button.ignore_texture_size = true
	button.custom_minimum_size = Vector2.ONE * ELListLook.ITEM_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var icon := profile.card_icon(code)
	button.texture_normal = icon if icon != null else _tile_look.frame
	var title := ELEncyclopaedia.name(profile, code)
	var copies := " ×%d" % count if count > 1 else ""
	var picked := _text("Picked · ", "Выбрано · ") if selected else ""
	button.accessibility_name = picked + title + copies
	button.tooltip_text = "%s%s\n%s %s\n%s" % [picked, title + copies, _text("Ether cost", "Цена в эфире"), _card_cost(code), profile.card_description(code)]
	if button.texture_normal == null:
		var initials := _label(code, 13, GOLD)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(initials)
		initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile_look.dress(button)
	if count > 1:
		var number := _heading(copies.strip_edges(), 14)
		number.autowrap_mode = TextServer.AUTOWRAP_OFF
		number.add_theme_constant_override("outline_size", 5)
		number.add_theme_color_override("font_outline_color", Color.BLACK)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(number)
		number.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		number.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		number.grow_vertical = Control.GROW_DIRECTION_BEGIN
		number.offset_right = -4
		number.offset_bottom = -3
	_add_outline(button, selected)
	ELUiSounds.bind(button, profile)
	button.pressed.connect(func(): _show_card(code))
	return button


func _show_card(code: String) -> void:
	_open_modal(ELEncyclopaedia.name(profile, code), 650)
	_modal_rows.add_child(_card_panel(code))


func _show_opponent(result: Dictionary) -> void:
	var opponent: Dictionary = result.get("opponent", {})
	_open_modal(_opponent_name(opponent), 535, 500)
	_modal_rows.add_child(_label(_text("Drafted by the same rules: 16 picks, one card from each offer.", "Те же правила драфта: 16 выборов, по одной карте из каждого предложения."), 18, MUTED))
	var cards: Array = opponent.get("cards", [])
	_cost_curve(_modal_rows, cards)
	var history: Array = Dictionary(opponent.get("draft", {})).get("history", [])
	var log := _button(_text("Draft history", "История драфта"), GOLD)
	log.name = "ArenaOpponentDraft"
	log.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	log.pressed.connect(func(): _show_draft_log(_opponent_name(opponent), history))
	_modal_rows.add_child(log)
	_add_deck_tiles(_modal_rows, cards, 8)


func _show_draft_log(title: String, history: Array) -> void:
	_open_modal(title + _text(" · Draft history", " · История драфта"), 1050)
	_modal_rows.add_child(_label(_text("The selected card is highlighted. Each row is one pick.", "Выбранная карта выделена. Каждая строка — один выбор."), 17, MUTED))
	if history.is_empty():
		_modal_rows.add_child(_label(_text("No choices recorded yet.", "Выборов ещё нет."), 18, MUTED))
	for pick in history.size():
		var record: Dictionary = history[pick]
		var panel := _panel(LINE)
		_modal_rows.add_child(panel)
		var rows := _rows(panel, 8)
		rows.add_child(_label(_text("PICK %d", "ВЫБОР %d") % (pick + 1), 15, MUTED))
		var tiles := _tile_grid(rows)
		for index in Array(record.get("offer", [])).size():
			var code := str(record.offer[index])
			var selected := index == int(record.get("choice", -1))
			tiles.add_child(_card_tile(code, 1, selected))


func _add_pool_choice(rows: VBoxContainer) -> void:
	rows.add_child(_label(_text("Card pool", "Пул карт"), 16, GOLD))
	_pool_choice = OptionButton.new()
	_pool_choice.name = "ArenaPool"
	_pool_choice.custom_minimum_size.y = 38
	_pool_choice.add_item(_pool_text(ELArenaRules.OPEN_RULES), ELArenaRules.OPEN_RULES)
	_pool_choice.add_item(_pool_text(ELArenaRules.FACTION_RULES), ELArenaRules.FACTION_RULES)
	_pool_choice.select(1 if run != null and run.rules_version != ELArenaRules.OPEN_RULES else 0)
	rows.add_child(_pool_choice)


func _pool_text(rules: int) -> String:
	if rules == ELArenaRules.FACTION_RULES: return _text("Hero’s faction only", "Только фракция героя")
	if rules == ELArenaRules.LEGACY_RULES: return _text("Hero’s faction + neutral", "Фракция героя и нейтральные")
	return _text("Any faction", "Любая фракция")


func _add_level_choice(rows: VBoxContainer) -> void:
	var caption := _text("Hero level (both sides)", "Уровень героев")
	rows.add_child(_label(caption, 16, GOLD))
	_player_level = OptionButton.new()
	_player_level.name = "ArenaPlayerLevel"
	_player_level.accessibility_name = caption
	_player_level.custom_minimum_size.y = 38
	var allowed := ELDuelCosts.hero_levels(profile)
	for level in range(allowed.x, allowed.y + 1): _player_level.add_item(str(level), level)
	var value := run.hero_levels.x if run != null else ELArenaRules.DEFAULT_LEVEL
	_player_level.select(_player_level.get_item_index(value))
	rows.add_child(_player_level)


func _request_start() -> void:
	var seed := -1
	var rules := _pool_choice.get_selected_id()
	var level := _player_level.get_selected_id()
	if _seed_field != null and not _seed_field.text.strip_edges().is_empty():
		var value := _seed_field.text.strip_edges()
		if not value.is_valid_int() or value.to_int() < 0 or value.to_int() > 0x7fffffff:
			_seed_error.text = _text("Enter a whole number from 0 to 2147483647.", "Введите целое число от 0 до 2147483647.")
			_seed_error.show()
			_seed_field.grab_focus()
			return
		seed = value.to_int()
	var start := func(): _dispatch(func(): started.emit(seed, rules, level))
	if ELArenaRun.has_save() and (run == null or run.phase != "finished"):
		_confirm(_text("Start a new run?", "Начать новый заход?"),
			_text("This replaces your saved Arena run. You can resume it instead from the Arena menu.", "Новый заход заменит сохранённый. Вы можете продолжить старый заход в меню арены."),
			_text("Start new run", "Начать заново"), start)
	else: start.call()


func _request_retire() -> void:
	_confirm(_text("Retire this run?", "Завершить этот заход?"),
		_text("Your current record becomes final. Use Main menu if you only want to pause.", "Текущий результат станет окончательным. Чтобы просто сделать паузу, вернитесь в главное меню."),
		_text("Retire run", "Завершить заход"), func(): _dispatch(retired.emit))


func _confirm(title: String, detail: String, caption: String, action: Callable) -> void:
	_open_modal(title, 640)
	_modal_rows.add_child(_label(detail, 19, MUTED))
	var confirm := _button(caption, GOLD)
	confirm.name = "ArenaConfirm"
	confirm.pressed.connect(func():
		_close_modal()
		action.call())
	_modal_rows.add_child(confirm)
	var cancel := _button(_text("Keep this run", "Оставить текущий заход"))
	cancel.pressed.connect(_close_modal)
	_modal_rows.add_child(cancel)
	cancel.grab_focus()


func _open_modal(title: String, width: float, max_height := INF) -> void:
	_modal_focus = get_viewport().gui_get_focus_owner()
	_clear(_modal)
	_modal_panel = _framed_panel()
	_modal_panel.set_meta("preferred_width", width)
	_modal_panel.set_meta("max_height", max_height)
	_modal.add_child(_modal_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_modal_panel.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	var label := _label(title, 25, GOLD)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var caption := _text("Close", "Закрыть")
	var close := _button("×")
	close.name = "ArenaCloseDetails"
	close.accessibility_name = caption
	close.tooltip_text = caption
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kit.icon_button(close, str(_kit.art.get("back", "")), caption)
	close.pressed.connect(_close_modal)
	header.add_child(close)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_scroll.follow_focus = true
	layout.add_child(_modal_scroll)
	_modal_rows = VBoxContainer.new()
	_modal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_rows.add_theme_constant_override("separation", 12)
	_modal_scroll.add_child(_modal_rows)
	_modal.show()
	close.grab_focus()
	_relayout()


func _close_modal() -> void:
	if _modal == null: return
	_modal.hide()
	_clear(_modal)
	_modal_panel = null
	if is_instance_valid(_modal_focus) and _modal_focus.is_inside_tree(): _modal_focus.grab_focus()
	_modal_focus = null


func _fit_viewport() -> void:
	# The battle canvas scales down to a fixed design width. Arena keeps its
	# text and hit targets full size and reflows instead in a smaller window.
	var stretch := get_viewport().get_stretch_transform().get_scale().max(Vector2(0.01, 0.01))
	scale = Vector2.ONE.max(Vector2.ONE / stretch)
	size = get_viewport_rect().size / scale
	_relayout()


func _relayout() -> void:
	if _margin == null: return
	var small := size.x < 800
	var short := size.y < 730
	for edge in ["left", "right"]: _margin.add_theme_constant_override("margin_" + edge, 16 if small else 32)
	for edge in ["top", "bottom"]: _margin.add_theme_constant_override("margin_" + edge, 16 if small or short else 25)
	_title.add_theme_font_size_override("font_size", 27 if small or short else 36)
	_layout.add_theme_constant_override("separation", 9 if short else 15)
	if _landing_panel != null:
		_landing_panel.custom_minimum_size.x = minf(630, maxf(0, size.x - (40 if small else 76)))
	var hub_wide := _hub_main != null and size.x >= 850
	var draft_wide := _hub_main == null and size.x >= 1180
	if _body_grid != null: _body_grid.columns = 2 if hub_wide or draft_wide else 1
	if _hub_main != null:
		_hub_main.custom_minimum_size.x = 360 if hub_wide else 0
		_hub_main.size_flags_horizontal = Control.SIZE_FILL if hub_wide else Control.SIZE_EXPAND_FILL
	if _sidebar != null:
		_sidebar.custom_minimum_size.x = 300 if draft_wide else 0
		_sidebar.size_flags_horizontal = Control.SIZE_FILL if draft_wide else Control.SIZE_EXPAND_FILL
	if _offer_grid != null:
		_offer_grid.columns = 3 if size.x >= 780 else 1
		var compact := short and _offer_grid.columns == 3
		for stage: PanelContainer in _offer_grid.find_children("ArenaHeroStage", "PanelContainer", true, false):
			stage.custom_minimum_size.y = clampf(size.y - 300, 245, 720) if _offer_grid.columns == 3 else clampf(size.y * 0.5, 260, 460)
		for rows: VBoxContainer in _offer_grid.find_children("ArenaCardRows", "VBoxContainer", true, false):
			rows.add_theme_constant_override("separation", 6 if compact else 10)
		for stage: PanelContainer in _offer_grid.find_children("ArenaCardStage", "PanelContainer", true, false):
			stage.custom_minimum_size.y = 139 if compact else 204
		for rules_text: ScrollContainer in _offer_grid.find_children("ArenaOfferRules", "ScrollContainer", true, false):
			rules_text.custom_minimum_size.y = 72 if compact else 0
			rules_text.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if compact else ScrollContainer.SCROLL_MODE_DISABLED
	if _modal.visible and _modal_panel != null:
		var height := minf(float(_modal_panel.get_meta("max_height", INF)), maxf(160, size.y - 48))
		_modal_panel.size = Vector2(minf(float(_modal_panel.get_meta("preferred_width", 800)), size.x - 32), height)
		_modal_panel.position = (size - _modal_panel.size) * 0.5
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo(): return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if _modal.visible: _close_modal()
		else: left.emit()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


func _dispatch(action: Callable) -> void:
	if _busy or not _save_error.is_empty(): return
	_busy = true
	for button: BaseButton in _action_buttons:
		if is_instance_valid(button): button.disabled = true
	action.call()


func _action(caption: String, action: Callable, accent := INK) -> Button:
	var button := _button(caption, accent)
	button.disabled = _busy or not _save_error.is_empty()
	button.pressed.connect(action)
	_action_buttons.append(button)
	return button


func _draft_heading(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := _heading(caption, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var retire := _action(_text("Retire draft", "Отменить драфт"), _request_retire, MUTED)
	retire.name = "ArenaRetire"
	row.add_child(retire)
	return row


func _card_kind(code: String) -> String:
	var kind := str(profile.table("CombatSpells").get(code, {}).get("Class", ""))
	var value: Array = KINDS.get(kind, ["Spell", "Заклинание"])
	return str(value[int(_russian)])


func _card_cost(code: String) -> String:
	var cost := ELEncyclopaedia.cost(profile, code)
	if bool(ELCatalog.rule(profile, code).get("variable", false)):
		return "%d + X" % cost if cost > 0 else "X"
	return str(cost)


func _faction_name(faction: String) -> String:
	var value: Array = FACTIONS.get(faction, ["Neutral", "Нейтральные", GOLD])
	return str(value[int(_russian)])


func _faction_color(faction: String) -> Color:
	var value: Array = FACTIONS.get(faction, ["", "", GOLD])
	return value[2]


func _opponent_name(opponent: Dictionary) -> String:
	var name := str(opponent.get("name", ""))
	return ELRemakeText.t(name, profile) if not name.is_empty() else _faction_name(str(opponent.get("faction", "")))


func _text(en: String, ru: String) -> String:
	return ru if _russian else en


func _label(value: String, points: int, color := INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	return label


func _heading(value: String, points: int) -> Label:
	var label := _label(value, points, GOLD)
	label.add_theme_font_override("font", _heading_font)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _button(caption: String, accent := GOLD) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.35))
	if not theme.has_stylebox("normal", "Button"):
		button.add_theme_stylebox_override("normal", _plate(Color("37271a"), accent.darkened(0.58), 10))
		button.add_theme_stylebox_override("hover", _plate(Color("503b24"), accent, 10))
		button.add_theme_stylebox_override("pressed", _plate(Color("684b2c"), accent, 10))
		button.add_theme_stylebox_override("disabled", _plate(Color("261e17"), LINE.darkened(0.25), 10))
	button.add_theme_stylebox_override("focus", _plate(Color(0, 0, 0, 0), GOLD, 10))
	# Flow and box containers otherwise shrink a wrapping button to one letter.
	button.custom_minimum_size.x = minf(245, theme.default_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 36)
	ELUiSounds.bind(button, profile)
	return button


func _chip(value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plate(Color("2a1d13"), color.darkened(0.55), 8))
	var label := _label(value, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _panel(border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _column_style if _column_style != null else _plate(PANEL, border, 13))
	return panel


func _framed_panel() -> PanelContainer:
	var panel := _panel(LINE)
	if _menu_frame != null: panel.add_theme_stylebox_override("panel", _menu_frame)
	return panel


func _plate(color: Color, border: Color, padding: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _rows(parent: Control, gap: int) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", gap)
	parent.add_child(rows)
	return rows


func _image(texture: Texture2D, minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = minimum
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
