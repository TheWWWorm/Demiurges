class_name ELExpeditionScreen
extends Control
## The map and journal are drawn together so resizing keeps routes on their buttons.
signal started(preset: String, seed: int)
signal resumed
signal node_chosen(id: String)
signal choice_made(id: String)
signal save_retried
signal retried
signal left

const INK := Color("f4e4c5")
const MUTED := Color("c3b297")
const GOLD := Color("d8aa61")
const HIGHLANDS := "res://assets/branding/expedition-highland.png"
const CITADEL := "res://assets/branding/expedition-citadel.png"
const RELIQUARY_ART := "res://assets/branding/expedition-reliquary.png"
const WARDEN_ART := "res://assets/branding/expedition-warden.png"
const RANDOM_SEED := -1
const INVALID_SEED := -2
const ACCENTS := {
	"fight": Color("d0a171"), "elite": Color("f0a26f"), "event": Color("9fbfc8"),
	"rest": Color("a8c59c"), "boss": Color("f1b86d"),
}
const KIND := {
	"fight": ["Battle", "Бой"], "elite": ["Elite", "Элита"], "event": ["Event", "Событие"],
	"rest": ["Camp", "Привал"], "boss": ["Boss", "Босс"],
}
const MARK := {"fight": "◆", "elite": "▲", "event": "?", "rest": "+", "boss": "✦"}
const SPELL_KINDS := {"Creature": ["Creature", "Создание"], "Sorcery": ["Sorcery", "Колдовство"], "Enchantment": ["Enchantment", "Чары"]}
const GUARDIAN_HINTS := {
	"m41 - Worm Queen": ["The queen starts with worms on the field. Draft creatures you can summon early.", "Королева начинает бой с червями на поле. Берите создания, которых можно призвать рано."],
	"m13 - Bee Hive Boss": ["The hive fills the air with bees. Bring fliers or spells that can clear several creatures.", "Улей наполняет воздух пчёлами. Возьмите летающих созданий или заклинания против нескольких целей."],
	"m23 - Mother Tick": ["The mother starts with ticks on the field. Keep cheap spells to answer them.", "Матка начинает бой с клещами на поле. Возьмите недорогие заклинания против них."],
	"m24 - Red Dragon": ["Prepare for flying dragons and spells that take control of creatures.", "Приготовьтесь к летающим драконам и заклинаниям, перехватывающим контроль над созданиями."],
	"m54 - White Lord": ["Stone Skin can absorb weak hits. Bring a way to remove his wards before you attack.", "Каменная кожа может поглотить слабые удары. Подготовьте способ снять защитные чары перед атакой."],
}

var profile: ELProfile
var run: ELExpeditionRun
## The second game's original menu pieces (ELMenuKit): frames, boxes and
## button plates in place of the flat panels; null keeps the flat look.
var _kit: ELMenuKit
## A battle reward on the spell shop's art (with the kit), over everything.
var _board: ELExpeditionBoard
var _russian := false
var _title: Label
var _subtitle: Label
var _vitals: Label
var _art: TextureRect
var _map: Control
var _body: HBoxContainer
var _journal_panel: PanelContainer
var _dialogue: ColorRect
var _scroll: ScrollContainer
var _journal: VBoxContainer
var _deck_button: Button
var _return: Button
var _points: Dictionary = {}
var _nodes: Dictionary = {}
var _available: Array = []
var _route: Array = []
var _display_deck := false
var _scout_act := 0
var _scout_rooms := false
var _scout_room_id := ""
var _journey_open := false
var _retry_confirmation := false
var _save_error := ""
var _replacement := {}
var _starter_preview: PanelContainer

func build(data: ELProfile) -> void:
	profile = data
	_russian = ELRemakeText.language(profile) == "ru"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_kit = ELMenuKit.for_profile(profile)
	var kit_look: Theme = _kit.theme() if _kit != null else null
	if kit_look == null: _kit = null
	var look := Theme.new()
	if kit_look != null: look.merge_with(kit_look)
	look.default_font_size = 20
	look.set_color("font_color", "Label", INK)
	theme = look

	var background := ColorRect.new()
	background.color = Color("14171b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.modulate = Color(0.66, 0.64, 0.61)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 38)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 27)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _panel("frame", _plate(Color("211a16f4"), Color("967449"), 16)))
	layout.add_child(header)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	header.add_child(heading)
	var nameplate := VBoxContainer.new()
	nameplate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(nameplate)
	_title = _label(_text("ETHER EXPEDITION", "ЭФИРНАЯ ЭКСПЕДИЦИЯ"), 39, GOLD)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Liberation Serif", "Noto Serif"])
	_title.add_theme_font_override("font", serif)
	nameplate.add_child(_title)
	_subtitle = _label("", 19, MUTED)
	nameplate.add_child(_subtitle)
	_vitals = _label("", 21, INK)
	# Give the header row a real minimum width for the single-line readout.
	_vitals.autowrap_mode = TextServer.AUTOWRAP_OFF
	_vitals.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(_vitals)
	_deck_button = _button(_text("Deck", "Колода"))
	_deck_button.pressed.connect(func(): _show_deck(not _display_deck))
	heading.add_child(_deck_button)
	_return = _button(_text("Main menu", "Главное меню"))
	_return.pressed.connect(func(): left.emit())
	heading.add_child(_return)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 20)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	_map = Control.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.resized.connect(_place_nodes)
	_map.draw.connect(_draw_routes)
	_body.add_child(_map)
	_journal_panel = PanelContainer.new()
	_journal_panel.custom_minimum_size.x = 370
	_journal_panel.add_theme_stylebox_override("panel", _panel("frame", _plate(Color("201a16f7"), Color("967449"), 18)))
	_body.add_child(_journal_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_journal_panel.add_child(_scroll)
	_journal = VBoxContainer.new()
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal.add_theme_constant_override("separation", 12)
	_scroll.add_child(_journal)
	_dialogue = ColorRect.new()
	_dialogue.name = "EncounterDialogue"
	_dialogue.color = Color(0, 0, 0, 0.64)
	_dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialogue)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogue.hide()
	resized.connect(_layout_dialogue)
	_journal.minimum_size_changed.connect(_layout_dialogue, CONNECT_DEFERRED)

func _choice_pending() -> bool:
	return run != null and run.phase in ["event", "rest", "reward"]

func _layout_dialogue() -> void:
	if not _dialogue.visible: return
	var margins := _journal_panel.get_theme_stylebox("panel").get_minimum_size()
	var height := maxf(260.0, _journal.get_combined_minimum_size().y + margins.y)
	_journal_panel.size = Vector2(minf(700.0, size.x - 48.0), minf(height, size.y - 88.0))
	_journal_panel.position = (size - _journal_panel.size) * 0.5

func show_run(active: ELExpeditionRun, save_error := "") -> void:
	run = active
	_save_error = save_error
	_replacement = {}
	var backdrop := CITADEL if run != null and run.act == 3 and ResourceLoader.exists(CITADEL) else HIGHLANDS
	_art.texture = load(backdrop) if ResourceLoader.exists(backdrop) else null
	_display_deck = false
	_scout_act = 0
	_scout_rooms = false
	_scout_room_id = ""
	_journey_open = false
	_retry_confirmation = false
	var modal := _choice_pending()
	var parent: Control = _dialogue if modal else _body
	if _journal_panel.get_parent() != parent: _journal_panel.reparent(parent, false)
	_dialogue.visible = modal
	_layout_dialogue()
	_deck_button.visible = run != null and _save_error.is_empty() and not modal
	_return.disabled = modal
	_subtitle.text = _text("A deck-building journey through Etherlords II", "Путешествие по миру «Демиургов II»") if run == null else _text("ACT %d OF 3  ·  SEED %d", "АКТ %d ИЗ 3  ·  СИД %d") % [run.act, run.seed_value]
	_vitals.text = "" if run == null else _text("LIFE  %d / %d   ·   %d SPELLS", "ЗДОРОВЬЕ  %d / %d   ·   КАРТЫ %d") % [run.health, run.max_health, run.deck.size()]
	for button: Button in _nodes.values():
		_map.remove_child(button)
		button.queue_free()
	_nodes.clear()
	_route = [] if run == null else run.route()
	_available = [] if run == null or not _save_error.is_empty() else run.available()
	for row: Array in _route:
		for node: Dictionary in row:
			var id: String = node.id
			var kind: String = node.kind
			var caption: Array = KIND.get(kind, [kind, kind])
			var title := str(node.get("title", ""))
			var button := _button("%s   %s" % [MARK.get(kind, "·"), caption[int(_russian)]], ACCENTS.get(kind, GOLD))
			button.custom_minimum_size = Vector2(126, 44)
			button.tooltip_text = title if not title.is_empty() else caption[int(_russian)]
			if kind == "boss": button.tooltip_text = _guardian_brief()
			button.disabled = not id in _available or run.phase != "map"
			if not button.disabled and _kit == null:
				button.add_theme_stylebox_override("normal", _plate(Color("42301eea"), ACCENTS.get(kind, GOLD), 9))
			elif _kit != null:
				# Rooms that can be entered wear the lit plate; the rest dim.
				if button.disabled: button.self_modulate = Color(0.72, 0.72, 0.72)
				else: button.add_theme_stylebox_override("normal", theme.get_stylebox("hover", "Button"))
			button.set_meta("selected_node", id == run.current)
			button.pressed.connect(func(): node_chosen.emit(id))
			_map.add_child(button)
			_nodes[id] = button
	_place_nodes()
	_draw_journal()

## A fresh reward, a camp or an encounter opens on the spell shop's art
## (ELExpeditionBoard); the journal keeps its views (deck, scouting, a
## spell's place after a pending choice) and a failed save.
func _show_board() -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	var journal_view := _display_deck or _scout_act > 0 or _scout_rooms or not _scout_room_id.is_empty() \
		or _journey_open or _retry_confirmation or not _replacement.is_empty()
	if _kit != null and _choice_pending() and not journal_view and _save_error.is_empty():
		_board = ELExpeditionBoard.make(_kit, run, _russian)
	_dialogue.visible = _choice_pending() and _board == null
	_layout_dialogue()
	if _board == null: return
	add_child(_board)
	_board.chosen.connect(func(ids: Array):
		for id: String in ids: choice_made.emit(id))
	_board.aside.connect(func(kind: String):
		if kind == "scout": _show_room_scout(true)
		elif kind == "inspect": _show_room_details(run.current))

func message(text: String) -> void:
	if text.is_empty(): return
	var replacement_error := _journal.get_node_or_null("ReplaceCheckpoint/ReplacementError") as Label
	if replacement_error != null and replacement_error.get_parent().visible:
		replacement_error.text = ELRemakeText.t(text, profile)
		replacement_error.show()
		return
	var alert := _label(ELRemakeText.t(text, profile), 18, Color("f4b18c"))
	_journal.add_child(alert)
	_journal.move_child(alert, 0)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and not ELWikiScreen.is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var cancel := _journal.get_node_or_null("ReplaceCheckpoint/CancelReplacement") as Button
		if cancel != null and cancel.is_visible_in_tree(): cancel.pressed.emit()
		elif _display_deck: _show_deck(false)
		elif _scout_act > 0: _show_scout(0)
		elif not _scout_room_id.is_empty(): _show_room_details("")
		elif _scout_rooms: _show_room_scout(false)
		elif _journey_open: _show_journey(false)
		elif _retry_confirmation: _show_retry(false)
		elif not _replacement.is_empty(): _show_replacement({})
		elif run != null and not run.pending_card.is_empty() and _save_error.is_empty(): choice_made.emit("back")
		elif _choice_pending() and _save_error.is_empty(): return
		else: left.emit()

func _place_nodes() -> void:
	if _map == null: return
	_points.clear()
	for index in _route.size():
		var row: Array = _route[index]
		for column in row.size():
			var node: Dictionary = row[column]
			var id: String = node.id
			var button: Button = _nodes.get(id)
			if button == null: continue
			var center := Vector2(
				_map.size.x * float(column + 1) / float(row.size() + 1),
				_map.size.y * (0.9 - 0.8 * float(index) / maxf(1.0, float(_route.size() - 1))))
			_points[id] = center
			button.size = button.get_combined_minimum_size()
			button.position = center - button.size * 0.5
	_map.queue_redraw()

func _draw_routes() -> void:
	for row: Array in _route:
		for node: Dictionary in row:
			var from: Vector2 = _points.get(node.id, Vector2.ZERO)
			for id: String in node.get("next", []):
				if not _points.has(id): continue
				var destination: Vector2 = _points[id]
				var active: bool = node.id == run.current and (id in _available or id == _scout_room_id)
				var completed: bool = node.id in run.visited and id in run.visited
				var color := GOLD if active or completed else Color("92816ac4")
				_map.draw_line(from, destination, Color("171512"), 6, true)
				_map.draw_dashed_line(from, destination, color, 2.5, 8.0, true, true)
	for id: String in _nodes:
		var inspected := id == _scout_room_id
		if not _points.has(id) or (not inspected and not _nodes[id].get_meta("selected_node")): continue
		var button: Button = _nodes[id]
		_map.draw_rect(Rect2(button.position - Vector2(5, 5), button.size + Vector2(10, 10)), INK if inspected else GOLD, false, 2.0)

func _draw_journal() -> void:
	_fill_journal()
	_show_board()

func _fill_journal() -> void:
	_scroll.scroll_vertical = 0
	if _starter_preview != null:
		_map.remove_child(_starter_preview)
		_starter_preview.queue_free()
		_starter_preview = null
	_scroll.scroll_vertical = 0
	for child: Node in _journal.get_children():
		_journal.remove_child(child)
		child.queue_free()
	if not _save_error.is_empty():
		_journal.add_child(_label(_text("Checkpoint pending", "Сохранение не завершено"), 27, GOLD))
		_journal.add_child(_label(ELRemakeText.t(_save_error, profile), 18, Color("f4b18c")))
		_journal.add_child(_label(_text("Retry to keep your progress. Leaving returns you to the last saved checkpoint.", "Повторите сохранение, чтобы продолжить. Если выйти, игра вернётся к последнему сохранению."), 19, MUTED))
		var retry := _button(_text("Retry save", "Повторить сохранение"), GOLD)
		retry.pressed.connect(func(): save_retried.emit())
		_journal.add_child(retry)
		if _choice_pending():
			var leave := _button(_text("Main menu", "Главное меню"))
			leave.pressed.connect(func(): left.emit())
			_journal.add_child(leave)
		return
	if run == null:
		_journal.add_child(_label(_text("Into the highlands", "В путь по нагорью"), 27, GOLD))
		_journal.add_child(_label(_text(
			"Choose a hero and make for the citadel. Win battles, trade at strange encounters and shape a deck that can survive three acts.",
			"Выберите героя и отправляйтесь к цитадели. Побеждайте в боях, решайте, кому доверять, и соберите колоду, с которой можно пройти три акта."), 19, MUTED))
		if ELExpeditionRun.has_save():
			var resume := _button(_text("Resume expedition", "Продолжить экспедицию"), GOLD)
			resume.pressed.connect(func(): resumed.emit())
			_journal.add_child(resume)
		_journal.add_child(_label(_text("Starting spellbook", "Стартовая книга заклинаний"), 19, GOLD))
		var presets := ELExpeditionRun.starters(profile)
		var selector := OptionButton.new()
		selector.fit_to_longest_item = false
		selector.custom_minimum_size.y = 45
		for preset: Dictionary in presets:
			var id: String = preset.id
			selector.add_item(str(preset.name))
			selector.set_item_metadata(selector.item_count - 1, id)
		if selector.item_count > 0:
			_journal.add_child(selector)
			selector.item_selected.connect(func(index: int): _show_starter(presets[index]))
			_show_starter(presets[selector.selected])
			var start := _button(_text("Begin expedition", "Начать экспедицию"), GOLD)
			start.name = "BeginExpedition"
			var seed_label := _text("Run seed (optional)", "Сид экспедиции (необязательно)")
			_journal.add_child(_label(seed_label, 17, GOLD))
			var seed_field := LineEdit.new()
			seed_field.name = "ExpeditionSeed"
			seed_field.custom_minimum_size.y = 38
			seed_field.placeholder_text = _text("Random route", "Случайный маршрут")
			seed_field.tooltip_text = _text("Enter a seed from 0 to 4294967295 to replay a route.", "Введите сид от 0 до 4294967295, чтобы повторить маршрут.")
			seed_field.accessibility_name = seed_label
			if _kit == null:
				seed_field.add_theme_stylebox_override("normal", _plate(Color("282019"), Color("7f643e"), 8))
				seed_field.add_theme_stylebox_override("focus", _plate(Color.TRANSPARENT, GOLD, 8))
			seed_field.add_theme_color_override("font_color", INK)
			seed_field.add_theme_color_override("font_placeholder_color", MUTED)
			_journal.add_child(seed_field)
			var seed_error := _label(_text("Enter a whole number from 0 to 4294967295.", "Введите целое число от 0 до 4294967295."), 16, Color("f4b18c"))
			seed_error.hide()
			_journal.add_child(seed_error)
			seed_field.text_changed.connect(func(value: String):
				var invalid := _read_seed(value) == INVALID_SEED
				seed_error.visible = invalid
				start.disabled = invalid)
			seed_field.text_submitted.connect(func(_value: String):
				if start.is_visible_in_tree() and not start.disabled: start.pressed.emit())
			_journal.add_child(start)
			_attach_replacement_prompt(selector, seed_field, start)
		return
	_deck_button.text = _text("Route", "Маршрут") if _display_deck else _text("Deck", "Колода")
	if _display_deck:
		if _choice_pending():
			var back := _button(_text("Back to choices", "К выбору"))
			back.name = "DeckBack"
			back.pressed.connect(_show_deck.bind(false))
			_journal.add_child(back)
		_journal.add_child(_label(_text("Your spellbook", "Ваша книга заклинаний"), 27, GOLD))
		var copies := {}
		var creatures := 0
		for card: String in run.deck:
			copies[card] = int(copies.get(card, 0)) + 1
			if _spell_class(card) == "Creature": creatures += 1
		_journal.add_child(_label(_text("%d creatures · %.1f average base ether", "Созданий: %d · средняя базовая цена: %.1f") % [creatures, _average_ether()], 17, MUTED))
		if not run.keepsake_artifact.is_empty():
			var title := ELMapPickups.artifact_title(profile, run.keepsake_artifact)
			_journal.add_child(_label(_text("Keepsake · %s", "Реликвия · %s") % title, 19, GOLD))
			_journal.add_child(_label(_text("One charge per duel", "Один заряд на бой"), 17, MUTED))
		var trained := run.trained_skills()
		if not trained.is_empty():
			_journal.add_child(_label(_text("Camp training", "Обучение на привале"), 19, GOLD))
			for code: String in trained:
				var rank: int = trained[code]
				var skill := ELHeroSkills.definition(profile, code, rank)
				var title := profile.text(str(skill.get("Name", code)))
				_journal.add_child(_label(_text("%s · Rank %d", "%s · Ступень %d") % [title, rank + 1], 17, INK))
		for card: String in copies:
			_journal.add_child(_spell_tile(card, "%d ×" % copies[card], false))
		return
	if _scout_act > 0:
		_draw_scout()
		return
	if not _scout_room_id.is_empty():
		_draw_room_details()
		return
	if _scout_rooms:
		_draw_room_scout()
		return
	if _journey_open:
		_draw_journey()
		return
	if _retry_confirmation:
		_draw_retry()
		return
	if not _replacement.is_empty():
		_draw_replacement()
		return
	var heads := {
		"map": [_text("Choose a route", "Выберите маршрут"), _text("Follow a highlighted path. Your life and deck carry into the next room.", "Следуйте по подсвеченному пути. Здоровье и колода переносятся в следующую комнату.")],
		"battle": [_text("The next duel", "Следующий бой"), _text("Enter the room to continue.", "Войдите в комнату, чтобы продолжить.")],
		"reward": [_text("Spoils of battle", "Награда за бой"), _text("Take a spell or leave the spoils behind.", "Возьмите заклинание или оставьте награду.")],
		"event": [_text("An encounter", "Необычная встреча"), _text("Choose how to approach the encounter.", "Решите, как поступить.")],
		"rest": [_text("A moment of respite", "Время передохнуть"), _text("Recover some life or refine your deck.", "Восстановите здоровье или измените колоду.")],
		"lost": [_text("The expedition falls", "Экспедиция пала"), _text("Your journey ended in this battle.", "Ваш поход закончился в этом бою.")],
		"won": [_text("The citadel is yours", "Цитадель ваша"), _text("You have defeated the three guardians.", "Вы победили трёх стражей.")],
	}
	var heading: Array = heads.get(run.phase, heads.map)
	var summary := run.room_summary()
	if not summary.is_empty(): heading = [summary.title, summary.description]
	_journal.add_child(_label(heading[0], 27, GOLD))
	var art_key := str(summary.get("illustration", ""))
	var art: String = {"reliquary": RELIQUARY_ART, "warden": WARDEN_ART}.get(art_key, "")
	if not art.is_empty() and ResourceLoader.exists(art):
		var illustration := TextureRect.new()
		illustration.name = "WardenIllustration" if art_key == "warden" else "ReliquaryIllustration"
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		illustration.custom_minimum_size.y = 130
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		illustration.texture = load(art)
		_journal.add_child(illustration)
	_journal.add_child(_label(heading[1], 19, MUTED))
	if art_key == "warden" and not run.opponent_at(run.current).is_empty():
		var inspect := _button(_text("Inspect opponent", "Посмотреть соперника"), GOLD)
		inspect.name = "InspectWarden"
		inspect.pressed.connect(_show_room_details.bind(run.current))
		_journal.add_child(inspect)
	if run.finished(): _draw_result_actions()
	if not run.borrowed_artifact.is_empty():
		var artifact_title := ELMapPickups.artifact_title(profile, run.borrowed_artifact)
		_journal.add_child(_label(_text("Next duel · %s", "Следующий бой · %s") % artifact_title, 17, GOLD))
	if not run.pending_card.is_empty():
		_journal.add_child(_spell_tile(run.pending_card, _text("INCOMING SPELL", "НОВОЕ ЗАКЛИНАНИЕ"), false))
	_draw_choices()
	if _choice_pending():
		_journal.add_child(HSeparator.new())
		var deck := _button(_text("View spellbook", "Посмотреть книгу"), GOLD)
		deck.name = "EncounterDeck"
		deck.pressed.connect(_show_deck.bind(true))
		_journal.add_child(deck)
	if run.phase == "map":
		_journal.add_child(HSeparator.new())
		_journal.add_child(_label("%s   %s" % [MARK.boss, _guardian_brief()], 17, ACCENTS.boss))
		var scout := _button(_text("Scout guardians", "Разведка стражей"), GOLD)
		scout.name = "ScoutGuardians"
		scout.pressed.connect(_show_scout.bind(run.act))
		_journal.add_child(scout)
	if run.pending_card.is_empty() and not run.upcoming().is_empty():
		var rooms := _button(_text("Scout next rooms", "Разведка комнат"), GOLD)
		rooms.name = "ScoutRooms"
		rooms.pressed.connect(_show_room_scout.bind(true))
		_journal.add_child(rooms)
	if run.phase == "map" or run.finished():
		var journey := _button(_text("Journey log", "Журнал пути"), GOLD)
		journey.name = "JourneyLog"
		journey.pressed.connect(_show_journey.bind(true))
		_journal.add_child(journey)
	if run.phase == "map":
		var legend := [
			["fight", _text("Win a spell reward.", "Победите, чтобы получить заклинание.")],
			["elite", _text("Fight for a wider selection of spells.", "Победите, чтобы получить больше заклинаний на выбор.")],
			["event", _text("Make a choice with lasting effects.", "Примите решение, которое повлияет на весь поход.")],
			["rest", _text("Heal or refine your spellbook.", "Вылечитесь или измените книгу заклинаний.")],
		]
		for row: Array in legend:
			_journal.add_child(_label("%s   %s" % [MARK[row[0]], row[1]], 17, ACCENTS[row[0]]))

func _draw_choices() -> void:
	var listed := {}
	for option: Dictionary in run.choices():
		var id: String = option.id
		var card := str(option.get("card", ""))
		var icon_code := str(option.get("artifact", {}).get("spell", card))
		var caption: String = option.title
		if id.begins_with("replace:") or id.begins_with("remove:"):
			if listed.has(card): continue
			listed[card] = true
			var count := run.deck.count(card)
			if count > 1: caption += "  ×%d" % count
		var button := _button(caption, GOLD if not icon_code.is_empty() else INK)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not icon_code.is_empty():
			button.icon = profile.card_icon(icon_code)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 40)
		var description := str(option.get("description", ""))
		button.tooltip_text = description
		if id.begins_with("replace:") or option.has("incoming"):
			button.name = "Compare_" + id.replace(":", "_")
			button.pressed.connect(_show_replacement.bind(option))
		else:
			button.pressed.connect(func(): choice_made.emit(id))
		button.resized.connect(_size_choice.bind(button))
		_journal.add_child(button)
		if not card.is_empty():
			var stats := _spell_stats(card)
			if id.begins_with("card:"):
				match profile.table("CombatSpells")[card].get("Rarity"):
					"Rare": stats += " · " + _text("Rare", "Редкое")
					"Unique": stats += " · " + _text("Unique", "Уникальное")
			_journal.add_child(_label(stats, 15, GOLD))
		if not description.is_empty(): _journal.add_child(_label(description, 16, MUTED))

func _attach_replacement_prompt(selector: OptionButton, seed_field: LineEdit, start: Button) -> void:
	var prompt := VBoxContainer.new()
	prompt.name = "ReplaceCheckpoint"
	prompt.add_theme_constant_override("separation", 8)
	prompt.hide()
	_journal.add_child(prompt)
	prompt.add_child(_label(_text("Start a new expedition?", "Начать новую экспедицию?"), 22, GOLD))
	prompt.add_child(_label(_text("This replaces your saved expedition.", "Новая экспедиция заменит сохранённую."), 17, MUTED))
	var error_label := _label("", 17, Color("f4b18c"))
	error_label.name = "ReplacementError"
	error_label.hide()
	prompt.add_child(error_label)
	var cancel := _button(_text("Keep saved expedition", "Оставить сохранение"))
	cancel.name = "CancelReplacement"
	prompt.add_child(cancel)
	var confirm := _button(_text("Replace checkpoint", "Заменить сохранение"), Color("f4b18c"))
	confirm.name = "ConfirmReplacement"
	prompt.add_child(confirm)
	start.pressed.connect(func():
		var seed := _read_seed(seed_field.text)
		if seed == INVALID_SEED or not start.is_visible_in_tree(): return
		if not ELExpeditionRun.has_save():
			started.emit(selector.get_selected_metadata(), seed)
			return
		selector.disabled = true
		seed_field.editable = false
		start.hide()
		prompt.show()
		cancel.grab_focus())
	cancel.pressed.connect(func():
		prompt.hide()
		error_label.hide()
		selector.disabled = false
		seed_field.editable = true
		start.show()
		start.grab_focus())
	confirm.pressed.connect(func():
		if prompt.is_visible_in_tree(): started.emit(selector.get_selected_metadata(), _read_seed(seed_field.text)))

func _show_starter(preset: Dictionary) -> void:
	if _starter_preview != null:
		_map.remove_child(_starter_preview)
		_starter_preview.queue_free()
	_starter_preview = PanelContainer.new()
	_starter_preview.add_theme_stylebox_override("panel", _panel("frame", _plate(Color("211a16ed"), Color("967449"), 18)))
	_map.add_child(_starter_preview)
	_starter_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_starter_preview.anchor_bottom = 0.7
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_starter_preview.add_child(content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	content.add_child(heading)
	var hero := ELDuelPresets.default_template(profile, preset.faction)
	var face_index := int(profile.table("HeroTemplates").get(hero, {}).get("Face", -1))
	var face := profile.portrait(face_index) as AtlasTexture if face_index >= 0 else null
	if face != null and face.atlas != null:
		var portrait := TextureRect.new()
		portrait.texture = face
		portrait.custom_minimum_size = Vector2(60, 60)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heading.add_child(portrait)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(summary)
	summary.add_child(_label(preset.name, 27, GOLD))
	var life := ELExpeditionRun._life_cap(profile, preset, 1)
	summary.add_child(_label(_text("%d starting life · Level %d · %d spells", "%d здоровья · Уровень %d · Карт: %d") % [life, preset.level, preset.cards.size()], 17, MUTED))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var copies := {}
	for card: String in preset.cards:
		copies[card] = int(copies.get(card, 0)) + 1
	for card: String in copies:
		grid.add_child(_spell_tile(card, "%d ×" % copies[card], false))

func _show_deck(enabled: bool) -> void:
	_scout_act = 0
	_scout_rooms = false
	_scout_room_id = ""
	_journey_open = false
	_retry_confirmation = false
	_display_deck = enabled
	_map.queue_redraw()
	_draw_journal()
	var back := _journal.get_node_or_null("ReplacementBack") as Button
	if back != null: back.grab_focus()
	elif _choice_pending():
		var control := _journal.get_node_or_null("DeckBack" if enabled else "EncounterDeck") as Button
		if control != null: control.grab_focus()
	else: _deck_button.grab_focus()

func _show_scout(act: int) -> void:
	_scout_act = act
	_draw_journal()
	var control := _journal.get_node_or_null("ScoutGuardians" if act == 0 else "ScoutBack") as Button
	if control != null: control.grab_focus()

func _show_room_scout(enabled: bool) -> void:
	_scout_rooms = enabled
	_scout_room_id = ""
	_draw_journal()
	var control := _journal.get_node_or_null("RoomScoutBack" if enabled else "ScoutRooms") as Button
	if control != null: control.grab_focus()

func _show_room_details(id: String) -> void:
	var previous := _scout_room_id
	_scout_room_id = id
	_map.queue_redraw()
	_draw_journal()
	var focus_name := "InspectRoom_" + previous if _scout_rooms else "LastBattle"
	if run.phase == "event" and previous == run.current: focus_name = "InspectWarden"
	if not id.is_empty(): focus_name = "RoomDetailBack"
	var control := _journal.get_node_or_null(focus_name) as Button
	if control != null: control.grab_focus()

func _show_journey(enabled: bool) -> void:
	_journey_open = enabled
	_draw_journal()
	var control := _journal.get_node_or_null("JourneyBack" if enabled else "JourneyLog") as Button
	if control != null: control.grab_focus()

func _draw_result_actions() -> void:
	var opponent := run.opponent_at(run.current)
	if not opponent.is_empty():
		_journal.add_child(_label(str(opponent.title), 22, GOLD))
		var result := run.final_battle()
		if not result.is_empty():
			var summary := _text("Round %d · Opponent life %d", "Раунд %d · Здоровье соперника %d")
			_journal.add_child(_label(summary % [result.round, result.opponent_life], 17, MUTED))
		var inspect := _button(_text("Inspect last opponent", "Последний соперник"), GOLD)
		inspect.name = "LastBattle"
		inspect.pressed.connect(_show_room_details.bind(run.current))
		_journal.add_child(inspect)
	var retry := _button(_text("Retry this seed", "Повторить сид"), GOLD)
	retry.name = "RetryRoute"
	retry.pressed.connect(_show_retry.bind(true))
	_journal.add_child(retry)

func _show_retry(enabled: bool) -> void:
	_retry_confirmation = enabled
	_draw_journal()
	var button := _journal.get_node_or_null("RetryBack" if enabled else "RetryRoute") as Button
	if button != null: button.grab_focus()

func _draw_retry() -> void:
	_journal.add_child(_label(_text("Retry this seed?", "Повторить сид?"), 27, GOLD))
	var details := _text("Start again with seed %d and the same starting spellbook. This replaces the saved expedition.",
		"Начните заново с сидом %d и той же стартовой книгой. Новый поход заменит сохранённую экспедицию.")
	_journal.add_child(_label(details % run.seed_value, 19, MUTED))
	var back := _button(_text("Back to results", "К итогам"))
	back.name = "RetryBack"
	back.pressed.connect(_show_retry.bind(false))
	_journal.add_child(back)
	var confirm := _button(_text("Begin retry", "Начать заново"), GOLD)
	confirm.name = "RetryConfirm"
	confirm.pressed.connect(func(): retried.emit())
	_journal.add_child(confirm)

func _draw_journey() -> void:
	var back := _button(_text("Back to route", "К маршруту"))
	back.name = "JourneyBack"
	back.pressed.connect(_show_journey.bind(false))
	_journal.add_child(back)
	_journal.add_child(_label(_text("Journey log", "Журнал пути"), 27, GOLD))
	for chapter: Dictionary in run.journey():
		var cleared: bool = chapter.act < run.act or run.phase == "won"
		var heading := _text("Act %d · Cleared", "Акт %d · Пройден") if cleared else _text("Act %d", "Акт %d")
		_journal.add_child(_label(heading % chapter.act, 20, GOLD))
		if not chapter.recorded:
			_journal.add_child(_label(_text("Route details are unavailable for this act.", "Сведения о маршруте этого акта недоступны."), 17, MUTED))
		elif chapter.rooms.is_empty():
			_journal.add_child(_label(_text("No rooms visited yet.", "Комнаты ещё не посещены."), 17, MUTED))
		for room: Dictionary in chapter.rooms:
			var kind: String = room.kind
			var caption := _text("%d. %s · Lane %d", "%d. %s · Путь %d") % [room.floor, KIND[kind][int(_russian)], room.column + 1]
			if chapter.act == run.act and run.phase == "lost" and room == chapter.rooms.back():
				caption += _text(" · Defeat", " · Поражение")
			_journal.add_child(_label("%s   %s" % [MARK[kind], caption], 17, ACCENTS[kind]))

func _draw_room_scout() -> void:
	var can_enter := run.phase == "map"
	var back := _button(_text("Back to route", "К маршруту") if can_enter else _text("Back to choices", "К выбору"))
	back.name = "RoomScoutBack"
	back.pressed.connect(_show_room_scout.bind(false))
	_journal.add_child(back)
	_journal.add_child(_label(_text("Reachable rooms", "Доступные комнаты"), 25, GOLD))
	var hint := _text("Rooms are shown from left to right. Select one to enter.", "Комнаты идут слева направо. Выберите комнату, чтобы войти.")
	if not can_enter:
		hint = _text("These rooms open after you finish your current choice.", "Эти комнаты откроются после того, как вы сделаете текущий выбор.")
	_journal.add_child(_label(hint, 17, MUTED))
	var reachable := run.upcoming()
	for row: Array in _route:
		for room: Dictionary in row:
			var id: String = room.id
			if not id in reachable: continue
			var kind: String = room.kind
			var opponent := run.opponent_at(id)
			var caption := "%d. %s" % [int(room.column) + 1, KIND[kind][int(_russian)]]
			if can_enter:
				var button := _button(caption, ACCENTS[kind])
				button.pressed.connect(func(): node_chosen.emit(id))
				_journal.add_child(button)
			else:
				_journal.add_child(_label(caption, 19, ACCENTS[kind]))
			if not opponent.is_empty():
				var detail := "%s\n%s" % [opponent.title, _text("%d life · Level %d", "%d здоровья · Уровень %d") % [opponent.health, opponent.level]]
				_journal.add_child(_label(detail, 18, INK))
				_nodes[id].tooltip_text = detail
				var inspect := _button(_text("Inspect spellbook", "Посмотреть книгу"), GOLD)
				inspect.name = "InspectRoom_" + id
				inspect.pressed.connect(_show_room_details.bind(id))
				_journal.add_child(inspect)

func _draw_room_details() -> void:
	var id := _scout_room_id
	var caption := _text("Back to rooms", "К списку комнат")
	if run.finished(): caption = _text("Back to results", "К итогам")
	elif run.phase == "event" and id == run.current: caption = _text("Back to encounter", "К событию")
	var back := _button(caption)
	back.name = "RoomDetailBack"
	back.pressed.connect(_show_room_details.bind(""))
	_journal.add_child(back)
	var opponent := run.opponent_at(id)
	_journal.add_child(_label(str(opponent.title), 27, INK))
	_journal.add_child(_label(_text("%d life · Level %d", "%d здоровья · Уровень %d") % [opponent.health, opponent.level], 18, GOLD))
	if run.phase == "map":
		var enter := _button(_text("Enter battle", "Вступить в бой"), GOLD)
		enter.name = "EnterScoutedBattle"
		enter.pressed.connect(func(): node_chosen.emit(id))
		_journal.add_child(enter)
	_draw_opponent_book(opponent, "RoomSpecialization")

func _draw_scout() -> void:
	var back := _button(_text("Back to route", "К маршруту"))
	back.name = "ScoutBack"
	back.pressed.connect(_show_scout.bind(0))
	_journal.add_child(back)
	var final_act := ELExpeditionRun.ACTS
	if run.act < final_act:
		var looking_ahead := _scout_act == final_act
		var switch := _button(_text("Current guardian", "Страж текущего акта") if looking_ahead else _text("Final guardian", "Последний страж"), GOLD)
		switch.pressed.connect(_show_scout.bind(run.act if looking_ahead else final_act))
		_journal.add_child(switch)
	var boss := run.guardian() if _scout_act == run.act else ELExpeditionEncounters.build(profile, "boss", final_act * ELExpeditionRun.FLOORS, 0)
	_journal.add_child(_label(_text("GUARDIAN OF ACT %d", "СТРАЖ АКТА %d") % _scout_act, 15, GOLD))
	if boss.is_empty():
		_journal.add_child(_label(_text("Guardian details are unavailable.", "Сведения о страже недоступны."), 19, MUTED))
		return
	_journal.add_child(_label(str(boss.title), 27, INK))
	_journal.add_child(_label(_text("%d life · Level %d", "%d здоровья · Уровень %d") % [boss.health, boss.level], 18, GOLD))
	var hint: Array = GUARDIAN_HINTS.get(boss.id, [])
	if not hint.is_empty(): _journal.add_child(_label(hint[int(_russian)], 17, MUTED))
	_draw_opponent_book(boss, "GuardianSpecialization")

func _draw_opponent_book(opponent: Dictionary, specialization_control: String) -> void:
	var spec_code: String = opponent.specialization
	var spec: Dictionary = profile.table("HeroesSpecs").get(spec_code, {})
	if spec_code != "NONE" and not spec.is_empty():
		var name_key := str(spec.get("Name", ""))
		var title := profile.text(name_key).strip_edges()
		if not title.is_empty() and title != name_key:
			var details := _button(_text("Specialization · %s", "Специализация · %s") % title, GOLD)
			details.name = specialization_control
			details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			details.tooltip_text = _text("Read about this specialization in the wiki.", "Прочитайте об этой специализации в вики.")
			details.resized.connect(_size_choice.bind(details))
			details.pressed.connect(func():
				var wiki := ELWikiScreen.open(self, "spec-" + spec_code.to_lower(), title)
				wiki.tree_exited.connect(details.grab_focus, CONNECT_ONE_SHOT | CONNECT_DEFERRED))
			_journal.add_child(details)
	var skills: PackedStringArray = []
	for code: String in opponent.skills:
		var rank := int(opponent.skills[code])
		var skill := ELHeroSkills.definition(profile, code, rank)
		var name_key := str(skill.get("Name", ""))
		var title := profile.text(name_key).strip_edges()
		if not title.is_empty() and title != name_key: skills.append(title)
	if not skills.is_empty():
		_journal.add_child(_label(_text("Skills · %s", "Навыки · %s") % ", ".join(skills), 17, MUTED))
	_journal.add_child(HSeparator.new())
	_journal.add_child(_label(_text("Starting spellbook", "Стартовая книга заклинаний"), 19, GOLD))
	var copies := {}
	for card: String in opponent.cards:
		copies[card] = int(copies.get(card, 0)) + 1
	for card: String in copies:
		_journal.add_child(_spell_tile(card, "%d ×" % copies[card], false))

func _show_replacement(option: Dictionary) -> void:
	var return_button := "Compare_" + str(_replacement.get("id", "")).replace(":", "_")
	_replacement = option
	_draw_journal()
	var focus := _journal.get_node_or_null(return_button if option.is_empty() else "ReplacementBack") as Button
	if focus != null: focus.grab_focus()

func _draw_replacement() -> void:
	var old: String = _replacement.card
	var exchange := _replacement.has("incoming")
	var next := str(_replacement.get("incoming", run.pending_card))
	_journal.add_child(_label(_text("Replace a spell", "Замена заклинания"), 27, GOLD))
	if exchange: _journal.add_child(_label(_replacement.description, 17, GOLD))
	_journal.add_child(_label(_text("Replace one copy. Your spellbook stays at %d cards.", "Заменяется одна копия. В книге останется карт: %d.") % run.deck.size(), 17, MUTED))
	var delta := ELEncyclopaedia.cost(profile, next) - ELEncyclopaedia.cost(profile, old)
	_journal.add_child(_label(_text("Average base ether\n%.1f → %.1f", "Средняя базовая цена\n%.1f → %.1f") % [_average_ether(), _average_ether(delta)], 19, GOLD))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	_journal.add_child(columns)
	columns.add_child(_spell_tile(old, _text("OUTGOING", "УБИРАЕМ"), true))
	columns.add_child(_spell_tile(next, _text("INCOMING", "ДОБАВЛЯЕМ"), true))
	var confirm := _button(_text("Confirm replacement", "Подтвердить замену"), GOLD)
	confirm.pressed.connect(func(): choice_made.emit(_replacement.id))
	_journal.add_child(confirm)
	var back := _button(_text("Back to the mirror", "Назад к зеркалу") if exchange else _text("Back to spellbook", "Назад к книге заклинаний"))
	back.name = "ReplacementBack"
	back.pressed.connect(_show_replacement.bind({}))
	_journal.add_child(back)

func _average_ether(delta := 0) -> float:
	var total := delta
	for card: String in run.deck: total += ELEncyclopaedia.cost(profile, card)
	return float(total) / maxi(1, run.deck.size())

func _spell_tile(card: String, tag: String, describe: bool) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.add_theme_stylebox_override("panel", _panel("box", _plate(Color("30251be8"), Color("856645"), 8)))
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 4)
	tile.add_child(contents)
	contents.add_child(_label(tag, 14, GOLD))
	var line := HBoxContainer.new()
	contents.add_child(line)
	var icon := TextureRect.new()
	icon.texture = profile.card_icon(card)
	icon.custom_minimum_size = Vector2(50, 50) if describe else Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(icon)
	var title := _label(ELEncyclopaedia.name(profile, card), 24 if describe else 17, INK)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	contents.add_child(_label(_spell_stats(card), 18 if describe else 15, GOLD))
	var description := profile.card_description(card)
	if not description.is_empty() and description != card:
		if describe: contents.add_child(_label(description, 19, MUTED))
		else: tile.tooltip_text = description
	return tile

func _spell_class(card: String) -> String:
	return str(profile.table("CombatSpells").get(card, {}).get("Class", ""))

func _spell_stats(card: String) -> String:
	var spell_class := _spell_class(card)
	var kind: Array = SPELL_KINDS.get(spell_class, ["Spell", "Заклинание"])
	var strength := ELEncyclopaedia.strength(profile, card)
	var line := "%s · %s" % [kind[int(_russian)], _text("%d ether", "%d ед. эфира") % ELEncyclopaedia.cost(profile, card)]
	if not strength.is_empty(): line += " · " + strength
	return line

func _guardian_brief() -> String:
	var boss := run.guardian()
	var title := str(boss.get("title", _text("Act guardian", "Страж акта")))
	var hint: Array = GUARDIAN_HINTS.get(boss.get("id", ""), [])
	return title if hint.is_empty() else title + "\n" + str(hint[int(_russian)])

func _size_choice(button: Button) -> void:
	var plate := button.get_theme_stylebox("normal")
	var width := button.size.x - plate.get_minimum_size().x
	if button.icon != null:
		width -= button.get_theme_constant("icon_max_width") + button.get_theme_constant("h_separation")
	if width <= 0: return
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var lines_height := font.get_multiline_string_size(button.text, button.alignment, width, font_size).y
	button.custom_minimum_size.y = maxf(45.0, ceilf(lines_height + plate.get_minimum_size().y))

static func _read_seed(value: String) -> int:
	var digits := value.strip_edges()
	if digits.is_empty(): return RANDOM_SEED
	if digits.length() > 10 or not digits.is_valid_int(): return INVALID_SEED
	var number := digits.to_int()
	return number if number >= 0 and number <= 0xffffffff else INVALID_SEED

func _text(en: String, ru: String) -> String:
	return ru if _russian else en

func _label(value: String, points: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	return label

func _button(caption: String, accent := INK) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 45
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_disabled_color", accent.darkened(0.20))
	# The kit's theme gives the original plate.
	if _kit != null: return button
	button.add_theme_stylebox_override("normal", _plate(Color("31251beb"), accent.darkened(0.35), 9))
	button.add_theme_stylebox_override("hover", _plate(Color("544028"), accent, 9))
	button.add_theme_stylebox_override("pressed", _plate(Color("695039"), accent, 9))
	button.add_theme_stylebox_override("disabled", _plate(Color("201b19e6"), Color("675746"), 9))
	return button

## The kit's frame or column box (see ELMenuKit.panel_style), padded like the
## flat `fallback`; the fallback itself without the kit.
func _panel(kind: String, fallback: StyleBoxFlat) -> StyleBox:
	if _kit == null: return fallback
	var pad := fallback.content_margin_left
	# The frame's border is wider than a flat plate's line.
	var padding := Vector4(pad + 14, pad + 14, pad + 14, pad + 10) if kind == "frame" else Vector4(pad + 2, pad, pad + 2, pad)
	return _kit.panel_style(kind, padding)

func _plate(color: Color, border: Color, margin: float) -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	plate.bg_color = color
	plate.border_color = border
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(6)
	plate.content_margin_left = margin
	plate.content_margin_right = margin
	plate.content_margin_top = margin * 0.65
	plate.content_margin_bottom = margin * 0.65
	return plate
