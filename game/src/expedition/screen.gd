class_name ELExpeditionScreen
extends Control
## The map and journal are drawn together so resizing keeps routes on their buttons.
signal started(preset: String, seed: int, difficulty: String)
signal resumed
signal node_chosen(id: String)
signal choice_made(id: String)
signal save_retried
signal retried
signal left

const INK := Color("e4dcc6")
const MUTED := Color("b8aa88")
const GOLD := Color("d8aa61")
## The second game's menu inks (ELMenuKit): headings and warnings.
const TITLE := Color("d6bb88")
const WARN := Color("e6aa8b")
## One square of a spellbook, as in the deck editor.
const CELL := 46.0
## Text is drawn this much smaller than the sizes written below.
const TEXT_SCALE := 0.8
const HIGHLANDS := "res://assets/branding/expedition-highland.png"
const CITADEL := "res://assets/branding/expedition-citadel.png"
const RELIQUARY_ART := "res://assets/branding/expedition-reliquary.png"
const WARDEN_ART := "res://assets/branding/expedition-warden.png"
const RANDOM_SEED := -1
const INVALID_SEED := -2
const ACCENTS := {
	"fight": Color("d0a171"), "elite": Color("f0a26f"), "event": Color("9fbfc8"),
	"rest": Color("a8c59c"), "boss": Color("f1b86d"),
	"shop": Color("e3ca7e"), "treasure": Color("c7a4e3"),
}
const KIND := {
	"fight": ["Battle", "Бой"], "elite": ["Elite", "Элита"], "event": ["Event", "Событие"],
	"rest": ["Camp", "Привал"], "boss": ["Boss", "Босс"],
	"shop": ["Merchant", "Торговец"], "treasure": ["Treasure", "Сокровища"],
}
const MARK := {"fight": "◆", "elite": "▲", "event": "?", "rest": "+", "boss": "✦", "shop": "¤", "treasure": "◇"}
const SPELL_KINDS := {"Creature": ["Creature", "Создание"], "Sorcery": ["Sorcery", "Колдовство"], "Enchantment": ["Enchantment", "Чары"]}
const GUARDIAN_HINTS := {
	"m41 - Worm Queen": ["The queen starts with worms on the field. Draft creatures you can summon early.", "Королева начинает бой с червями на поле. Берите создания, которых можно призвать рано."],
	"m13 - Bee Hive Boss": ["The hive fills the air with bees. Bring fliers or spells that can clear several creatures.", "Улей наполняет воздух пчёлами. Возьмите летающих созданий или заклинания против нескольких целей."],
	"m23 - Mother Tick": ["The mother starts with ticks on the field. Keep cheap spells to answer them.", "Матка начинает бой с клещами на поле. Возьмите недорогие заклинания против них."],
	"m24 - Red Dragon": ["Prepare for flying dragons and spells that take control of creatures.", "Приготовьтесь к летающим драконам и заклинаниям, перехватывающим контроль над созданиями."],
	"m54 - White Lord": ["%s reduces each physical hit by 2 per copy. Remove the enchantment or use non-physical damage.", "%s уменьшает урон каждого физического удара на 2 за каждую копию. Снимите чары или используйте нефизический урон."],
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
var _merchant_footer: HBoxContainer
var _merchant_back: Button
var _merchant_leave: Button
var _choice_footer: VBoxContainer
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
var _scout_variant := ""
var _journey_open := false
var _retry_confirmation := false
var _save_error := ""
var _replacement := {}
var _shop_removal_open := false
var _camp_removal_open := false
var _legend_open := false
var _starter_preview: PanelContainer
var _deck_return_view := {}
var _scout_return_view := {}
var _view_serial := 0
var _shown_service_key := ""
var _shown_service_root := false
var _service_return_view := {}

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
	look.default_font_size = 15
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
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 20)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
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
	_title = _label(_text("ETHER EXPEDITION", "ЭФИРНАЯ ЭКСПЕДИЦИЯ"), 30, TITLE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	if _kit == null:
		var serif := SystemFont.new()
		serif.font_names = PackedStringArray(["Georgia", "Liberation Serif", "Noto Serif"])
		_title.add_theme_font_override("font", serif)
	nameplate.add_child(_title)
	_subtitle = _label("", 17, MUTED)
	nameplate.add_child(_subtitle)
	_vitals = _label("", 18, INK)
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
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_body)
	_map = Control.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.resized.connect(_place_nodes)
	_map.draw.connect(_draw_routes)
	_body.add_child(_map)
	_journal_panel = PanelContainer.new()
	_journal_panel.custom_minimum_size.x = 330
	_journal_panel.add_theme_stylebox_override("panel", _panel("frame", _plate(Color("201a16f7"), Color("967449"), 18)))
	_body.add_child(_journal_panel)
	var journal_layout := VBoxContainer.new()
	journal_layout.add_theme_constant_override("separation", 10)
	_journal_panel.add_child(journal_layout)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal_layout.add_child(_scroll)
	_journal = VBoxContainer.new()
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal.add_theme_constant_override("separation", 7)
	_scroll.add_child(_journal)
	_merchant_footer = HBoxContainer.new()
	_merchant_footer.name = "MerchantFooter"
	_merchant_footer.add_theme_constant_override("separation", 10)
	journal_layout.add_child(_merchant_footer)
	_merchant_back = _button(_text("Back to merchant", "Назад к торговцу"))
	_merchant_back.name = "ShopRemovalBack"
	_merchant_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merchant_back.pressed.connect(_show_shop_removals.bind(false))
	_merchant_footer.add_child(_merchant_back)
	_merchant_leave = _button(_text("Leave merchant", "Уйти от торговца"), GOLD)
	_merchant_leave.name = "ShopLeave"
	_merchant_leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merchant_leave.resized.connect(_size_choice.bind(_merchant_leave))
	_merchant_leave.pressed.connect(func(): choice_made.emit("enter_guardian" if run != null and run.phase == "haven" else "leave"))
	_merchant_footer.add_child(_merchant_leave)
	_merchant_footer.hide()
	_merchant_footer.minimum_size_changed.connect(_layout_dialogue, CONNECT_DEFERRED)
	_choice_footer = VBoxContainer.new()
	_choice_footer.name = "ChoiceFooter"
	_choice_footer.add_theme_constant_override("separation", 6)
	journal_layout.add_child(_choice_footer)
	_choice_footer.hide()
	_choice_footer.minimum_size_changed.connect(_layout_dialogue, CONNECT_DEFERRED)
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
	return run != null and run.phase in ["event", "rest", "reward", "boon", "relic_reward", "treasure", "shop", "haven", "discipline", "keystone_reward", "elite_gate"]

## Set while the dialog is being sized: resizing it lays out its lines
## again, which reports new minimum sizes that would size it once more.
var _laying_out := false

func _layout_dialogue() -> void:
	if not _dialogue.visible or _laying_out: return
	_laying_out = true
	var margins := _journal_panel.get_theme_stylebox("panel").get_minimum_size()
	var height := maxf(260.0, _journal.get_combined_minimum_size().y + margins.y)
	if _merchant_footer.visible: height += _merchant_footer.get_combined_minimum_size().y + 10.0
	if _choice_footer.visible: height += _choice_footer.get_combined_minimum_size().y + 10.0
	var target := Vector2(minf(560.0, size.x - 48.0), minf(height, size.y - 88.0)).round()
	if not _journal_panel.size.is_equal_approx(target): _journal_panel.size = target
	var place := ((size - _journal_panel.size) * 0.5).round()
	if not _journal_panel.position.is_equal_approx(place): _journal_panel.position = place
	_laying_out = false

func show_run(active: ELExpeditionRun, save_error := "") -> void:
	_remember_service_position()
	var service_key := _service_key(active)
	var opening_pending := active != null and active.practiced() and active.opening_selecting
	if service_key != _shown_service_key: _service_return_view.clear()
	var restore_service := {}
	if not service_key.is_empty() and active.pending_card.is_empty() and active.pending_reserve < 0 and not opening_pending and save_error.is_empty():
		restore_service = _service_return_view.duplicate()
	_view_serial += 1
	_deck_return_view.clear()
	_scout_return_view.clear()
	run = active
	_save_error = save_error
	_replacement = {}
	_shop_removal_open = false
	_camp_removal_open = false
	var backdrop := CITADEL if run != null and run.act == 3 and ResourceLoader.exists(CITADEL) else HIGHLANDS
	_art.texture = load(backdrop) if ResourceLoader.exists(backdrop) else null
	_display_deck = false
	_scout_act = 0
	_scout_rooms = false
	_scout_room_id = ""
	_scout_variant = ""
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
	if run != null and run.balanced():
		_subtitle.text = _text("ACT %d OF 3  ·  %s  ·  SEED %d", "АКТ %d ИЗ 3  ·  %s  ·  СИД %d") % [run.act, _difficulty_name(run.difficulty), run.seed_value]
	_vitals.text = "" if run == null else _text("LIFE  %d / %d   ·   %d SPELLS", "ЗДОРОВЬЕ  %d / %d   ·   КАРТЫ %d") % [run.health, run.max_health, run.deck.size()]
	if run != null and run.expanded():
		_vitals.text += "\n" + _text("GOLD  %d   ·   RELICS  %d", "ЗОЛОТО  %d   ·   РЕЛИКВИИ  %d") % [run.gold, run.relics.size()]
	if run != null and run.refined():
		_vitals.text += "\n" + (_text("RESERVE  %d / 2", "ЗАПАС  %d / 2") if run.rebalanced() else _text("RESERVE  %d / 2", "РЕЗЕРВ  %d / 2")) % run.reserve.size()
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
			button.custom_minimum_size = Vector2(104, 30)
			button.add_theme_font_size_override("font_size", 13)
			button.tooltip_text = title if not title.is_empty() else caption[int(_russian)]
			var room_hint := _room_hint(kind)
			if not room_hint.is_empty(): button.tooltip_text += "\n" + room_hint
			if kind == "boss": button.tooltip_text = _guardian_brief()
			var detour := run.evolved() and id in _available and run.is_detour(id)
			if detour:
				button.text = "↗ " + button.text
				button.tooltip_text += "\n" + _detour_hint()
				button.add_theme_color_override("font_color", ACCENTS.treasure)
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
	_shown_service_key = service_key
	_shown_service_root = not service_key.is_empty() and active.pending_card.is_empty() and active.pending_reserve < 0 and not opening_pending and save_error.is_empty()
	_draw_journal()
	if not restore_service.is_empty(): _restore_inspection_view.call_deferred(restore_service, _view_serial)

func _service_key(active: ELExpeditionRun) -> String:
	if active == null or not active.rebalanced(): return ""
	if not active.shopping() and not (active.attuned() and active.phase == "rest"): return ""
	return "%d:%s" % [active.get_instance_id(), active.current]

func _remember_service_position() -> void:
	if not _shown_service_root or _shown_service_key.is_empty() or _journal == null: return
	if _display_deck or _scout_act > 0 or _scout_rooms or not _scout_room_id.is_empty() or _journey_open or _retry_confirmation or not _replacement.is_empty() or _shop_removal_open or _camp_removal_open: return
	var focused := get_viewport().gui_get_focus_owner()
	_service_return_view = {"scroll": _scroll.scroll_vertical, "focus_name": "", "focus_node": null}
	if focused == null: return
	if _journal_panel.is_ancestor_of(focused):
		_service_return_view.focus_name = str(focused.name)
		_service_return_view.anchor = focused.get_global_rect().position.y - _scroll.get_global_rect().position.y
	else: _service_return_view.focus_node = focused

## A fresh reward, a camp or an encounter opens on the spell shop's art
## (ELExpeditionBoard); the journal keeps its views (deck, scouting, a
## spell's place after a pending choice) and a failed save.
func _show_board() -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	var journal_view := _display_deck or _scout_act > 0 or _scout_rooms or not _scout_room_id.is_empty() \
		or _journey_open or _retry_confirmation or not _replacement.is_empty() or _shop_removal_open or _camp_removal_open
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
		elif _shop_removal_open: _show_shop_removals(false)
		elif _camp_removal_open: _show_camp_removals(false)
		elif run != null and not run.pending_card.is_empty() and _save_error.is_empty(): choice_made.emit("back")
		elif run != null and not run.pending_relic.is_empty() and _save_error.is_empty(): choice_made.emit("back")
		elif run != null and run.refined() and (run.pending_reserve >= 0 or not run.pending_craft.is_empty()) and _save_error.is_empty(): choice_made.emit("back")
		elif run != null and run.practiced() and run.opening_selecting and _save_error.is_empty(): choice_made.emit("back")
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
			# Fixed end margins leave more space between the eight floors of a
			# new expedition, while keeping the old six-floor layout familiar.
			var margin := minf(36.0, _map.size.y * 0.1) if _route.size() > 6 else _map.size.y * 0.1
			var center := Vector2(
				_map.size.x * float(column + 1) / float(row.size() + 1),
				_map.size.y - margin - (_map.size.y - 2.0 * margin) * float(index) / maxf(1.0, float(_route.size() - 1)))
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
	if run != null and run.evolved() and _points.has(run.current):
		for id: String in _available:
			if not run.is_detour(id) or not _points.has(id): continue
			_map.draw_dashed_line(_points[run.current], _points[id], ACCENTS.treasure, 3.0, 5.0, true, true)
	for id: String in _nodes:
		var inspected := id == _scout_room_id
		if not _points.has(id) or (not inspected and not _nodes[id].get_meta("selected_node")): continue
		var button: Button = _nodes[id]
		_map.draw_rect(Rect2(button.position - Vector2(5, 5), button.size + Vector2(10, 10)), INK if inspected else GOLD, false, 2.0)

func _draw_journal() -> void:
	_fill_journal()
	_refresh_merchant_footer()
	_refresh_choice_footer()
	_show_board()

func _fixed_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if run == null or not run.evolved() or not _save_error.is_empty(): return result
	if _display_deck or _scout_act > 0 or _scout_rooms or not _scout_room_id.is_empty() or _journey_open or _retry_confirmation or (_shop_removal_open and _replacement.is_empty()):
		return result
	if not _replacement.is_empty():
		var confirm := _replacement.duplicate()
		confirm.title = _text("Confirm change", "Подтвердить изменение") if run.refined() else _text("Confirm replacement", "Подтвердить замену")
		if run.rebalanced(): confirm.title = _change_action(_replacement)
		confirm.description = ""
		var available := true
		if _artifact_choice(_replacement) or (run.practiced() and str(_replacement.id).begins_with("opening_spell:")):
			available = run.choices().any(func(option: Dictionary) -> bool: return option.id == _replacement.id and not bool(option.get("disabled", false)))
		elif run.refined(): available = not _change_preview(_replacement).is_empty()
		if not available:
			confirm.disabled = true
			confirm.reason = _text("This change is no longer available.", "Это изменение больше недоступно.")
		result.append(confirm)
		result.append({"id": "ui:comparison_back", "title": _text("Back to choices", "К выбору") if run.refined() else _text("Back to spellbook", "Назад к книге заклинаний")})
		return result
	if _camp_removal_open:
		result.append({"id": "ui:camp_removal_back", "title": _text("Back to camp", "Назад к привалу")})
		return result
	var pending := not run.pending_card.is_empty() or not run.pending_relic.is_empty()
	if run.refined(): pending = pending or run.pending_reserve >= 0 or not run.pending_craft.is_empty()
	if run.practiced(): pending = pending or run.opening_selecting
	if not pending and run.phase != "reward": return result
	for option: Dictionary in run.choices():
		if pending and option.id == "back":
			var back := option.duplicate()
			back.title = _text("Back to choices", "К выбору") if run.refined() else _text("Back to offers", "Назад к предложениям")
			result.append(back)
		elif not pending and option.id in ["recover_reward", "reroll_reward", "skip"]:
			result.append(option)
	return result

func _refresh_choice_footer() -> void:
	for child: Node in _choice_footer.get_children():
		_choice_footer.remove_child(child)
		child.queue_free()
	var choices := _fixed_choices()
	_choice_footer.visible = not choices.is_empty()
	if choices.is_empty(): return
	var grid := GridContainer.new()
	grid.columns = mini(2, choices.size())
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_choice_footer.add_child(grid)
	for option: Dictionary in choices:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 3)
		grid.add_child(column)
		var id := str(option.id)
		var caption := str(option.title)
		if option.has("cost"): caption += " · " + _text("%d gold", "%d золота") % int(option.cost)
		if run.rebalanced() and int(option.get("life_cost", 0)) > 0: caption += " · " + _text("%d life", "%d здоровья") % int(option.life_cost)
		if id == "recover_reward": caption += "\n" + str(option.get("description", ""))
		var button := _button(caption, GOLD if id != "skip" else MUTED)
		button.name = "Choice_" + id.replace(":", "_")
		button.add_theme_font_size_override("font_size", _font_size(17))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = bool(option.get("disabled", false))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reason := str(option.get("disabled_reason", option.get("reason", "")))
		button.tooltip_text = str(option.get("description", ""))
		if not reason.is_empty(): button.tooltip_text += "\n" + reason
		if id == "ui:comparison_back":
			button.name = "ReplacementBack"
			button.pressed.connect(_show_replacement.bind({}))
		elif id == "ui:camp_removal_back":
			button.name = "CampRemovalBack"
			button.pressed.connect(_show_camp_removals.bind(false))
		else:
			if not _replacement.is_empty(): button.name = "ConfirmReplacementChoice"
			button.pressed.connect(func():
				if not button.disabled: choice_made.emit(id))
		button.resized.connect(_size_choice.bind(button))
		column.add_child(button)
		if button.disabled and not reason.is_empty(): column.add_child(_label(reason, 14, Color("e6aa8b")))

func _refresh_merchant_footer() -> void:
	var another_view := _display_deck or _scout_act > 0 or _scout_rooms or not _scout_room_id.is_empty() \
		or _journey_open or _retry_confirmation or not _replacement.is_empty()
	_merchant_footer.visible = run != null and run.phase in ["shop", "haven"] and run.pending_card.is_empty() \
		and _save_error.is_empty() and not another_view and (not run.refined() or run.pending_reserve < 0) \
		and (not run.practiced() or not run.opening_selecting)
	_merchant_back.visible = _shop_removal_open
	var haven := run != null and run.phase == "haven"
	_merchant_back.text = _text("Back to preparations", "Назад к подготовке") if haven else _text("Back to merchant", "Назад к торговцу")
	_merchant_leave.text = _text("Face White Lord", "Бросить вызов Белому Лорду") if haven else _text("Leave merchant", "Уйти от торговца")
	_merchant_leave.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
		_journal.add_child(_label(_text("Checkpoint pending", "Сохранение не завершено"), 24, TITLE))
		_journal.add_child(_label(ELRemakeText.t(_save_error, profile), 18, Color("f4b18c")))
		var recovery := _text("Retry to keep your progress. Leaving returns you to the last saved checkpoint.", "Повторите сохранение, чтобы продолжить. Если выйти, игра вернётся к последнему сохранению.")
		if run != null and run.refined():
			recovery = _text("Your current progress is held in memory. Retry saving to continue. Main menu also retries the save and stays here if it cannot finish.", "Текущий прогресс хранится в памяти. Повторите сохранение, чтобы продолжить. Выход в главное меню тоже повторит сохранение; при ошибке этот экран останется открыт.")
		_journal.add_child(_label(recovery, 19, MUTED))
		var retry := _button(_text("Retry save", "Повторить сохранение"), GOLD)
		retry.pressed.connect(func(): save_retried.emit())
		_journal.add_child(retry)
		if _choice_pending():
			var leave := _button(_text("Main menu", "Главное меню"))
			leave.pressed.connect(func(): left.emit())
			_journal.add_child(leave)
		return
	if run == null:
		_journal.add_child(_label(_text("The road to the White Lord", "Дорога к Белому Лорду"), 24, TITLE))
		_journal.add_child(_label(_text(
			"Choose a hero and cross three acts to reach the White Lord's citadel. Your health carries between duels. Find spells, choose your battles, and claim powers from defeated guardians.",
			"Выберите героя и пройдите три акта до цитадели Белого Лорда. Раны остаются с вами: пополняйте книгу и выбирайте, с кем сражаться. Побеждённые стражи могут дать силы для следующих боёв."), 19, MUTED))
		if ELExpeditionRun.has_save():
			var resume := _button(_text("Resume expedition", "Продолжить экспедицию"), GOLD)
			resume.pressed.connect(func(): resumed.emit())
			_journal.add_child(resume)
		_journal.add_child(_label(_text("Starting spellbook", "Стартовая книга заклинаний"), 19, GOLD))
		var presets := ELExpeditionRun.starters(profile)
		var selector := OptionButton.new()
		selector.name = "ExpeditionStarter"
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
			_journal.add_child(_label(_text("Difficulty", "Сложность"), 19, GOLD))
			var difficulty := OptionButton.new()
			difficulty.name = "ExpeditionDifficulty"
			difficulty.fit_to_longest_item = false
			difficulty.custom_minimum_size.y = 42
			for key: String in ["standard", "veteran"]:
				difficulty.add_item(_difficulty_name(key))
				difficulty.set_item_metadata(difficulty.item_count - 1, key)
			_journal.add_child(difficulty)
			var difficulty_note := _label(_difficulty_description("standard"), 16, MUTED)
			difficulty_note.name = "ExpeditionDifficultyDescription"
			_journal.add_child(difficulty_note)
			difficulty.item_selected.connect(func(_index: int):
				difficulty_note.text = _difficulty_description(str(difficulty.get_selected_metadata()))
				difficulty.tooltip_text = difficulty_note.text)
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
			_attach_replacement_prompt(selector, seed_field, start, difficulty)
		return
	_deck_button.text = _text("Route", "Маршрут") if _display_deck else _text("Deck", "Колода")
	if _display_deck:
		if _choice_pending():
			var back := _button(_text("Back to choices", "К выбору"))
			back.name = "DeckBack"
			back.pressed.connect(_show_deck.bind(false))
			_journal.add_child(back)
		if run.refined():
			_draw_refined_deck()
			return
		_journal.add_child(_label(_text("Your spellbook", "Ваша книга заклинаний"), 24, TITLE))
		_draw_run_identity(false)
		_draw_battle_preview()
		var copies := {}
		var creatures := 0
		for card: String in run.deck:
			copies[card] = int(copies.get(card, 0)) + 1
			if _spell_class(card) == "Creature": creatures += 1
		_journal.add_child(_label(_text("%d creatures · %.1f average base ether", "Созданий: %d · средняя базовая цена: %.1f") % [creatures, _average_ether()], 17, MUTED))
		if run.expanded():
			_journal.add_child(_label(_text("Gold · %d", "Золото · %d") % run.gold, 19, GOLD))
			_draw_relics()
			_draw_journey_effects()
		if not run.keepsake_artifact.is_empty():
			var title := ELMapPickups.artifact_title(profile, run.keepsake_artifact)
			_journal.add_child(_label(_text("Artifact · %s", "Артефакт · %s") % title, 19, GOLD))
			_journal.add_child(_label(_text("One charge per duel", "Один заряд на бой"), 17, MUTED))
		var trained := run.trained_skills()
		if not trained.is_empty():
			_journal.add_child(_label(_text("Camp training", "Обучение на привале"), 19, GOLD))
			for code: String in trained:
				var rank: int = trained[code]
				var skill := ELHeroSkills.definition(profile, code, rank)
				var title := profile.text(str(skill.get("Name", code)))
				_journal.add_child(_label(_text("%s · Rank %d", "%s · Ступень %d") % [title, rank + 1], 17, INK))
		_journal.add_child(_section(_text("Spells in your book", "Заклинания в книге") + "  ·  %d" % run.deck.size()))
		_journal.add_child(_book_grid(run.deck, 0, "ActiveSpell", func(card: String) -> String: return _text("Copies: %d", "Копий: %d") % copies[card]))
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
	if _shop_removal_open:
		_draw_shop_removals()
		return
	if _camp_removal_open:
		_draw_camp_removals()
		return
	var heads := {
		"map": [_text("Choose a route", "Выберите маршрут"), _text("Follow a highlighted path. Your life and deck carry into the next room.", "Следуйте по подсвеченному пути. Здоровье и колода переносятся в следующую комнату.")],
		"battle": [_text("The next duel", "Следующий бой"), _text("Enter the room to continue.", "Войдите в комнату, чтобы продолжить.")],
		"reward": [_text("Spoils of battle", "Награда за бой"), _text("Take a spell or leave the spoils behind.", "Возьмите заклинание или оставьте награду.")],
		"event": [_text("An encounter", "Необычная встреча"), _text("Choose how to approach the encounter.", "Решите, как поступить.")],
		"rest": [_text("A moment of respite", "Время передохнуть"), _text("Recover some life or refine your deck.", "Восстановите здоровье или измените колоду.")],
		"boon": [_text("Prepare for the journey", "Подготовка к походу"), _text("Choose a gift to guide this expedition.", "Выберите дар, который поможет в этой экспедиции.")],
		"shop": [_text("The travelling merchant", "Странствующий торговец"), _text("Spend gold on spells, relics or services. You may make several purchases before leaving.", "Потратьте золото на заклинания, реликвии или услуги. Перед уходом можно сделать несколько покупок.")],
		"haven": [_text("Before the citadel", "Перед цитаделью"), _text("Prepare your spellbook and supplies, then face White Lord. Inspect the guardian before spending your gold.", "Подготовьте книгу и припасы, затем сразитесь с Белым Лордом. Изучите стража, прежде чем тратить золото.")],
		"treasure": [_text("A hidden cache", "Тайник"), _text("Choose a relic for the rest of the journey.", "Выберите реликвию, которая останется с вами до конца похода.")],
		"relic_reward": [_text("A hard-won relic", "Заслуженная реликвия"), _text("Choose one relic, then continue to your spell reward.", "Выберите реликвию, затем получите награду заклинаниями.")],
		"discipline": [_text("Choose your path", "Выберите свой путь"), _text("Give your spellbook a direction for this expedition.", "Задайте направление книге заклинаний на эту экспедицию.")],
		"keystone_reward": [_text("The guardian's legacy", "Наследие стража"), _text("Choose a lasting effect for this expedition. Read its benefits and conditions, then take your spell reward.", "Выберите постоянный эффект для этой экспедиции. Изучите преимущества и условия, затем получите награду заклинанием.")],
		"elite_gate": [_text("Choose your challenge", "Выберите испытание"), _text("Inspect each opponent and decide which risk to take.", "Изучите противников и решите, какой риск принять.")],
		"lost": [_text("The expedition falls", "Экспедиция пала"), _text("Your journey ended in this battle.", "Ваш поход закончился в этом бою.")],
		"won": [_text("White Lord defeated", "Белый Лорд побеждён"), _text("You survived all three acts. The expedition is complete.", "Вы прошли все три акта. Экспедиция завершена.")],
	}
	var heading: Array = heads.get(run.phase, heads.map)
	var summary := run.room_summary()
	if not summary.is_empty(): heading = [summary.title, summary.description]
	_journal.add_child(_label(heading[0], 24, TITLE))
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
	_draw_reward_receipt(summary)
	if run.refined() and (run.phase == "map" or ((run.shopping() or (run.rebalanced() and run.phase == "rest")) and run.pending_card.is_empty() and run.pending_reserve < 0)): _draw_outcome()
	if run.phase == "map" and run.practiced(): _draw_reachable_routes()
	if run.phase == "map": _draw_run_identity(true)
	if run.phase in ["map", "haven", "elite_gate"]: _draw_battle_preview(run.phase == "map")
	if run.phase == "map" and run.expanded(): _draw_journey_effects()
	if run.expanded() and _choice_pending():
		var resources := _text("Life %d / %d · Gold %d · Relics %d", "Здоровье %d / %d · Золото %d · Реликвии %d") % [run.health, run.max_health, run.gold, run.relics.size()]
		if run.evolved(): resources += " · " + _text("Spells %d / %d", "Заклинания %d / %d") % [run.deck.size(), ELExpeditionRun.MAX_DECK]
		if run.refined(): resources += " · " + (_text("Reserve %d / 2", "Запас %d / 2") if run.rebalanced() else _text("Reserve %d / 2", "Резерв %d / 2")) % run.reserve.size()
		_journal.add_child(_label(resources, 17, GOLD))
	var show_book := run.refined() and run.phase in ["reward", "shop", "haven", "rest", "event"] and (not run.rebalanced() or _needs_book_summary())
	if show_book:
		_journal.add_child(_book_summary(run.deck, true))
	if (art_key == "warden" or run.phase == "haven") and not run.opponent_at(run.current).is_empty():
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
		if run.refined():
			_journal.add_child(_label(_owned_context(run.pending_card), 16, GOLD))
			if run.phase == "haven":
				var placement := _text("Haven purchases go directly into your active book. Its reserve exchange prepares a page brought from your journey.", "Покупки на Последнем привале поступают прямо в активную книгу. Обмен резерва позволяет подготовить страницу, принесённую из похода.")
				if run.rebalanced(): placement = _text("Add this purchase to your spellbook or replace a spell.", "Добавьте покупку в боевую книгу или замените заклинание.")
				_journal.add_child(_label(placement, 16, MUTED))
		elif run.evolved(): _journal.add_child(_label(_text("Already in your spellbook: %d copies.", "В книге уже есть копии: %d.") % run.deck.count(run.pending_card), 16, GOLD))
	if run.refined() and run.pending_reserve >= 0 and run.pending_reserve < run.reserve.size():
		_journal.add_child(_spell_tile(run.reserve[run.pending_reserve], _text("FROM RESERVE", "ИЗ ЗАПАСА") if run.rebalanced() else _text("FROM RESERVE", "ИЗ РЕЗЕРВА"), true))
		if not run.rebalanced(): _journal.add_child(_label(_text("Choose one active page to exchange. The outgoing page will move into reserve; the active book stays the same size.", "Выберите активную страницу для обмена. Убранная страница перейдёт в резерв; размер активной книги не изменится."), 17, MUTED))
	if run.refined() and not run.pending_craft.is_empty():
		_journal.add_child(_spell_tile(run.pending_craft, _text("SPELL TO CHANGE", "МЕНЯЕМ") if run.rebalanced() else _text("CRAFTING SOURCE", "ИСХОДНОЕ ЗАКЛИНАНИЕ"), false))
	if run.balanced() and not run.pending_relic.is_empty(): _draw_pending_relic()
	_draw_choices()
	if _choice_pending() and (not run.rebalanced() or not show_book):
		_journal.add_child(HSeparator.new())
		var deck := _button(_text("View spellbook", "Посмотреть книгу"), GOLD)
		deck.name = "EncounterDeck"
		deck.pressed.connect(_show_deck.bind(true))
		_journal.add_child(deck)
	if run.phase == "map":
		if run.evolved() and not run.practiced(): _draw_reachable_routes()
		_journal.add_child(HSeparator.new())
		_journal.add_child(_label("%s   %s" % [MARK.boss, _guardian_brief()], 17, ACCENTS.boss))
		var scout := _button(_text("Scout guardians", "Разведка стражей"), GOLD)
		scout.name = "ScoutGuardians"
		scout.pressed.connect(_show_scout.bind(run.act))
		_journal.add_child(scout)
	if run.pending_card.is_empty() and not run.upcoming().is_empty() and (not run.evolved() or run.phase != "map"):
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
		if run.expanded():
			legend[0][1] = _text("Win gold and a spell reward.", "Победите, чтобы получить золото и заклинание.")
			legend[1][1] = _room_hint("elite")
			legend.append(["shop", _room_hint("shop")])
			legend.append(["treasure", _room_hint("treasure")])
		if run.evolved():
			var key := _button(_text("Hide map key", "Скрыть обозначения") if _legend_open else _text("Show map key", "Показать обозначения"), MUTED)
			key.name = "MapKey"
			_journal.add_child(key)
			var entries := VBoxContainer.new()
			entries.name = "MapKeyEntries"
			entries.visible = _legend_open
			entries.add_theme_constant_override("separation", 6)
			_journal.add_child(entries)
			for row: Array in legend:
				entries.add_child(_label("%s   %s" % [MARK[row[0]], row[1]], 16, ACCENTS[row[0]]))
			entries.add_child(_label(_text("↗  A Compass detour uses this act's one off-path move.", "↗  Обход с компасом расходует единственный переход без пути в этом акте."), 16, ACCENTS.treasure))
			key.pressed.connect(func():
				_legend_open = not _legend_open
				entries.visible = _legend_open
				key.text = _text("Hide map key", "Скрыть обозначения") if _legend_open else _text("Show map key", "Показать обозначения"))
		else:
			for row: Array in legend:
				_journal.add_child(_label("%s   %s" % [MARK[row[0]], row[1]], 17, ACCENTS[row[0]]))

func _book_metrics(cards: Array) -> Dictionary:
	var result := {"pages": cards.size(), "creatures": 0, "sorceries": 0, "enchantments": 0,
		"cheap_creatures": 0, "average": 0.0, "curve": [0, 0, 0, 0], "variable": 0,
		"charges": cards.size() * run.charges_per_page(), "copies": {}, "study": 0}
	var total := 0
	var focused: Array = run.study_details().get("cards", [])
	for card: String in cards:
		result.copies[card] = int(result.copies.get(card, 0)) + 1
		var cost := ELEncyclopaedia.cost(profile, card)
		match _spell_class(card):
			"Creature":
				result.creatures += 1
				if cost >= 0 and cost <= 3: result.cheap_creatures += 1
			"Sorcery": result.sorceries += 1
			"Enchantment": result.enchantments += 1
		if card in focused: result.study += 1
		if cost < 0:
			result.variable += 1
			continue
		total += cost
		var bucket := 0 if cost <= 1 else (1 if cost <= 3 else (2 if cost <= 5 else 3))
		result.curve[bucket] += 1
	result.average = float(total) / maxi(1, cards.size() - int(result.variable))
	return result

func _curve_text(stats: Dictionary) -> String:
	var text := _text("Base ether · 0–1: %d  ·  2–3: %d  ·  4–5: %d  ·  6+: %d", "Базовая цена · 0–1: %d  ·  2–3: %d  ·  4–5: %d  ·  6+: %d") % stats.curve
	if int(stats.variable) > 0: text += "  ·  X: %d" % int(stats.variable)
	return text

func _needs_book_summary() -> bool:
	if not run.pending_card.is_empty() or run.pending_reserve >= 0 or not run.pending_craft.is_empty(): return true
	for option: Dictionary in run.choices():
		var id := str(option.id)
		if id.begins_with("remove:") or id.begins_with("shop_remove:"): continue
		if not str(option.get("card", "")).is_empty() or option.has("incoming"): return true
	return false

func _book_summary(cards: Array, compact: bool) -> PanelContainer:
	var stats := _book_metrics(cards)
	var panel := PanelContainer.new()
	panel.name = "BookSummary"
	panel.add_theme_stylebox_override("panel", _panel("box", _plate(Color("252b2aeb"), Color("748b79"), 10)))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 5)
	panel.add_child(lines)
	var heading := HBoxContainer.new()
	lines.add_child(heading)
	var caption := _text("Active book · %d pages · %d charges", "Активная книга · Страниц: %d · Зарядов: %d") % [stats.pages, stats.charges]
	if run.rebalanced():
		caption = _text("Spellbook · %d spells · %d charges", "Боевая книга · Заклинаний: %d · Зарядов: %d") % [stats.pages, stats.charges]
		if compact: caption = _text("%d spells · %d creatures · %d charges", "Заклинаний: %d · Созданий: %d · Зарядов: %d") % [stats.pages, stats.creatures, stats.charges]
	var title := _label(caption, 17 if compact else 21, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	if compact:
		var inspect := _button(_text("Spellbook", "Книга") if run.rebalanced() else _text("Inspect book", "Изучить книгу"), GOLD)
		inspect.name = "InspectBookSummary"
		inspect.add_theme_font_size_override("font_size", _font_size(15))
		inspect.pressed.connect(_show_deck.bind(true))
		heading.add_child(inspect)
		if run.rebalanced():
			panel.tooltip_text = _text("Open your spellbook to see ether costs, spell types and charges per duel.", "Откройте боевую книгу, чтобы посмотреть цены в эфире, типы заклинаний и заряды на бой.")
			return panel
	lines.add_child(_label(_text("Creatures %d · Sorceries %d · Enchantments %d", "Создания: %d · Колдовство: %d · Чары: %d") % [stats.creatures, stats.sorceries, stats.enchantments], 15 if compact else 17, MUTED))
	var cheap := _text("Creatures at 0–3 base ether: %d · Average base ether: %.1f", "Созданий за 0–3 эфира: %d · Средняя базовая цена: %.1f") % [stats.cheap_creatures, stats.average]
	if int(stats.variable) > 0: cheap += _text(" (X costs omitted)", " (цены X не учтены)")
	lines.add_child(_label(cheap, 15 if compact else 17, GOLD))
	if compact:
		lines.add_child(_label(_curve_text(stats), 14, MUTED))
	else:
		lines.add_child(_label(_text("Pages by printed base ether cost", "Страницы по базовой цене в эфире"), 16, MUTED))
		var curve := HBoxContainer.new()
		curve.name = "BookCostCurve"
		curve.add_theme_constant_override("separation", 8)
		lines.add_child(curve)
		var highest := maxi(1, int(stats.curve.max()))
		for index in 4:
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			curve.add_child(column)
			var bucket_label := _label("%s · %d" % [["0–1", "2–3", "4–5", "6+"][index], stats.curve[index]], 17, GOLD)
			bucket_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(bucket_label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(36, 9)
			bar.show_percentage = false
			bar.max_value = highest
			bar.value = int(stats.curve[index])
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_theme_stylebox_override("background", _plate(Color("1c211f"), Color.TRANSPARENT, 0))
			bar.add_theme_stylebox_override("fill", _plate(Color("91a77f"), Color.TRANSPARENT, 0))
			column.add_child(bar)
		var charges := _text("Each active page starts a duel with %d charges. Reserve pages are not drawn and add no combat charges.", "Каждая активная страница начинает бой с %d зарядами. Страницы резерва не приходят в руку и не дают боевых зарядов.")
		if run.rebalanced(): charges = _text("Each spell in your book starts a duel with %d charges. Spells in reserve are not drawn and give no charges.", "Каждое заклинание в боевой книге начинает бой с %d зарядами. Заклинания из запаса не приходят в руку и не дают зарядов.")
		lines.add_child(_label(charges % run.charges_per_page(), 16, MUTED))
		var study := run.study_details()
		if not study.get("cards", []).is_empty():
			var matches := _text("Matches %s: %d spells", "Школа «%s»: %d заклинаний") if run.rebalanced() else _text("Matches %s: %d active pages", "Соответствуют школе «%s»: %d активных страниц")
			lines.add_child(_label(matches % [str(study.title), stats.study], 16, ACCENTS.event))
	panel.tooltip_text = _text("Counts include every active copy. Ether values are printed base costs, before battle effects.", "Учитывается каждая активная копия. Указаны базовые цены до влияния боевых эффектов.")
	return panel

func _owned_context(card: String) -> String:
	if run.rebalanced():
		var copies := _text("In book: %d", "В книге: %d") % run.deck.count(card)
		if run.reserve.count(card) > 0: copies += " · " + _text("In reserve: %d", "В запасе: %d") % run.reserve.count(card)
		return copies
	return _text("Active %d · Reserve %d · Owned %d / 4", "Активных: %d · В резерве: %d · Всего: %d / 4") % [run.deck.count(card), run.reserve.count(card), run.owned_copies(card)]

func _study_context(card: String) -> String:
	var study := run.study_details()
	if run.rebalanced(): return _text("School: %s", "Школа: %s") % str(study.title) if card in study.get("cards", []) else ""
	return _text("Matches %s", "Соответствует школе «%s»") % str(study.title) if card in study.get("cards", []) else ""

func _draw_refined_deck() -> void:
	_journal.add_child(_label(_text("Your spellbook", "Ваша книга заклинаний"), 24, TITLE))
	_journal.add_child(_book_summary(run.deck, false))
	if run.attuned() and not run.practiced():
		_draw_hero_details()
		_draw_abilities()
	if not run.practiced(): _draw_reserve()
	var heading := _section((_text("Spells in your book", "Заклинания в боевой книге") if run.rebalanced() else _text("Active pages", "Активные страницы")) + "  ·  %d / %d" % [run.deck.size(), ELExpeditionRun.MAX_DECK])
	heading.name = "ActiveBookHeading"
	_journal.add_child(heading)
	var copies: Dictionary = _book_metrics(run.deck).copies
	var opening := run.opening_details() if run.practiced() else {}
	var book := _book_grid(run.deck, ELExpeditionRun.MAX_DECK, "ActiveSpell", func(card: String) -> String:
		var tag := _text("%d active copies · %d charges", "Активных копий: %d · Зарядов: %d") % [copies[card], int(copies[card]) * run.charges_per_page()]
		if run.rebalanced(): tag = _text("Copies: %d · Charges: %d", "Копий: %d · Зарядов: %d") % [copies[card], int(copies[card]) * run.charges_per_page()]
		if run.practiced() and card == run.opening_spell:
			tag += " · " + (_text("Opening hand", "Стартовая рука") if bool(opening.get("active", false)) else _text("Opening spell · %s", "Стартовое заклинание · %s") % str(opening.get("status", "")))
		return tag,
		func(card: String) -> Array:
			return ["◆", ACCENTS.rest] if run.practiced() and card == run.opening_spell else [])
	book.name = "ActiveBook"
	_journal.add_child(book)
	if run.practiced():
		_draw_reserve()
		if run.implements_enabled(): _draw_field_artifacts()
		_draw_opening_details()
		_draw_hero_details()
		_draw_abilities()
	_journal.add_child(HSeparator.new())
	_draw_run_identity(false)
	_draw_battle_preview(false, not run.attuned())
	_journal.add_child(_label(_text("Gold · %d", "Золото · %d") % run.gold, 19, GOLD))
	_draw_relics()
	_draw_journey_effects()
	if not run.keepsake_artifact.is_empty():
		_journal.add_child(_label(_text("Artifact · %s", "Артефакт · %s") % ELMapPickups.artifact_title(profile, run.keepsake_artifact), 19, GOLD))
		_journal.add_child(_label(_text("One charge per duel", "Один заряд на бой"), 17, MUTED))
	var trained := {} if run.attuned() else run.trained_skills()
	if not trained.is_empty():
		_journal.add_child(_label(_text("Camp training", "Обучение на привале"), 19, GOLD))
		for code: String in trained:
			_journal.add_child(_label(ELHeroSkills.tooltip(profile, code, int(trained[code])), 17, INK))

func _draw_hero_details() -> void:
	var hero := run.hero_details()
	var panel := PanelContainer.new()
	panel.name = "HeroDetails"
	panel.add_theme_stylebox_override("panel", _panel("box", _plate(Color("282b2feb"), Color("8b947d"), 10)))
	_journal.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	panel.add_child(lines)
	lines.add_child(_label(_text("Hero skills", "Навыки героя") if run.finished() else _text("Skills for the next duel", "Навыки к следующему бою"), 20, GOLD))
	var code := str(hero.get("specialization", "NONE"))
	var specialization: Dictionary = profile.table("HeroesSpecs").get(code, {})
	if code != "NONE" and not specialization.is_empty():
		var title := profile.text(str(specialization.get("Name", code))).strip_edges()
		var inspect := _button(_text("Specialization · %s", "Специализация · %s") % title, GOLD)
		inspect.name = "HeroSpecialization"
		inspect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspect.add_theme_font_size_override("font_size", _font_size(17))
		inspect.tooltip_text = _text("Read this specialization's effect in the wiki.", "Открыть описание специализации в вики.")
		inspect.pressed.connect(func():
			var wiki := ELWikiScreen.open(self, "spec-" + code.to_lower(), title)
			wiki.tree_exited.connect(inspect.grab_focus, CONNECT_ONE_SHOT | CONNECT_DEFERRED))
		inspect.resized.connect(_size_choice.bind(inspect))
		lines.add_child(inspect)
	else:
		lines.add_child(_label(_text("No specialization", "Нет специализации"), 16, MUTED))
	var skills: Dictionary = hero.get("skills", {})
	for skill_code: String in skills:
		var rank := int(skills[skill_code])
		var title := _hero_skill_title(skill_code, rank)
		var inspect := LinkButton.new()
		inspect.name = "HeroSkill_" + skill_code
		inspect.focus_mode = Control.FOCUS_ALL
		inspect.text = _text("%s · Rank %d", "%s · Ступень %d") % [title, rank + 1]
		inspect.add_theme_color_override("font_color", INK)
		inspect.add_theme_font_size_override("font_size", _font_size(17))
		var tooltip := ELHeroSkills.tooltip(profile, skill_code, rank).split("\n")
		if not tooltip.is_empty(): tooltip[0] = title
		inspect.tooltip_text = "\n".join(tooltip)
		inspect.pressed.connect(func():
			var wiki := ELWikiScreen.open(self, "skill-" + skill_code.to_lower(), title)
			wiki.tree_exited.connect(inspect.grab_focus, CONNECT_ONE_SHOT | CONNECT_DEFERRED))
		lines.add_child(inspect)
	if skills.is_empty(): lines.add_child(_label(_text("No learned skills", "Нет изученных навыков"), 16, MUTED))

func _hero_skill_title(code: String, rank: int) -> String:
	var definition := ELHeroSkills.definition(profile, code, rank)
	var key := str(definition.get("Name", code))
	var title := profile.text(key).strip_edges()
	if not title.is_empty() and title != code and (title != key or not key.begins_with("T_")): return title
	match code:
		"PRVD": return _text("Resources", "Ресурсы")
		"SUPR": return _text("Suppression", "Сглаз")
		"CONC": return _text("Concentration", "Медитация")
	return code

func _draw_abilities() -> void:
	var powers := run.ability_details()
	if powers.is_empty(): return
	_journal.add_child(_label(_text("Guardian powers", "Силы стражей"), 22, ACCENTS.boss))
	if not run.finished(): _journal.add_child(_label(_text("Prepared powers start each duel. Change them for free at a camp or the Last Haven.", "Подготовленные силы действуют с начала каждого боя. Меняйте их бесплатно на привале или Последнем привале."), 16, MUTED))
	for detail: Dictionary in powers:
		var tile := PanelContainer.new()
		tile.name = "PowerDetail_" + str(detail.id)
		tile.add_theme_stylebox_override("panel", _panel("box", _plate(Color("302a21ed"), ACCENTS.boss.darkened(0.25), 10)))
		_journal.add_child(tile)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 5)
		tile.add_child(lines)
		lines.add_child(_label(str(detail.title), 20, ACCENTS.boss))
		lines.add_child(_label(str(detail.status), 16, ACCENTS.rest if bool(detail.prepared) else MUTED))
		lines.add_child(_label(str(detail.description), 17, INK))
		var context := str(detail.get("context", ""))
		if not context.is_empty(): lines.add_child(_label(context, 16, MUTED))

func _draw_reserve() -> void:
	var panel := PanelContainer.new()
	panel.name = "ReservePanel"
	panel.add_theme_stylebox_override("panel", _panel("box", _plate(Color("292632eb"), ACCENTS.treasure.darkened(0.2), 10)))
	_journal.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	panel.add_child(lines)
	var heading := _text("Reserve · %d / 2 spells", "Запас · Заклинаний: %d / 2") if run.rebalanced() else _text("Reserve · %d / 2 pages", "Резерв · Страниц: %d / 2")
	lines.add_child(_label(heading % run.reserve.size(), 19, TITLE))
	var rule := _text("Stored pages stay out of combat. Exchange one with an active page at a camp or the Last Haven.", "Хранимые страницы не участвуют в бою. Обменять одну на активную страницу можно на привале или в Последнем привале.")
	if run.rebalanced(): rule = _text("These spells stay out of combat. Swap them with spells in your book for free at any camp or the Last Haven, as often as you like.", "Эти заклинания не участвуют в бою. На привалах и Последнем привале их можно бесплатно менять с заклинаниями боевой книги сколько угодно раз.")
	lines.add_child(_label(rule, 16, MUTED))
	if run.reserve.is_empty():
		var empty := _text("Keep up to two spells here for later.", "Здесь можно хранить до двух заклинаний на потом.") if run.rebalanced() else _text("Reserve a reward or travelling-merchant spell to keep an option for later.", "Отложите заклинание из награды или обычной лавки, чтобы сохранить вариант на будущее.")
		lines.add_child(_label(empty, 16, MUTED))
	var reserve := _book_grid(run.reserve, 2, "ReserveSpell", func(card: String) -> String:
		var tag := _text("In reserve · No combat charges", "В запасе · Без боевых зарядов") if run.rebalanced() else _text("In reserve · No combat charges", "В резерве · Без боевых зарядов")
		if run.practiced() and card == run.opening_spell and run.opening_spell not in run.deck:
			tag += " · " + _text("Opening spell · %s", "Стартовое заклинание · %s") % str(run.opening_details().status)
		return tag)
	lines.add_child(reserve)

func _draw_opening_details() -> void:
	var detail := run.opening_details()
	if detail.is_empty(): return
	var lines := VBoxContainer.new()
	lines.name = "OpeningSpellDetails"
	lines.add_theme_constant_override("separation", 5)
	_journal.add_child(lines)
	lines.add_child(_label(_text("Opening hand · %s", "Стартовая рука · %s") % str(detail.title), 21, GOLD))
	lines.add_child(_label(str(detail.status), 16, ACCENTS.rest if bool(detail.active) else Color("e6aa8b")))
	lines.add_child(_label(str(detail.description), 17, MUTED))
	var reason := str(detail.get("reason", ""))
	if not reason.is_empty(): lines.add_child(_label(reason, 16, Color("e6aa8b")))

func _draw_outcome() -> void:
	var result := run.outcome_details()
	if result.is_empty(): return
	var panel := PanelContainer.new()
	panel.name = "EncounterOutcome"
	panel.add_theme_stylebox_override("panel", _panel("box", _plate(Color("24302ae8"), Color("83a285"), 10)))
	_journal.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 5)
	panel.add_child(lines)
	lines.add_child(_label(str(result.get("title", "")), 19, GOLD))
	lines.add_child(_label(str(result.get("description", "")), 17, INK))

func _draw_run_identity(compact: bool) -> void:
	if run == null or not run.evolved(): return
	var study := run.study_details()
	if not study.is_empty():
		var title := _text("Path · %s", "Путь · %s") % str(study.title)
		if run.rebalanced(): title = str(study.title) if str(study.id) == "none" else _text("School · %s", "Школа · %s") % str(study.title)
		var label := _label(title, 18 if compact else 22, ACCENTS.event)
		label.name = "StudyIdentity"
		label.tooltip_text = str(study.description)
		_journal.add_child(label)
		if not compact:
			_journal.add_child(_label(str(study.description), 17, MUTED))
			var names: PackedStringArray = []
			for code: String in study.get("cards", []): names.append(ELEncyclopaedia.name(profile, code))
			if not names.is_empty():
				_journal.add_child(_label(_text("Favoured spells · %s", "Предпочтительные заклинания · %s") % ", ".join(names), 16, MUTED))
	var keystones := run.keystone_details()
	if keystones.is_empty(): return
	_journal.add_child(_label(_text("Guardian legacies", "Наследие стражей"), 18 if compact else 22, GOLD))
	for item: Dictionary in keystones:
		var label := _label("✦  " + str(item.title), 17 if compact else 20, ACCENTS.boss)
		label.tooltip_text = str(item.description) + "\n" + str(item.get("context", ""))
		_journal.add_child(label)
		if not compact:
			_journal.add_child(_label(str(item.description), 17, MUTED))
			var context := str(item.get("context", ""))
			if not context.is_empty(): _journal.add_child(_label(context, 16, GOLD))

func _draw_reachable_routes() -> void:
	var heading := _label(_text("Next rooms", "Следующие комнаты"), 21, GOLD)
	heading.name = "ReachableRooms"
	_journal.add_child(heading)
	for row: Array in _route:
		for room: Dictionary in row:
			var id := str(room.id)
			if id not in _available: continue
			var kind := str(room.kind)
			var detour := run.is_detour(id)
			var caption := str(KIND[kind][int(_russian)])
			if detour: caption = _text("Detour · %s", "Обход · %s") % caption
			var opponent := run.opponent_at(id)
			var entry := VBoxContainer.new()
			entry.add_theme_constant_override("separation", 4)
			_journal.add_child(entry)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			entry.add_child(line)
			var text := "%s  %s" % [MARK[kind], caption]
			if not opponent.is_empty(): text += "\n" + str(opponent.title)
			var enter := _button(text, ACCENTS.treasure if detour else ACCENTS[kind])
			enter.name = "RouteEnter_" + id
			enter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			enter.add_theme_font_size_override("font_size", _font_size(16))
			enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			enter.pressed.connect(func(): node_chosen.emit(id))
			enter.resized.connect(_size_choice.bind(enter))
			line.add_child(enter)
			var detail := _room_hint(kind)
			if not opponent.is_empty():
				detail = _text("%d life · Level %d", "%d здоровья · Уровень %d") % [opponent.health, opponent.level]
				if opponent.has("strategy_title"): detail += " · " + str(opponent.strategy_title)
				var inspect := _button(_text("Inspect", "Изучить"), GOLD)
				inspect.name = "RouteInspect_" + id
				inspect.add_theme_font_size_override("font_size", _font_size(15))
				inspect.pressed.connect(_show_room_details.bind(id))
				line.add_child(inspect)
			if not detail.is_empty(): entry.add_child(_label(detail, 15, MUTED))
			if detour: entry.add_child(_label(_detour_hint(), 15, ACCENTS.treasure))
			enter.tooltip_text = detail
			if not opponent.is_empty() and opponent.has("strategy_hint"): enter.tooltip_text += "\n" + str(opponent.strategy_hint)
			if detour: enter.tooltip_text += "\n" + _detour_hint()
			if _nodes.has(id): _nodes[id].tooltip_text = enter.tooltip_text

func _detour_hint() -> String:
	return _text("Compass detour: uses this act's one off-path move.", "Обход с компасом: расходует единственный переход без пути в этом акте.")

func _room_hint(kind: String) -> String:
	match kind:
		"shop": return _text("Spend saved gold on spells, relics and services.", "Потратьте накопленное золото на заклинания, реликвии и услуги.")
		"treasure": return _text("Choose a passive relic for this expedition.", "Выберите пассивную реликвию для этой экспедиции.")
		"elite":
			if run != null and run.implements_enabled():
				return _text("A dangerous opponent, gold, and a choice of relic or charged artifact.", "Опасный соперник, золото и выбор: реликвия или заряженный артефакт.")
			if run != null and run.expanded():
				return _text("A dangerous opponent, gold and a relic reward.", "Опасный соперник, золото и реликвия в награду.")
	return ""

func _draw_relics() -> void:
	_journal.add_child(HSeparator.new())
	_journal.add_child(_label(_text("Expedition relics", "Реликвии экспедиции"), 20, TITLE))
	var collected := run.relic_details()
	if collected.is_empty():
		_journal.add_child(_label(_text("No passive relics collected yet.", "Пассивных реликвий пока нет."), 17, MUTED))
	for relic: Dictionary in collected:
		_journal.add_child(_label("◇  " + str(relic.title), 19, ACCENTS.treasure))
		_journal.add_child(_label(str(relic.description), 17, MUTED))
		if run.balanced():
			var context := str(relic.get("context", run.relic_status(str(relic.id))))
			if not context.is_empty(): _journal.add_child(_label(context, 17, GOLD))
	_journal.add_child(HSeparator.new())

func _artifact_choice(option: Dictionary) -> bool:
	return run != null and run.implements_enabled() and str(option.get("artifact_action", "")) in ["project", "claim", "complete", "recharge"]

func _artifact_rules() -> String:
	return _text("No ether or hand card required. Shared artifact limit: %d per duel. Spent charges stay spent between duels.",
		"Не тратит эфир и карту из руки. Общий лимит артефактов за бой: %d. Потраченные заряды не восстанавливаются между боями.") % run.artifact_use_limit()

func _artifact_cast_rules() -> String:
	return _text("Spell traps and Data Attraction still trigger. Spell Translocation does not trigger. Expert Artificer can preserve a charge, but the activation still counts against the shared limit.",
		"Ловушки для заклинаний и Притяжение Данных по-прежнему срабатывают. Транслокация заклинаний не срабатывает. «Эксперт в артефактах» может сохранить заряд, но применение всё равно расходует общий лимит.")

func _artifact_tile(row: Dictionary, tag: String, charges := -1) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", _panel("box", _plate(Color("253039e8"), Color("8faaa7"), 10)))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	tile.add_child(lines)
	lines.add_child(_label(tag, 15, GOLD))
	var heading := HBoxContainer.new()
	lines.add_child(heading)
	var icon := TextureRect.new()
	icon.texture = profile.card_icon(str(row.card))
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(icon)
	var title := _label(str(row.title), 22, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var charge_text := _text("Charges: %d / %d", "Заряды: %d / %d") % [charges, int(row.capacity)]
	if charges < 0:
		charge_text = _text("Unfinished · %d charges when completed", "Не собран · Зарядов после сборки: %d") % int(row.capacity)
	elif charges == 0:
		charge_text += " · " + _text("Depleted", "Разряжен")
	lines.add_child(_label(charge_text, 18, GOLD))
	lines.add_child(_label(str(row.description), 18, INK))
	if not str(row.get("context", "")).is_empty(): lines.add_child(_label(str(row.context), 16, MUTED))
	if not str(row.get("completion", "")).is_empty(): lines.add_child(_label(str(row.completion), 17, GOLD))
	lines.add_child(_label(_artifact_cast_rules(), 16, Color("e6aa8b")))
	var gap := int(row.get("gap", 1))
	lines.add_child(_label(_text("Ready again next round after use.", "После применения снова доступен в следующем раунде.") if gap == 1 else _text("Ready again %d rounds after use.", "После применения снова доступен через %d раунда.") % gap, 16, MUTED))
	var inspect := LinkButton.new()
	inspect.name = "ReadArtifactSpell_" + str(row.id)
	inspect.text = _text("Read original spell", "Описание исходного заклинания")
	inspect.add_theme_color_override("font_color", GOLD)
	inspect.add_theme_font_size_override("font_size", _font_size(15))
	inspect.pressed.connect(func():
		var wiki := ELWikiScreen.open(self, str(row.source), str(row.title))
		wiki.tree_exited.connect(inspect.grab_focus, CONNECT_ONE_SHOT | CONNECT_DEFERRED))
	lines.add_child(inspect)
	return tile

func _draw_field_artifacts() -> void:
	var carried := run.field_artifact_details()
	var project := run.artifact_project_details()
	if carried.is_empty() and project.is_empty(): return
	var heading := _label(_text("Travel artifacts", "Походные артефакты"), 20, TITLE)
	heading.name = "FieldArtifactHeading"
	_journal.add_child(heading)
	var rules := _label(_artifact_rules(), 17, MUTED)
	rules.name = "FieldArtifactRules"
	_journal.add_child(rules)
	if not carried.is_empty():
		var tile := _artifact_tile(carried, _text("CARRIED ARTIFACT", "СОБРАННЫЙ АРТЕФАКТ"), int(carried.charges))
		tile.name = "FieldArtifactDetails"
		_journal.add_child(tile)
	if not project.is_empty():
		var tile := _artifact_tile(project, _text("UNFINISHED PROJECT · Cannot be used in battle", "ЗАГОТОВКА · Пока недоступна в бою"))
		tile.name = "ArtifactProjectDetails"
		_journal.add_child(tile)

func _draw_artifact_offer(option: Dictionary, tile: ELExpeditionOfferTile, description: String, context: String, reason: String) -> void:
	var row := ELExpeditionArtifacts.find(profile, str(option.get("field_recipe", "")))
	_journal.add_child(tile)
	var caption := str(option.title)
	if option.has("cost"): caption += " · " + _text("%d gold", "%d золота") % int(option.cost)
	if int(option.get("life_cost", 0)) > 0: caption += " · " + _text("%d life", "%d здоровья") % int(option.life_cost)
	_tile_heading(tile, caption, TITLE, str(row.get("card", "")))
	if not row.is_empty() and not description.contains(str(row.description)):
		tile.line(str(row.description), 13, INK)
	if not description.is_empty(): tile.line(description, 13, MUTED)
	if not context.is_empty(): tile.line(context, 13, GOLD)
	if tile.disabled and not reason.is_empty(): tile.line(reason, 13, WARN)

func _draw_artifact_confirmation(option: Dictionary) -> void:
	var row := ELExpeditionArtifacts.find(profile, str(option.get("field_recipe", "")))
	var title := _label(_change_action(option), 24, TITLE)
	title.name = "ArtifactReview"
	_journal.add_child(title)
	if row.is_empty():
		_journal.add_child(_label(_text("This artifact is no longer available.", "Этот артефакт больше недоступен."), 19, MUTED))
		return
	var action := str(option.artifact_action)
	var carried := run.field_artifact_details()
	var project := run.artifact_project_details()
	var changes: Array[String] = []
	var charges := int(row.capacity)
	if action == "project":
		charges = -1
		changes.append(_text("Pack an unfinished artifact. It cannot be used until assembled.", "Вы берёте заготовку. Артефакт можно использовать только после сборки."))
		if not project.is_empty(): changes.append(_text("Give up the unfinished %s project.", "Прежняя заготовка «%s» будет потеряна.") % str(project.title))
		if not carried.is_empty(): changes.append(_text("Keep %s with its %d remaining charges.", "Собранный артефакт «%s» останется с прежними зарядами: %d.") % [str(carried.title), int(carried.charges)])
	elif action == "recharge":
		charges = int(option.get("charges_after", run.field_charges + 1))
		changes.append(_text("%s · Charges %d → %d / %d", "%s · Заряды: %d → %d / %d") % [str(row.title), run.field_charges, charges, int(row.capacity)])
	else:
		if not carried.is_empty(): changes.append(_text("Give up %s and its %d remaining charges. They do not transfer.", "Вы теряете артефакт «%s» и оставшиеся заряды: %d. Заряды не переносятся.") % [str(carried.title), int(carried.charges)])
		changes.append(_text("Take %s with %d / %d charges.", "Вы получаете артефакт «%s» с зарядами: %d / %d.") % [str(row.title), charges, int(row.capacity)])
		if action == "complete": changes.append(_text("Use up the unfinished project to assemble it.", "Заготовка расходуется при сборке."))
		elif not project.is_empty(): changes.append(_text("Keep the unfinished %s project.", "Заготовка «%s» останется у вас.") % str(project.title))
	if run.phase == "rest": changes.append(_text("This is your one camp service. Leave camp after confirming.", "Это ваше единственное занятие на привале. После подтверждения вы продолжите путь."))
	var change := _label("\n".join(changes), 18, GOLD)
	change.name = "ArtifactChangePreview"
	_journal.add_child(change)
	if option.has("cost"):
		_journal.add_child(_label(_text("Gold %d → %d", "Золото: %d → %d") % [run.gold, run.gold - int(option.cost)], 18, GOLD))
	if int(option.get("life_cost", 0)) > 0:
		_journal.add_child(_label(_text("Life after confirming: %d → %d", "Здоровье после подтверждения: %d → %d") % [run.health, run.health - int(option.life_cost)], 18, Color("e6aa8b")))
	var context := str(option.get("context", ""))
	context = context.trim_prefix(str(row.get("context", ""))).strip_edges()
	if not context.is_empty(): _journal.add_child(_label(context, 17, MUTED))
	_journal.add_child(_label(_artifact_rules(), 17, MUTED))
	var tile := _artifact_tile(row, _text("UNFINISHED PROJECT", "ЗАГОТОВКА") if action == "project" else _text("AFTER CONFIRMING", "ПОСЛЕ ПОДТВЕРЖДЕНИЯ"), charges)
	tile.name = "ReviewedArtifactDetails"
	_journal.add_child(tile)

func _draw_battle_preview(compact := false, show_powers := true) -> void:
	if run == null or not run.balanced() or run.finished(): return
	var preview := run.battle_preview()
	var box := PanelContainer.new()
	box.name = "BattleReadiness"
	box.add_theme_stylebox_override("panel", _panel("box", _plate(Color("2b3027e8"), Color("8f9c71"), 10)))
	_journal.add_child(box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	box.add_child(lines)
	lines.add_child(_label(_text("Next duel · Hero level %d", "Следующий бой · Уровень героя %d") % int(preview.level), 19, GOLD))
	var detail := _text("Base level %d", "Базовый уровень %d") % int(preview.base_level)
	for bonus: String in preview.bonus_lines: detail += "\n" + bonus
	box.tooltip_text = detail
	if not compact and not preview.bonus_lines.is_empty():
		lines.add_child(_label(detail, 16, MUTED))
	if run.practiced() and not str(preview.get("opening_line", "")).is_empty():
		var opening := _label(str(preview.opening_line), 16, GOLD)
		opening.name = "BattleOpeningSpell"
		lines.add_child(opening)
		box.tooltip_text += "\n" + str(preview.opening_line)
	if run.implements_enabled():
		for key: String in ["artifact_line", "project_line"]:
			if str(preview.get(key, "")).is_empty(): continue
			var artifact_text := str(preview[key])
			if key == "artifact_line": artifact_text += " · " + _text("Shared limit: %d/duel", "Общий лимит: %d/бой") % run.artifact_use_limit()
			var artifact := _label(artifact_text, 16, GOLD if key == "artifact_line" else MUTED)
			artifact.name = "BattleFieldArtifact" if key == "artifact_line" else "BattleArtifactProject"
			lines.add_child(artifact)
			box.tooltip_text += "\n" + str(preview[key])
	if run.attuned() and show_powers:
		var power_lines: Array = preview.get("ability_lines", [])
		for index in power_lines.size():
			var power := _label(str(power_lines[index]), 16, ACCENTS.event)
			power.name = "BattlePower_" + str(index)
			lines.add_child(power)
			box.tooltip_text += "\n" + str(power_lines[index])

func _draw_reward_receipt(summary: Dictionary) -> void:
	if not run.balanced(): return
	var receipt := str(summary.get("receipt", ""))
	if receipt.is_empty(): return
	var box := PanelContainer.new()
	box.name = "RewardReceipt"
	box.add_theme_stylebox_override("panel", _panel("box", _plate(Color("34301de8"), GOLD.darkened(0.3), 10)))
	_journal.add_child(box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	box.add_child(lines)
	lines.add_child(_label(_text("Victory rewards received", "Полученные награды за победу"), 16, GOLD))
	lines.add_child(_label(receipt, 18, INK))

func _draw_pending_relic() -> void:
	var incoming := ELExpeditionContent.relic(profile, run.pending_relic, run.balanced())
	if incoming.is_empty(): return
	var box := PanelContainer.new()
	box.name = "IncomingRelic"
	box.add_theme_stylebox_override("panel", _panel("box", _plate(Color("302537e8"), ACCENTS.treasure, 12)))
	_journal.add_child(box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	box.add_child(lines)
	lines.add_child(_label(_text("INCOMING RELIC", "НОВАЯ РЕЛИКВИЯ"), 15, GOLD))
	lines.add_child(_label(str(incoming.title), 22, ACCENTS.treasure))
	lines.add_child(_label(str(incoming.description), 17, MUTED))
	var context := run.relic_status(run.pending_relic)
	if not context.is_empty(): lines.add_child(_label(context, 17, GOLD))

func _draw_journey_effects() -> void:
	var effects := run.journey_effects()
	if effects.is_empty(): return
	_journal.add_child(_label(_text("Along the way", "В пути"), 20, GOLD))
	for effect: String in effects:
		_journal.add_child(_label(effect, 17, MUTED))

func _show_shop_removals(enabled: bool) -> void:
	if run.rebalanced():
		_view_serial += 1
		if enabled: _remember_service_position()
	_shop_removal_open = enabled
	_draw_journal()
	if run.rebalanced() and not enabled and not _service_return_view.is_empty():
		_restore_inspection_view.call_deferred(_service_return_view.duplicate(), _view_serial)
		return
	var target := _merchant_back if enabled else _journal.get_node_or_null("ShopRemoveChoice") as Button
	if target != null: target.grab_focus()

func _draw_shop_removals() -> void:
	_journal.add_child(_label(_text("Remove a spell", "Удалить заклинание") if run.rebalanced() else _text("Refine your spellbook", "Улучшить книгу заклинаний"), 24, TITLE))
	var detail := _text("Remove one copy of a spell. Choose carefully: each merchant offers this service once.", "Удалите одну копию заклинания. Выбирайте обдуманно: у каждого торговца этой услугой можно воспользоваться один раз.")
	if run.rebalanced(): detail = _text("Remove one copy from your spellbook. Once per merchant.", "Удалить одну копию из боевой книги. Один раз у каждого торговца.")
	_journal.add_child(_label(detail, 19, MUTED))
	_journal.add_child(_label(_text("Gold · %d", "Золото · %d") % run.gold, 19, GOLD))
	_draw_choices(true)
	var deck := _button(_text("View spellbook", "Посмотреть книгу"), GOLD)
	deck.name = "EncounterDeck"
	deck.pressed.connect(_show_deck.bind(true))
	_journal.add_child(deck)

func _show_camp_removals(enabled: bool) -> void:
	_view_serial += 1
	if run.attuned() and enabled: _remember_service_position()
	_camp_removal_open = enabled
	_draw_journal()
	if run.attuned() and not enabled and not _service_return_view.is_empty():
		_restore_inspection_view.call_deferred(_service_return_view.duplicate(), _view_serial)
		return
	var target := _journal_panel.find_child("CampRemovalBack" if enabled else "CampRemoveChoice", true, false) as Button
	if target != null: target.grab_focus()

func _draw_camp_removals() -> void:
	_journal.add_child(_label(_text("Remove a spell", "Удалить заклинание"), 24, TITLE))
	_journal.add_child(_label(_text("Remove one copy from your spellbook instead of resting or another camp service.", "Удалить одну копию из боевой книги вместо отдыха или другого занятия на привале."), 19, MUTED))
	_journal.add_child(_book_summary(run.deck, true))
	_draw_choices(true)

func _draw_removal_entry(options: Array[Dictionary], camp := false) -> void:
	if options.is_empty(): return
	var offer := options[0]
	var available: bool = options.any(func(option: Dictionary) -> bool: return not bool(option.get("disabled", false)))
	var caption := _text("Choose a spell to remove", "Выбрать заклинание для удаления")
	if run.rebalanced(): caption = _text("Remove a spell", "Удалить заклинание")
	if offer.has("cost"): caption += " · " + _text("%d gold", "%d золота") % int(offer.cost)
	var button := _button(caption, GOLD)
	button.name = "CampRemoveChoice" if camp else "ShopRemoveChoice"
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = not available
	var reason := str(offer.get("disabled_reason", offer.get("reason", "")))
	button.tooltip_text = reason if not available else str(offer.get("description", ""))
	button.pressed.connect(func():
		if button.disabled: return
		if camp: _show_camp_removals(true)
		else: _show_shop_removals(true))
	button.resized.connect(_size_choice.bind(button))
	_journal.add_child(HSeparator.new())
	_journal.add_child(button)
	var description := str(offer.get("description", ""))
	if camp: description = _text("Remove one copy instead of resting.", "Удалить одну копию вместо отдыха.")
	if not description.is_empty(): _journal.add_child(_label(description, 16, MUTED))
	if not available and not reason.is_empty(): _journal.add_child(_label(reason, 16, Color("e6aa8b")))

func _ordered_choices() -> Array[Dictionary]:
	var choices := run.choices()
	if run.practiced() and run.phase == "rest" and run.pending_card.is_empty() and run.pending_reserve < 0 and not run.opening_selecting:
		var preparation: Array[Dictionary] = []
		for option: Dictionary in choices:
			if _free_preparation(option): preparation.append(option)
		for option: Dictionary in choices:
			if not _free_preparation(option): preparation.append(option)
		return preparation
	if not run.rebalanced() or run.pending_card.is_empty(): return choices
	var ordered: Array[Dictionary] = []
	# Both ways of keeping an offer appear before the potentially long book.
	for option: Dictionary in choices:
		if option.id == "add": ordered.append(option)
	for option: Dictionary in choices:
		if str(option.get("storage", "")) in ["reserve_add", "reserve_replace"]: ordered.append(option)
	for option: Dictionary in choices:
		if option.id != "add" and str(option.get("storage", "")) not in ["reserve_add", "reserve_replace"]: ordered.append(option)
	return ordered

func _free_preparation(option: Dictionary) -> bool:
	return bool(option.get("opening_toggle", false)) or str(option.id).get_slice(":", 0) in ["swap_select", "prepare_power", "suppress_power"]

## Choices that name one spell show it as a square of the book (its cost
## under it); a click takes the choice, and the spell's lines show under the
## squares while it is under the pointer or has focus.
const SQUARE_CHOICES := ["card", "buy_card", "library_card", "craft", "craft_select", "replace", "remove",
	"shop_remove", "purge", "echo", "swap_with", "swap_select", "reserve_replace", "opening_spell"]

func _draw_choices(removals_only := false) -> void:
	var listed := {}
	var merchant := run.phase in ["shop", "haven"] and run.pending_card.is_empty()
	var camp := run.rebalanced() and run.phase == "rest" and run.pending_card.is_empty() and run.pending_reserve < 0 and (not run.practiced() or not run.opening_selecting)
	var removals: Array[Dictionary] = []
	var replacement_heading := false
	var camp_group := ""
	var fixed := {}
	var flow: HFlowContainer = null
	var detail: PanelContainer = null
	for option: Dictionary in _fixed_choices(): fixed[str(option.id)] = true
	for option: Dictionary in _ordered_choices():
		var id: String = option.id
		if fixed.has(id): continue
		if merchant:
			if id in ["leave", "enter_guardian"]: continue # Always available in the fixed footer.
			var removal := id.begins_with("shop_remove:")
			if removal: removals.append(option)
			if removal != removals_only: continue
		elif camp:
			var removal := id.begins_with("remove:")
			if removal: removals.append(option)
			if removal != removals_only: continue
		if camp and run.practiced() and not removals_only:
			var group := "free" if _free_preparation(option) else "main"
			if group != camp_group:
				camp_group = group
				var heading := _section(_text("Prepare your book · Free", "Подготовка книги · Бесплатно") if group == "free" else _text("Choose one camp service", "Одно занятие на привале"))
				heading.name = "CampFreePreparation" if group == "free" else "CampMainService"
				_journal.add_child(heading)
				flow = null
		var card := str(option.get("card", ""))
		var icon_code := str(option.get("artifact", {}).get("spell", card))
		if _artifact_choice(option): icon_code = str(ELExpeditionArtifacts.find(profile, str(option.get("field_recipe", ""))).get("card", ""))
		var shown_card := card
		if run.refined() and id.begins_with("craft:"):
			shown_card = str(option.get("incoming", card))
			icon_code = shown_card
		var caption: String = option.title
		var prefix := id.get_slice(":", 0)
		var outgoing := prefix in ["replace", "remove", "shop_remove", "purge", "swap_with", "reserve_replace"]
		if run.rebalanced() and id.begins_with("replace:") and not replacement_heading:
			replacement_heading = true
			_journal.add_child(_section(_text("Replace a spell", "Заменить заклинание")))
			flow = null
		if run.rebalanced() and id.begins_with("swap_with:"):
			caption = _text("Put %s in reserve", "Убрать в запас: %s") % ELEncyclopaedia.name(profile, card)
		var count := 0
		if prefix in ["replace", "remove", "shop_remove", "purge", "echo"]:
			var copy_key := prefix + ":" + card
			if listed.has(copy_key): continue
			listed[copy_key] = true
			count = run.deck.count(card)
		var price := ""
		if option.has("cost"): price = _text("%d gold", "%d зол.") % int(option.cost)
		if run.rebalanced() and int(option.get("life_cost", 0)) > 0:
			price += (" · " if not price.is_empty() else "") + _text("%d life", "%d здор.") % int(option.life_cost)
		if not price.is_empty(): caption += " · " + price
		var square := prefix in SQUARE_CHOICES and not shown_card.is_empty() and profile.table("CombatSpells").has(shown_card) \
			and not _artifact_choice(option) and not option.has("relic")
		var description := str(option.get("description", ""))
		var context := str(option.get("context", ""))
		var reason := str(option.get("disabled_reason", option.get("reason", "")))
		if bool(option.get("disabled", false)) and reason.is_empty() and option.has("cost") and int(option.cost) > run.gold:
			reason = _text("Need %d more gold.", "Не хватает %d золота.") % (int(option.cost) - run.gold)
		var button: Button
		if square: button = ELExpeditionCardCell.make(profile, shown_card, CELL)
		else: button = ELExpeditionOfferTile.new()
		button.name = "Choice_" + id.replace(":", "_")
		if run.attuned() and prefix in ["prepare_power", "suppress_power"]:
			button.name = "PowerToggle_" + id.get_slice(":", 1)
		if run.practiced() and bool(option.get("opening_toggle", false)):
			button.name = "OpeningToggle"
		button.disabled = bool(option.get("disabled", false))
		var tip: PackedStringArray = []
		if square: tip.append(caption)
		for part: String in [description, context, reason]:
			if not part.is_empty(): tip.append(part)
		button.tooltip_text = "\n".join(tip)
		var removal_preview := run.refined() and prefix in ["remove", "shop_remove", "purge"]
		if id.begins_with("replace:") or option.has("incoming") or removal_preview or _artifact_choice(option) or (run.practiced() and id.begins_with("opening_spell:")):
			button.name = "Compare_" + id.replace(":", "_")
			button.pressed.connect(func():
				if not button.disabled: _show_replacement(option))
		else:
			button.pressed.connect(func():
				if not button.disabled: choice_made.emit(id))
		if square:
			# The spell's own lines, shown under the squares.
			var lines: Array = [[caption, TITLE]]
			var stats := _spell_stats(shown_card)
			if run.rebalanced() and outgoing:
				var held := run.reserve.count(card) if str(option.get("storage", "")) == "reserve_replace" else run.deck.count(card)
				stats += " · " + (_text("%d in reserve", "В запасе: %d") if str(option.get("storage", "")) == "reserve_replace" else _text("%d in book", "В книге: %d")) % held
			if prefix in ["card", "buy_card"] or (run.refined() and prefix in ["craft", "library_card"]):
				match profile.table("CombatSpells")[shown_card].get("Rarity"):
					"Rare": stats += " · " + _text("Rare", "Редкое")
					"Unique": stats += " · " + _text("Unique", "Тайное")
				if run.evolved() and not run.refined(): stats += " · " + _text("%d in spellbook", "В книге: %d") % run.deck.count(card)
			lines.append([stats, GOLD])
			if run.refined():
				if not run.rebalanced() or (not outgoing and run.owned_copies(shown_card) > 0): lines.append([_owned_context(shown_card), MUTED])
				if not run.rebalanced() or not outgoing:
					var focus := _study_context(shown_card)
					if not focus.is_empty(): lines.append([focus, ACCENTS.event])
			var spell_description := profile.card_description(shown_card)
			if not description.is_empty() and (not run.rebalanced() or prefix not in ["swap_with", "reserve_replace"]): lines.append([description, MUTED])
			if spell_description != shown_card and not spell_description.is_empty() and not description.contains(spell_description): lines.append([spell_description, MUTED])
			if not context.is_empty(): lines.append([context, GOLD])
			if button.disabled and not reason.is_empty(): lines.append([reason, WARN])
			if flow == null:
				flow = HFlowContainer.new()
				flow.name = "CardChoices"
				flow.add_theme_constant_override("h_separation", 5)
				flow.add_theme_constant_override("v_separation", 5)
				_journal.add_child(flow)
				detail = _card_detail()
				_journal.add_child(detail)
				_fill_card_detail(detail, shown_card, lines)
			var cell := button as ELExpeditionCardCell
			if count > 1: cell.set_count("×%d" % count)
			if run.practiced() and shown_card == run.opening_spell and outgoing: cell.set_mark("◆", ACCENTS.rest)
			var shown_detail := detail
			var show := func(): _fill_card_detail(shown_detail, shown_card, lines)
			button.mouse_entered.connect(show)
			button.focus_entered.connect(show)
			var under := price if not price.is_empty() else _ether_text(shown_card)
			flow.add_child(_card_square(button, under))
			continue
		flow = null
		var tile := button as ELExpeditionOfferTile
		if _artifact_choice(option):
			_draw_artifact_offer(option, tile, description, context, reason)
			continue
		if run.evolved() and run.phase in ["discipline", "keystone_reward"]:
			_draw_major_offer(option, tile, description, context, reason)
			continue
		if run.balanced() and option.has("relic"):
			_draw_relic_offer(option, tile, description, context, reason)
			continue
		_journal.add_child(tile)
		_tile_heading(tile, caption, TITLE if not icon_code.is_empty() else INK, icon_code)
		if not description.is_empty(): tile.line(description, 13, MUTED)
		if run.refined():
			if id == "add" or str(option.get("storage", "")) == "reserve_add":
				var preview := _change_preview(option)
				if not preview.is_empty(): tile.line(_change_text(preview, true), 13, ACCENTS.rest)
			if id.begins_with("craft_select:") and not run.rebalanced():
				tile.line(_text("Choose a result next. Nothing is spent until you confirm a recipe.", "Далее выберите результат. До подтверждения рецепта ничего не расходуется."), 13, ACCENTS.event)
		if not context.is_empty(): tile.line(context, 13, GOLD)
		if tile.disabled and not reason.is_empty(): tile.line(reason, 13, WARN)
		if run.evolved() and run.phase == "elite_gate" and id.begins_with("elite:") and not tile.disabled:
			var inspect := _button(_text("Inspect this opponent", "Изучить этого противника"), GOLD)
			inspect.name = "InspectElite_" + id.get_slice(":", 1)
			inspect.pressed.connect(_show_room_details.bind(run.current, id.get_slice(":", 1)))
			_journal.add_child(inspect)
	if (merchant or camp) and not removals_only: _draw_removal_entry(removals, camp)

func _draw_major_offer(option: Dictionary, tile: ELExpeditionOfferTile, description: String, context: String, reason: String) -> void:
	var accent := ACCENTS.boss if run.phase == "keystone_reward" else ACCENTS.event
	_journal.add_child(tile)
	var title := str(option.title)
	if option.has("cost"): title += " · " + _text("%d gold", "%d золота") % int(option.cost)
	_tile_heading(tile, title, accent)
	if not description.is_empty(): tile.line(description, 13, MUTED)
	if not context.is_empty(): tile.line(context, 13, GOLD)
	if tile.disabled and not reason.is_empty(): tile.line(reason, 13, WARN)

func _draw_relic_offer(option: Dictionary, tile: ELExpeditionOfferTile, description: String, context: String, reason: String) -> void:
	_journal.add_child(tile)
	var title := "◇  " + str(option.title)
	if option.has("cost"): title += " · " + _text("%d gold", "%d золота") % int(option.cost)
	_tile_heading(tile, title, ACCENTS.treasure)
	if not description.is_empty(): tile.line(description, 13, MUTED)
	if not context.is_empty(): tile.line(context, 13, GOLD)
	if tile.disabled and not reason.is_empty(): tile.line(reason, 13, WARN)

func _attach_replacement_prompt(selector: OptionButton, seed_field: LineEdit, start: Button, difficulty: OptionButton) -> void:
	var prompt := VBoxContainer.new()
	prompt.name = "ReplaceCheckpoint"
	prompt.add_theme_constant_override("separation", 8)
	prompt.hide()
	_journal.add_child(prompt)
	prompt.add_child(_label(_text("Start a new expedition?", "Начать новую экспедицию?"), 20, TITLE))
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
			started.emit(selector.get_selected_metadata(), seed, difficulty.get_selected_metadata())
			return
		selector.disabled = true
		difficulty.disabled = true
		seed_field.editable = false
		start.hide()
		prompt.show()
		cancel.grab_focus())
	cancel.pressed.connect(func():
		prompt.hide()
		error_label.hide()
		selector.disabled = false
		difficulty.disabled = false
		seed_field.editable = true
		start.show()
		start.grab_focus())
	confirm.pressed.connect(func():
		if prompt.is_visible_in_tree(): started.emit(selector.get_selected_metadata(), _read_seed(seed_field.text), difficulty.get_selected_metadata()))

func _difficulty_name(value: String) -> String:
	return _text("Veteran", "Ветеран") if value == "veteran" else _text("Standard", "Обычная")

func _difficulty_description(value: String) -> String:
	if value == "veteran":
		return _text("Enemies have 15% more life. Ordinary and elite opponents gain one level, except special encounters. Base victory gold is 15% higher.",
			"У врагов на 15% больше здоровья. Обычные и элитные соперники получают ещё один уровень, кроме особых поединков. Базовая награда золотом за победу выше на 15%.")
	return _text("The standard expedition challenge, with the usual enemies and victory rewards.",
		"Обычная сложность экспедиции: стандартные противники и награды за победы.")

func _show_starter(preset: Dictionary) -> void:
	if _starter_preview != null:
		_map.remove_child(_starter_preview)
		_starter_preview.queue_free()
	_starter_preview = PanelContainer.new()
	_starter_preview.add_theme_stylebox_override("panel", _panel("frame", _plate(Color("211a16ed"), Color("967449"), 18)))
	_map.add_child(_starter_preview)
	_starter_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_starter_preview.anchor_bottom = 0.45
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
	summary.add_child(_label(preset.name, 24, TITLE))
	var life := ELExpeditionRun._life_cap(profile, preset, 1)
	summary.add_child(_label(_text("%d starting life · Level %d · %d spells", "%d здоровья · Уровень %d · Карт: %d") % [life, preset.level, preset.cards.size()], 17, MUTED))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var book := _book_grid(preset.cards, 0, "StarterSpell")
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(book)

func _show_deck(enabled: bool) -> void:
	var restore := {}
	if run != null and run.refined():
		_view_serial += 1
		if enabled and not _display_deck:
			var focused := get_viewport().gui_get_focus_owner()
			_deck_return_view = {"scroll": _scroll.scroll_vertical, "focus_name": "", "focus_node": null,
				"scout_act": _scout_act, "scout_rooms": _scout_rooms, "scout_room": _scout_room_id,
				"scout_variant": _scout_variant, "journey": _journey_open, "retry": _retry_confirmation}
			if focused != null:
				if _journal_panel.is_ancestor_of(focused): _deck_return_view.focus_name = str(focused.name)
				else: _deck_return_view.focus_node = focused
		elif not enabled and _display_deck:
			restore = _deck_return_view.duplicate()
			_deck_return_view.clear()
	_scout_act = 0
	_scout_rooms = false
	_scout_room_id = ""
	_scout_variant = ""
	_journey_open = false
	_retry_confirmation = false
	_display_deck = enabled
	if not restore.is_empty():
		_scout_act = int(restore.scout_act)
		_scout_rooms = bool(restore.scout_rooms)
		_scout_room_id = str(restore.scout_room)
		_scout_variant = str(restore.scout_variant)
		_journey_open = bool(restore.journey)
		_retry_confirmation = bool(restore.retry)
	_map.queue_redraw()
	_draw_journal()
	if not restore.is_empty():
		_restore_inspection_view.call_deferred(restore, _view_serial)
		return
	var back := _journal_panel.find_child("ReplacementBack", true, false) as Button
	if back != null: back.grab_focus()
	elif _choice_pending():
		var control := _journal.get_node_or_null("DeckBack" if enabled else "EncounterDeck") as Button
		if control != null: control.grab_focus()
	else: _deck_button.grab_focus()

func _restore_inspection_view(state: Dictionary, serial: int) -> void:
	await get_tree().process_frame
	if serial != _view_serial or _display_deck: return
	_scroll.follow_focus = false
	var focused: Control
	if not str(state.focus_name).is_empty():
		focused = _journal_panel.find_child(str(state.focus_name), true, false) as Control
	elif is_instance_valid(state.focus_node):
		focused = state.focus_node as Control
	var focus_target := focused
	if state.has("anchor") and focused is BaseButton and focused.disabled:
		# Bought stock stays visible. Keep keyboard navigation near it when
		# that exact offer can no longer receive focus.
		var nearest := INF
		focus_target = null
		for candidate: Node in _journal.find_children("*", "Button", true, false):
			var button := candidate as Button
			if button.disabled or not button.is_visible_in_tree(): continue
			var distance := absf(button.get_global_rect().position.y - focused.get_global_rect().position.y)
			if distance < nearest:
				nearest = distance
				focus_target = button
	if focus_target != null and focus_target.is_visible_in_tree() and (not focus_target is BaseButton or not focus_target.disabled): focus_target.grab_focus()
	_scroll.scroll_vertical = int(state.scroll)
	await get_tree().process_frame
	if serial == _view_serial and state.has("anchor") and is_instance_valid(focused) and focused.is_visible_in_tree():
		var shift := focused.get_global_rect().position.y - _scroll.get_global_rect().position.y - float(state.anchor)
		_scroll.scroll_vertical += int(round(shift))
	_scroll.follow_focus = true

func _show_scout(act: int) -> void:
	_scout_act = act
	_draw_journal()
	var control := _journal.get_node_or_null("ScoutGuardians" if act == 0 else "ScoutBack") as Button
	if control != null: control.grab_focus()

func _show_room_scout(enabled: bool) -> void:
	_scout_rooms = enabled
	_scout_room_id = ""
	_scout_variant = ""
	_draw_journal()
	var control := _journal.get_node_or_null("RoomScoutBack" if enabled else "ScoutRooms") as Button
	if control != null: control.grab_focus()

func _show_room_details(id: String, variant := "") -> void:
	var previous := _scout_room_id
	var previous_variant := _scout_variant
	var restore := {}
	if run.refined():
		_view_serial += 1
		if not id.is_empty() and previous.is_empty():
			var focused := get_viewport().gui_get_focus_owner()
			_scout_return_view = {"scroll": _scroll.scroll_vertical, "focus_name": "", "focus_node": null}
			if focused != null:
				if _journal_panel.is_ancestor_of(focused): _scout_return_view.focus_name = str(focused.name)
				else: _scout_return_view.focus_node = focused
		elif id.is_empty():
			restore = _scout_return_view.duplicate()
			_scout_return_view.clear()
	_scout_room_id = id
	_scout_variant = variant
	_map.queue_redraw()
	_draw_journal()
	var focus_name := "InspectRoom_" + previous if _scout_rooms else "LastBattle"
	if run.phase in ["event", "haven"] and previous == run.current: focus_name = "InspectWarden"
	elif run.phase == "elite_gate" and not previous_variant.is_empty(): focus_name = "InspectElite_" + previous_variant
	elif run.phase == "map" and run.evolved(): focus_name = "RouteInspect_" + previous
	if not id.is_empty(): focus_name = "RoomDetailBack"
	if not restore.is_empty():
		# Reachable-room Inspect controls live inside rows, not directly in
		# the journal. Restore their original scroll as well as their focus.
		if str(restore.focus_name).is_empty() and not is_instance_valid(restore.focus_node): restore.focus_name = focus_name
		_restore_inspection_view.call_deferred(restore, _view_serial)
		return
	var control := _journal.find_child(focus_name, true, false) as Button
	if control != null: control.grab_focus()

func _show_journey(enabled: bool) -> void:
	_journey_open = enabled
	_draw_journal()
	var control := _journal.get_node_or_null("JourneyBack" if enabled else "JourneyLog") as Button
	if control != null: control.grab_focus()

func _draw_result_actions() -> void:
	var opponent := run.opponent_at(run.current)
	if not opponent.is_empty():
		_journal.add_child(_label(str(opponent.title), 20, TITLE))
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
	_journal.add_child(_label(_text("Retry this seed?", "Повторить сид?"), 24, TITLE))
	var details := _text("Start again with seed %d and the same starting spellbook. This replaces the saved expedition.",
		"Начните заново с сидом %d и той же стартовой книгой. Новый поход заменит сохранённую экспедицию.")
	_journal.add_child(_label(details % run.seed_value, 19, MUTED))
	if run.balanced():
		_journal.add_child(_label(_text("Difficulty · %s", "Сложность · %s") % _difficulty_name(run.difficulty), 19, GOLD))
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
	_journal.add_child(_label(_text("Journey log", "Журнал пути"), 24, TITLE))
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
	_draw_battle_preview()
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
				if opponent.has("strategy_title"): detail += "\n" + str(opponent.strategy_title)
				_journal.add_child(_label(detail, 18, INK))
				_nodes[id].tooltip_text = detail
				if opponent.has("strategy_hint"): _nodes[id].tooltip_text += "\n" + str(opponent.strategy_hint)
				var inspect := _button(_text("Inspect spellbook", "Посмотреть книгу"), GOLD)
				inspect.name = "InspectRoom_" + id
				inspect.pressed.connect(_show_room_details.bind(id))
				_journal.add_child(inspect)
			else:
				var room_hint := _room_hint(kind)
				if not room_hint.is_empty(): _journal.add_child(_label(room_hint, 17, MUTED))

func _draw_room_details() -> void:
	var id := _scout_room_id
	var caption := _text("Back to rooms", "К списку комнат")
	if run.finished(): caption = _text("Back to results", "К итогам")
	elif run.phase == "event" and id == run.current: caption = _text("Back to encounter", "К событию")
	elif run.phase == "haven" and id == run.current: caption = _text("Back to preparations", "Назад к подготовке")
	elif run.phase == "elite_gate" and id == run.current: caption = _text("Back to challenges", "Назад к испытаниям")
	var back := _button(caption)
	back.name = "RoomDetailBack"
	back.pressed.connect(_show_room_details.bind(""))
	_journal.add_child(back)
	var opponent := run.elite_preview(id, _scout_variant) if run.evolved() and not _scout_variant.is_empty() else run.opponent_at(id)
	if opponent.is_empty():
		_journal.add_child(_label(_text("Opponent details are unavailable.", "Сведения о сопернике недоступны."), 19, MUTED))
		return
	_journal.add_child(_label(str(opponent.title), 27, INK))
	if not _scout_variant.is_empty():
		for option: Dictionary in run.choices():
			if str(option.id) == "elite:" + _scout_variant:
				_journal.add_child(_label(str(option.title), 20, ACCENTS.elite))
				break
	_journal.add_child(_label(_text("%d life · Level %d", "%d здоровья · Уровень %d") % [opponent.health, opponent.level], 18, GOLD))
	_draw_battle_preview()
	if run.phase == "map":
		var enter := _button(_text("Enter encounter", "Войти в бой") if run.evolved() else _text("Enter battle", "Вступить в бой"), GOLD)
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
	if run.balanced(): boss = run.guardian_at(_scout_act)
	_journal.add_child(_label(_text("GUARDIAN OF ACT %d", "СТРАЖ АКТА %d") % _scout_act, 15, GOLD))
	if boss.is_empty():
		_journal.add_child(_label(_text("Guardian details are unavailable.", "Сведения о страже недоступны."), 19, MUTED))
		return
	_journal.add_child(_label(str(boss.title), 27, INK))
	_journal.add_child(_label(_text("%d life · Level %d", "%d здоровья · Уровень %d") % [boss.health, boss.level], 18, GOLD))
	if _scout_act == run.act: _draw_battle_preview()
	var hint := _guardian_hint(boss)
	if not hint.is_empty(): _journal.add_child(_label(hint, 17, MUTED))
	_draw_opponent_book(boss, "GuardianSpecialization")

func _draw_opponent_book(opponent: Dictionary, specialization_control: String) -> void:
	var strategy := str(opponent.get("strategy_title", ""))
	if not strategy.is_empty():
		_journal.add_child(_label(strategy, 21, ACCENTS.elite))
		var hint := str(opponent.get("strategy_hint", ""))
		if not hint.is_empty(): _journal.add_child(_label(hint, 17, MUTED))
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
	_journal.add_child(_section(_text("Starting spellbook", "Стартовая книга заклинаний") + "  ·  %d" % opponent.cards.size()))
	_journal.add_child(_book_grid(opponent.cards, 0, "OpponentSpell"))

func _show_replacement(option: Dictionary) -> void:
	if run.rebalanced(): _view_serial += 1
	var return_button := "Compare_" + str(_replacement.get("id", "")).replace(":", "_")
	_replacement = option
	_draw_journal()
	var focus := _journal_panel.find_child(return_button if option.is_empty() else "ReplacementBack", true, false) as Button
	if focus != null: focus.grab_focus()

func _draw_replacement() -> void:
	if run.refined():
		_draw_refined_replacement()
		return
	var old: String = _replacement.card
	var exchange := _replacement.has("incoming")
	var next := str(_replacement.get("incoming", run.pending_card))
	_journal.add_child(_label(_text("Replace a spell", "Замена заклинания"), 24, TITLE))
	if exchange: _journal.add_child(_label(_replacement.description, 17, GOLD))
	if _replacement.has("cost"):
		_journal.add_child(_label(_text("Pay %d gold when you confirm. Gold available: %d.", "При подтверждении будет потрачено %d золота. У вас: %d.") % [int(_replacement.cost), run.gold], 18, GOLD))
	_journal.add_child(_label(_text("Replace one copy. Your spellbook stays at %d cards.", "Заменяется одна копия. В книге останется карт: %d.") % run.deck.size(), 17, MUTED))
	var delta := ELEncyclopaedia.cost(profile, next) - ELEncyclopaedia.cost(profile, old)
	_journal.add_child(_label(_text("Average base ether\n%.1f → %.1f", "Средняя базовая цена\n%.1f → %.1f") % [_average_ether(), _average_ether(delta)], 19, GOLD))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	_journal.add_child(columns)
	columns.add_child(_spell_tile(old, _text("OUTGOING", "УБИРАЕМ"), true))
	columns.add_child(_spell_tile(next, _text("INCOMING", "ДОБАВЛЯЕМ"), true))
	if run.evolved(): return # Confirmation and Back remain outside the scroll.
	var confirm := _button(_text("Confirm replacement", "Подтвердить замену"), GOLD)
	confirm.name = "ConfirmReplacementChoice"
	confirm.disabled = bool(_replacement.get("disabled", false))
	confirm.pressed.connect(func():
		if not confirm.disabled: choice_made.emit(_replacement.id))
	_journal.add_child(confirm)
	var back := _button(_text("Back to choices", "К выбору") if exchange else _text("Back to spellbook", "Назад к книге заклинаний"))
	back.name = "ReplacementBack"
	back.pressed.connect(_show_replacement.bind({}))
	_journal.add_child(back)

func _change_preview(option: Dictionary) -> Dictionary:
	var active := run.deck.duplicate()
	var stored := run.reserve.duplicate()
	var id := str(option.get("id", ""))
	var storage := str(option.get("storage", ""))
	var outgoing := str(option.get("card", ""))
	var incoming := str(option.get("incoming", run.pending_card))
	var consume := maxi(1, int(option.get("consume", 1)))
	match storage:
		"reserve_select": return {}
		"reserve_add":
			incoming = run.pending_card if not run.pending_card.is_empty() else outgoing
			outgoing = ""
			if incoming.is_empty(): return {}
			stored.append(incoming)
		"reserve_replace":
			var index := int(option.get("reserve_index", -1))
			if index < 0 or index >= stored.size() or incoming.is_empty(): return {}
			outgoing = stored[index]
			stored[index] = incoming
		"reserve_swap":
			var reserve_index := int(option.get("reserve_index", -1))
			var active_index := int(id.get_slice(":", 1))
			if reserve_index < 0 or reserve_index >= stored.size() or active_index < 0 or active_index >= active.size(): return {}
			outgoing = active[active_index]
			incoming = stored[reserve_index]
			active[active_index] = incoming
			stored[reserve_index] = outgoing
		_:
			if id == "add":
				outgoing = ""
				if incoming.is_empty(): return {}
				active.append(incoming)
			elif id.begins_with("replace:"):
				var index := int(id.get_slice(":", 1))
				if index < 0 or index >= active.size() or incoming.is_empty(): return {}
				outgoing = active[index]
				active[index] = incoming
			elif id.get_slice(":", 0) in ["remove", "shop_remove", "purge"]:
				var index := int(id.get_slice(":", 1))
				if index < 0 or index >= active.size(): return {}
				outgoing = active[index]
				incoming = ""
				active.remove_at(index)
			elif option.has("incoming"):
				if outgoing.is_empty() or incoming.is_empty() or active.count(outgoing) < consume: return {}
				active[active.find(outgoing)] = incoming
				for index in consume - 1: active.remove_at(active.find(outgoing))
			else: return {}
	return {"active": active, "reserve": stored, "outgoing": outgoing, "incoming": incoming,
		"consume": consume, "storage": storage}

func _change_action(option: Dictionary) -> String:
	if _artifact_choice(option):
		match str(option.artifact_action):
			"project": return _text("Take this project", "Взять эту заготовку")
			"claim": return _text("Take this artifact", "Взять этот артефакт")
			"complete": return _text("Finish the artifact", "Собрать артефакт")
			"recharge": return _text("Recharge artifact", "Зарядить артефакт")
	if run.practiced() and str(option.id).begins_with("opening_spell:"):
		return _text("Prepare opening spell", "Подготовить стартовое заклинание")
	var storage := str(option.get("storage", ""))
	if storage == "reserve_swap": return _text("Swap spells", "Обменять заклинания")
	if storage == "reserve_replace": return _text("Replace in reserve", "Заменить в запасе")
	if str(option.id).get_slice(":", 0) in ["remove", "shop_remove", "purge"]: return _text("Remove spell", "Удалить заклинание")
	if int(option.get("consume", 1)) > 1: return _text("Combine two copies", "Объединить две копии")
	if str(option.id).begins_with("craft:"): return _text("Rewrite spell", "Переписать заклинание")
	return _text("Replace spell", "Заменить заклинание")

func _short_change_text(change: Dictionary, compact: bool) -> String:
	var before := _book_metrics(run.deck)
	var after := _book_metrics(change.active)
	var lines: Array[String] = []
	if change.active == run.deck:
		lines.append(_text("Spellbook unchanged.", "Боевая книга не изменится."))
	else:
		if before.pages != after.pages:
			lines.append(_text("Spells %d → %d · Charges per duel %d → %d", "Заклинания: %d → %d · Заряды на бой: %d → %d") % [before.pages, after.pages, before.charges, after.charges])
		var counts: Array[String] = []
		for metric: Array in [
			["creatures", _text("Creatures", "Создания")],
			["cheap_creatures", _text("Creatures at 0–3 ether", "Создания за 0–3 эфира")],
			["sorceries", _text("Sorceries", "Колдовство")],
			["enchantments", _text("Enchantments", "Чары")]]:
			if before[metric[0]] != after[metric[0]]: counts.append("%s %d → %d" % [metric[1], before[metric[0]], after[metric[0]]])
		if not counts.is_empty(): lines.append(" · ".join(counts))
		if not is_equal_approx(float(before.average), float(after.average)):
			var precision := "%.2f" if "%.1f" % float(before.average) == "%.1f" % float(after.average) else "%.1f"
			lines.append(_text("Average base ether %s → %s", "Средняя базовая цена: %s → %s") % [precision % float(before.average), precision % float(after.average)])
			if int(before.variable) > 0 or int(after.variable) > 0: lines.append(_text("X costs omitted.", "Цены X не учтены."))
		if lines.is_empty(): lines.append(_text("Book size and charges stay the same.", "Размер книги и число зарядов не изменятся."))
	if run.reserve.size() != change.reserve.size():
		lines.append(_text("Reserve %d → %d / 2", "Запас: %d → %d / 2") % [run.reserve.size(), change.reserve.size()])
	if not compact:
		var affected: Array[String] = []
		for card: String in [str(change.outgoing), str(change.incoming)]:
			if card.is_empty() or card in affected: continue
			affected.append(card)
			var copies: Array[String] = []
			if run.deck.count(card) != change.active.count(card): copies.append(_text("in book %d → %d", "в книге %d → %d") % [run.deck.count(card), change.active.count(card)])
			if run.reserve.count(card) != change.reserve.count(card): copies.append(_text("in reserve %d → %d", "в запасе %d → %d") % [run.reserve.count(card), change.reserve.count(card)])
			if not copies.is_empty(): lines.append(ELEncyclopaedia.name(profile, card) + " · " + " · ".join(copies))
	var opening_change := _opening_change_text(change)
	if not opening_change.is_empty(): lines.append(opening_change)
	return "\n".join(lines)

func _opening_change_text(change: Dictionary) -> String:
	if not run.practiced() or run.opening_spell.is_empty(): return ""
	if run.opening_spell not in [str(change.outgoing), str(change.incoming)]: return ""
	var before := run.opening_details()
	var after := run.opening_details_for(change.active, change.reserve)
	var title := ELEncyclopaedia.name(profile, run.opening_spell)
	if after.is_empty():
		return _text("Opening hand: %s → no prepared spell.", "Стартовая рука: %s → без подготовленного заклинания.") % title
	if not bool(after.active):
		var line := _text("Opening spell · %s: %s", "Стартовое заклинание · %s: %s") % [title, str(after.status)]
		var reason := str(after.get("reason", ""))
		if not reason.is_empty(): line += "\n" + reason
		return line
	if not bool(before.get("active", false)):
		return _text("%s returns to your opening hand.", "%s снова будет в стартовой руке.") % title
	if str(change.outgoing) == run.opening_spell:
		return _text("Opening spell stays prepared: %s.", "Стартовое заклинание остаётся подготовленным: %s.") % title
	return ""

func _change_text(change: Dictionary, compact: bool) -> String:
	if run.rebalanced(): return _short_change_text(change, compact)
	var before := _book_metrics(run.deck)
	var after := _book_metrics(change.active)
	var lines: Array[String] = []
	if change.active == run.deck:
		lines.append(_text("Active book and combat charges stay unchanged.", "Активная книга и боевые заряды не меняются."))
	else:
		lines.append(_text("Active pages %d → %d · Charges per duel %d → %d", "Активные страницы: %d → %d · Заряды на бой: %d → %d") % [before.pages, after.pages, before.charges, after.charges])
		lines.append(_text("Creatures %d → %d · Creatures at 0–3 ether %d → %d", "Создания: %d → %d · Создания за 0–3 эфира: %d → %d") % [before.creatures, after.creatures, before.cheap_creatures, after.cheap_creatures])
		if not compact:
			lines.append(_text("Sorceries %d → %d · Enchantments %d → %d", "Колдовство: %d → %d · Чары: %d → %d") % [before.sorceries, after.sorceries, before.enchantments, after.enchantments])
		lines.append(_text("Average base ether %.1f → %.1f", "Средняя базовая цена: %.1f → %.1f") % [before.average, after.average])
		if int(before.variable) > 0 or int(after.variable) > 0: lines.append(_text("Variable X costs are omitted from the average.", "Переменные цены X не учитываются в среднем."))
	if change.reserve != run.reserve:
		lines.append(_text("Reserve pages %d → %d / 2", "Страницы резерва: %d → %d / 2") % [run.reserve.size(), change.reserve.size()])
	if not compact:
		var affected: Array[String] = []
		for card: String in [str(change.outgoing), str(change.incoming)]:
			if card.is_empty() or card in affected: continue
			affected.append(card)
			lines.append(_text("%s · Active %d → %d · Reserve %d → %d", "%s · Активных: %d → %d · В резерве: %d → %d") % [ELEncyclopaedia.name(profile, card), run.deck.count(card), change.active.count(card), run.reserve.count(card), change.reserve.count(card)])
	return "\n".join(lines)

func _draw_refined_replacement() -> void:
	if _artifact_choice(_replacement):
		_draw_artifact_confirmation(_replacement)
		return
	if run.practiced() and str(_replacement.id).begins_with("opening_spell:"):
		_draw_opening_confirmation(_replacement)
		return
	var change := _change_preview(_replacement)
	if change.is_empty():
		_journal.add_child(_label(_text("This change is no longer available.", "Это изменение больше недоступно."), 20, TITLE))
		return
	var storage := str(change.storage)
	var title := _text("Review the change", "Проверьте изменение")
	if storage == "reserve_swap": title = _text("Exchange active and reserve pages", "Обмен активной страницы с резервом")
	elif storage == "reserve_replace": title = _text("Replace a reserve page", "Замена страницы в резерве")
	elif str(change.incoming).is_empty(): title = _text("Remove one active page", "Удаление активной страницы")
	elif int(change.consume) > 1: title = _text("Combine matching pages", "Объединение одинаковых страниц")
	if run.rebalanced(): title = _change_action(_replacement)
	_journal.add_child(_label(title, 24, TITLE))
	if not str(_replacement.get("description", "")).is_empty(): _journal.add_child(_label(str(_replacement.description), 17, MUTED))
	if _replacement.has("cost"):
		var payment := _text("Pay %d gold when you confirm. Gold available: %d.", "При подтверждении будет потрачено %d золота. У вас: %d.") % [int(_replacement.cost), run.gold]
		if run.rebalanced(): payment = _text("Gold %d → %d", "Золото: %d → %d") % [run.gold, run.gold - int(_replacement.cost)]
		_journal.add_child(_label(payment, 18, GOLD))
	if int(_replacement.get("life_cost", 0)) > 0:
		var life_cost := int(_replacement.life_cost)
		_journal.add_child(_label(_text("Life after confirming: %d → %d", "Здоровье после подтверждения: %d → %d") % [run.health, run.health - life_cost], 18, Color("e6aa8b")))
	var impact := _label(_change_text(change, false), 17, ACCENTS.rest)
	impact.name = "BookChangePreview"
	_journal.add_child(impact)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	_journal.add_child(columns)
	if not str(change.outgoing).is_empty():
		var tag := _text("OUTGOING · %d active page(s)", "УБИРАЕМ · Активных страниц: %d") % int(change.consume)
		if storage == "reserve_swap": tag = _text("MOVES TO RESERVE", "ПЕРЕХОДИТ В РЕЗЕРВ")
		elif storage == "reserve_replace": tag = _text("LEAVES RESERVE", "УБИРАЕМ ИЗ РЕЗЕРВА")
		if run.rebalanced():
			tag = _text("GIVE UP · Two copies", "ОТДАЁМ · Две копии") if int(change.consume) > 1 else _text("GIVE UP · One copy", "ОТДАЁМ · Одна копия")
			if storage == "reserve_swap": tag = _text("MOVES TO RESERVE", "В ЗАПАС")
			elif storage == "reserve_replace": tag = _text("LEAVES RESERVE", "УБИРАЕМ ИЗ ЗАПАСА")
		columns.add_child(_spell_tile(str(change.outgoing), tag, true))
	if not str(change.incoming).is_empty():
		var tag := _text("INCOMING · 1 active page", "ДОБАВЛЯЕМ · 1 активная страница")
		if storage in ["reserve_add", "reserve_replace"]: tag = _text("STORED IN RESERVE", "СОХРАНЯЕМ В РЕЗЕРВЕ")
		if run.rebalanced(): tag = _text("IN RESERVE", "В ЗАПАС") if storage in ["reserve_add", "reserve_replace"] else _text("IN YOUR BOOK · One copy", "В БОЕВУЮ КНИГУ · Одна копия")
		columns.add_child(_spell_tile(str(change.incoming), tag, true))

func _draw_opening_confirmation(option: Dictionary) -> void:
	var card := str(option.get("card", str(option.id).get_slice(":", 1)))
	var heading := _label(_text("Prepare your opening hand", "Подготовить стартовую руку"), 24, TITLE)
	heading.name = "OpeningSpellReview"
	_journal.add_child(heading)
	var previous := run.opening_details()
	if not previous.is_empty():
		_journal.add_child(_label(_text("Opening spell: %s → %s", "Стартовое заклинание: %s → %s") % [str(previous.title), ELEncyclopaedia.name(profile, card)], 18, GOLD))
	_journal.add_child(_label(_text("Start each duel with this spell in a normal opening-hand slot. Its casting cost, charges and discard rules are unchanged.", "Каждый бой это заклинание займёт обычное место в стартовой руке. Его цена, заряды и правила сброса не меняются."), 17, MUTED))
	var context := str(option.get("context", ""))
	if not context.is_empty(): _journal.add_child(_label(context, 18, GOLD))
	if option.has("cost"):
		_journal.add_child(_label(_text("Gold %d → %d", "Золото: %d → %d") % [run.gold, run.gold - int(option.cost)], 18, GOLD))
	_journal.add_child(_spell_tile(card, _text("IN YOUR OPENING HAND", "В СТАРТОВОЙ РУКЕ"), true))

func _average_ether(delta := 0) -> float:
	var total := delta
	for card: String in run.deck: total += ELEncyclopaedia.cost(profile, card)
	return float(total) / maxi(1, run.deck.size())

func _spell_tile(card: String, tag: String, describe: bool) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.add_theme_stylebox_override("panel", _panel("box", _plate(Color("1a1712eb"), Color("5c4c36"), 8)))
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 3)
	tile.add_child(contents)
	contents.add_child(_label(tag, 14, GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	contents.add_child(row)
	var cell := ELExpeditionCardCell.make(profile, card, CELL)
	cell.focus_mode = Control.FOCUS_NONE
	row.add_child(_card_square(cell, _ether_text(card)))
	# One-line labels beside the square: wrapping text next to a fixed-size
	# square can make the containers lay each other out forever.
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 2)
	row.add_child(names)
	for entry: Array in [[ELEncyclopaedia.name(profile, card), 18, TITLE], [_spell_stats(card), 15, GOLD]]:
		var label := _label(str(entry[0]), entry[1], entry[2])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 60
		names.add_child(label)
	var description := profile.card_description(card)
	if not description.is_empty() and description != card:
		if describe: contents.add_child(_label(description, 16, MUTED))
		cell.tooltip_text = description
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
	var hint := _guardian_hint(boss)
	return title if hint.is_empty() else title + "\n" + hint

func _guardian_hint(opponent: Dictionary) -> String:
	var hint: Array = GUARDIAN_HINTS.get(opponent.get("id", ""), [])
	if hint.is_empty(): return ""
	var detail := str(hint[int(_russian)])
	if opponent.get("id") == "m54 - White Lord": detail = detail % ELEncyclopaedia.name(profile, "STSK")
	return detail

func _size_choice(button: Button) -> void:
	var plate := button.get_theme_stylebox("normal")
	var width := button.size.x - plate.get_minimum_size().x
	if button.icon != null:
		width -= button.get_theme_constant("icon_max_width") + button.get_theme_constant("h_separation")
	if width <= 0: return
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var lines_height := font.get_multiline_string_size(button.text, button.alignment, width, font_size).y
	button.custom_minimum_size.y = maxf(32.0, ceilf(lines_height + plate.get_minimum_size().y))

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
	label.add_theme_font_size_override("font_size", _font_size(points))
	label.add_theme_color_override("font_color", color)
	return label

static func _font_size(points: int) -> int:
	return maxi(11, roundi(points * TEXT_SCALE))

## A heading on the Options screen's header strip (ELMenuKit.section); a
## flat bar without the art.
func _section(title: String) -> PanelContainer:
	var strip := PanelContainer.new()
	var style: StyleBox = _kit._section_styles.get("strip") if _kit != null else null
	if style == null: style = _plate(Color("2a2219e8"), Color("5c4c36"), 6)
	strip.add_theme_stylebox_override("panel", style)
	var caption := _label(title, 18, TITLE)
	caption.name = "Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	strip.add_child(caption)
	return strip

## A spellbook square with a short line under it (its cost).
func _card_square(cell: Button, under: String) -> VBoxContainer:
	var square := VBoxContainer.new()
	square.name = "Square_" + str(cell.name)
	square.add_theme_constant_override("separation", 1)
	square.add_child(cell)
	var label := Label.new()
	label.name = "Cost"
	label.text = under
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = CELL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", GOLD if not cell.disabled else MUTED.darkened(0.3))
	square.add_child(label)
	return square

## A spellbook as the deck editor shows it: a square per copy (cheapest
## first), its ether cost under it, `capacity` places in all (empty ones
## dark), and the spell under the pointer or focus described below. The first
## copy of each spell is named `prefix` + "_" + its code; `tag` gives a
## spell's extra line ("" for none) and `mark` its corner marker.
func _book_grid(cards: Array, capacity: int, prefix: String, tag := Callable(), mark := Callable()) -> VBoxContainer:
	var book := VBoxContainer.new()
	book.name = prefix + "Book"
	book.add_theme_constant_override("separation", 5)
	var sorted: Array = cards.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var left := ELEncyclopaedia.cost(profile, a)
		var right := ELEncyclopaedia.cost(profile, b)
		if left != right: return left < right
		var by_name := ELEncyclopaedia.name(profile, a).naturalnocasecmp_to(ELEncyclopaedia.name(profile, b))
		return by_name < 0 if by_name != 0 else a < b)
	var flow := HFlowContainer.new()
	flow.name = "Squares"
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	book.add_child(flow)
	var detail := _card_detail()
	var group := ButtonGroup.new()
	var named := {}
	var first: Array = []
	for card: String in sorted:
		var cell := ELExpeditionCardCell.make(profile, card, CELL)
		cell.toggle_mode = true
		cell.button_group = group
		if not named.has(card):
			named[card] = true
			cell.name = prefix + "_" + card
		var lines: Array = [[ELEncyclopaedia.name(profile, card), TITLE], [_spell_stats(card), GOLD]]
		var extra := str(tag.call(card)) if tag.is_valid() else ""
		if not extra.is_empty(): lines.append([extra, INK])
		if run != null and run.refined():
			var focus := _study_context(card)
			if not focus.is_empty(): lines.append([focus, ACCENTS.event])
		var description := profile.card_description(card)
		if not description.is_empty() and description != card: lines.append([description, MUTED])
		var tip: PackedStringArray = []
		for entry: Array in lines: tip.append(str(entry[0]))
		cell.tooltip_text = "\n".join(tip)
		if mark.is_valid():
			var marker: Array = mark.call(card)
			if not marker.is_empty(): cell.set_mark(str(marker[0]), marker[1])
		var show := func(): _fill_card_detail(detail, card, lines)
		cell.mouse_entered.connect(show)
		cell.focus_entered.connect(show)
		cell.pressed.connect(show)
		if first.is_empty(): first = [card, lines]
		flow.add_child(_card_square(cell, _ether_text(card)))
	for empty in maxi(0, capacity - sorted.size()):
		flow.add_child(_card_square(ELExpeditionCardCell.make(profile, "", CELL), ""))
	if not first.is_empty():
		book.add_child(detail)
		_fill_card_detail(detail, first[0], first[1])
	else: detail.free()
	return book

func _ether_text(card: String) -> String:
	var cost := ELEncyclopaedia.cost(profile, card)
	return _text("X ether", "X эф.") if cost < 0 else _text("%d ether", "%d эф.") % cost

## The spell under the pointer of a group of squares: its icon and lines.
func _card_detail() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CardDetail"
	panel.add_theme_stylebox_override("panel", _panel("box", _plate(Color("1a1712eb"), Color("5c4c36"), 8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 2)
	row.add_child(lines)
	return panel

## Fills a CardDetail: `lines` are [text, ink] pairs, the first its title.
func _fill_card_detail(panel: PanelContainer, card: String, lines: Array) -> void:
	if panel == null or not is_instance_valid(panel): return
	(panel.find_child("Icon", true, false) as TextureRect).texture = profile.card_icon(card) if not card.is_empty() else null
	var column := panel.find_child("Lines", true, false) as VBoxContainer
	for child: Node in column.get_children():
		column.remove_child(child)
		child.queue_free()
	for index in lines.size():
		var entry: Array = lines[index]
		if str(entry[0]).is_empty(): continue
		column.add_child(_label(str(entry[0]), 18 if index == 0 else 16, entry[1]))

## A tile's first line, with the offer's icon when it has one.
func _tile_heading(tile: ELExpeditionOfferTile, text: String, ink: Color, icon_code := "") -> void:
	if icon_code.is_empty():
		tile.line(text, 15, ink).name = "Title"
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	tile.content.add_child(row)
	var icon := TextureRect.new()
	icon.texture = profile.card_icon(icon_code)
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := tile.line(text, 15, ink)
	label.name = "Title"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.content.remove_child(label)
	row.add_child(label)

func _button(caption: String, accent := INK) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 32
	button.add_theme_font_size_override("font_size", 14)
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
	var padding := Vector4(pad * 0.5 + 16, pad * 0.5 + 16, pad * 0.5 + 16, pad * 0.5 + 12) if kind == "frame" else Vector4(pad * 0.7 + 2, pad * 0.6, pad * 0.7 + 2, pad * 0.6)
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
