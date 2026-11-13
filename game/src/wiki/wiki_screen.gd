class_name ELWikiScreen
extends Control
## The in-game wiki (a remake addition, after the EI remake's wiki panel): the
## articles of tools/build_wiki.py (ELWikiData) in English or Russian, with a
## searchable contents list, page history (Back/Forward, Alt+Left/Right),
## internal links and a language switch. It is drawn over whatever is open,
## from the main menu, the battle and map Esc menus or F6 (ELWikiHotkey).
## The game is paused while the wiki is open and resumes as it was on Close
## (Esc or F6). It reads no game files and never changes saves or settings
## other than its own remembered language (user://wiki.cfg).

signal closed

const SETTINGS := "user://wiki.cfg"
const LAYER := 120
const INK := Color("e8dcc4")
const MUTED := Color("b0a088")
const GOLD := Color("d6bb88")
const PANEL := Color("1b1611")
const PANEL_2 := Color("29211a")
const LINE := Color("4a3c2c")
const UI := {
	"en": {"title": "Demiurges wiki", "back": "Back", "forward": "Forward", "home": "Contents",
		"search": "Search the wiki", "close": "Close", "list": "Pages", "nothing": "Nothing found",
		"back_tip": "Previous page (Alt+Left)", "forward_tip": "Next page (Alt+Right)", "close_tip": "Close the wiki (Esc)",
		"language_tip": "Language of the wiki", "online": "This wiki is also online at demiurges.wwworm.com/wiki",
		"turn": "Drag to turn · wheel to zoom", "reset": "Reset view", "missing_game": "This page needs that game: add it with Game files… on the remake pages of Options."},
	"ru": {"title": "Вики Demiurges", "back": "Назад", "forward": "Вперёд", "home": "Содержание",
		"search": "Поиск по вики", "close": "Закрыть", "list": "Страницы", "nothing": "Ничего не найдено",
		"back_tip": "Предыдущая страница (Alt+←)", "forward_tip": "Следующая страница (Alt+→)", "close_tip": "Закрыть вики (Esc)",
		"language_tip": "Язык вики", "online": "Эта вики есть и в Интернете: demiurges.wwworm.com/wiki",
		"turn": "Перетаскивайте, чтобы повернуть · колесо — масштаб", "reset": "Сбросить вид", "missing_game": "Для этой страницы нужна эта игра: добавьте её кнопкой «Файлы игры…» на страницах ремейка в параметрах."},
}

static var instance: ELWikiScreen
const CLIP_LABELS := {
	"en": ["Idle", "Attack", "Ranged attack", "Hit reaction", "Death", "Summon", "Rest", "Rise", "Ability", "Play"],
	"ru": ["Ожидание", "Атака", "Дальняя атака", "Получение удара", "Гибель", "Призыв", "Отдых", "Подъём", "Способность", "Играть"],
}
## The installed games ({edition: ELProfile}), set by the main menu. Their
## encyclopedia pages (ELWikiCatalog) are built from the player's own copy.
static var profiles: Dictionary = {}

var language := "en"
var page := "home"
var _history: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _was_paused := false
var _layer: CanvasLayer
var _frame: PanelContainer
var _title: Label
var _back: Button
var _forward: Button
var _home: Button
var _list_toggle: Button
var _close: Button
var _languages: Dictionary = {}
var _search: LineEdit
var _tree: Tree
var _side: VBoxContainer
var _article: RichTextLabel
var _footer: Label
var _sans: Font
var _serif: Font
## The side panel: the live creature (ELWikiPreview) or the card's icon.
var _visual: VBoxContainer
var _preview: ELWikiPreview
## Pages, categories and an index per language (authored + encyclopedia).
var _content: Dictionary = {}
var _notice := ""

## Opens the wiki over the running game (or brings it to `target`). `hint` is
## a sample of the game's own text: Cyrillic picks Russian the first time.
static func open(from: Node, target := "", hint := "") -> ELWikiScreen:
	if instance != null and is_instance_valid(instance):
		if not target.is_empty(): instance.navigate(target)
		return instance
	var screen := ELWikiScreen.new()
	screen.language = remembered_language(hint)
	var layer := CanvasLayer.new()
	layer.name = "Wiki"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(screen)
	screen._layer = layer
	from.get_tree().root.add_child(layer)
	screen.navigate(target if not target.is_empty() else "home", false)
	return screen

static func is_open() -> bool:
	return instance != null and is_instance_valid(instance)

static func remembered_language(hint := "") -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		var stored := str(config.get_value("wiki", "language", ""))
		if stored in ELWikiData.LANGUAGES: return stored
	if RegEx.create_from_string("[\\x{0400}-\\x{04FF}]").search(hint) != null: return "ru"
	return "ru" if OS.get_locale_language() == "ru" else "en"

func _init() -> void:
	instance = self
	name = "WikiScreen"
	# The wiki has its own language choice; the remake's translation of
	# its screens stays out of it.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sans := SystemFont.new()
	sans.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif"])
	_sans = sans
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
	serif.font_weight = 700
	_serif = serif
	_build()

func _enter_tree() -> void:
	_was_paused = get_tree().paused
	if get_tree().get_first_node_in_group(&"live_network_duel") == null:
		get_tree().paused = true

func _exit_tree() -> void:
	if instance == self: instance = null
	get_tree().paused = _was_paused

func close() -> void:
	if _layer == null or _layer.is_queued_for_deletion(): return
	closed.emit()
	_layer.queue_free()

# --- Layout -------------------------------------------------------------------

func _plate(color: Color, border := LINE, radius := 6, margin := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _sans)
	button.add_theme_font_size_override("font_size", 18)
	for state: String in ["font_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	button.add_theme_stylebox_override("normal", _plate(PANEL_2, LINE, 5, 6))
	button.add_theme_stylebox_override("hover", _plate(PANEL_2.lightened(0.08), GOLD, 5, 6))
	button.add_theme_stylebox_override("pressed", _plate(PANEL_2.darkened(0.2), GOLD, 5, 6))
	button.add_theme_stylebox_override("disabled", _plate(Color(PANEL_2, 0.5), Color(LINE, 0.5), 5, 6))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.custom_minimum_size = Vector2(0, 40)
	return button

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", _plate(PANEL, LINE, 10, 14))
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_frame.add_child(column)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	column.add_child(bar)
	_list_toggle = _button("☰")
	_list_toggle.toggle_mode = true
	_list_toggle.button_pressed = true
	_list_toggle.custom_minimum_size.x = 44
	_list_toggle.toggled.connect(func(on: bool): _side.visible = on)
	bar.add_child(_list_toggle)
	_back = _button("◀")
	_back.pressed.connect(go_back)
	bar.add_child(_back)
	_forward = _button("▶")
	_forward.pressed.connect(go_forward)
	bar.add_child(_forward)
	_home = _button("")
	_home.pressed.connect(func(): navigate("home"))
	bar.add_child(_home)
	_title = Label.new()
	_title.add_theme_font_override("font", _serif)
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.clip_text = true
	bar.add_child(_title)
	for lang: String in ELWikiData.LANGUAGES:
		var choice := _button(lang.to_upper())
		choice.toggle_mode = true
		choice.custom_minimum_size.x = 52
		choice.pressed.connect(func(): set_language(lang))
		bar.add_child(choice)
		_languages[lang] = choice
	_close = _button("")
	_close.pressed.connect(close)
	bar.add_child(_close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_side = VBoxContainer.new()
	_side.custom_minimum_size.x = 320
	_side.add_theme_constant_override("separation", 8)
	body.add_child(_side)
	_search = LineEdit.new()
	_search.clear_button_enabled = true
	_search.add_theme_font_override("font", _sans)
	_search.add_theme_font_size_override("font_size", 18)
	_search.add_theme_color_override("font_color", INK)
	_search.add_theme_stylebox_override("normal", _plate(PANEL_2, LINE, 5, 8))
	_search.add_theme_stylebox_override("focus", _plate(PANEL_2, GOLD, 5, 8))
	_search.text_changed.connect(func(_value: String): _fill_list())
	_search.text_submitted.connect(func(_value: String): _open_first_result())
	_side.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_override("font", _sans)
	_tree.add_theme_font_override("title_button_font", _sans)
	_tree.add_theme_font_size_override("font_size", 18)
	_tree.add_theme_color_override("font_color", INK)
	_tree.add_theme_color_override("font_selected_color", GOLD)
	_tree.add_theme_color_override("font_disabled_color", MUTED)
	_tree.add_theme_constant_override("v_separation", 6)
	_tree.add_theme_stylebox_override("panel", _plate(PANEL_2.darkened(0.25), LINE, 6, 6))
	_tree.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_tree.add_theme_stylebox_override("selected", _plate(PANEL_2.lightened(0.05), GOLD, 4, 2))
	_tree.add_theme_stylebox_override("selected_focus", _plate(PANEL_2.lightened(0.05), GOLD, 4, 2))
	_tree.item_selected.connect(_tree_chosen)
	_side.add_child(_tree)
	var reading := VBoxContainer.new()
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(reading)
	_article = RichTextLabel.new()
	_article.bbcode_enabled = true
	_article.scroll_active = true
	_article.selection_enabled = true
	_article.context_menu_enabled = true
	_article.focus_mode = Control.FOCUS_CLICK
	_article.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_article.add_theme_font_override("normal_font", _sans)
	_article.add_theme_font_override("bold_font", _serif)
	_article.add_theme_font_size_override("normal_font_size", 20)
	_article.add_theme_font_size_override("bold_font_size", 20)
	_article.add_theme_font_size_override("italics_font_size", 20)
	_article.add_theme_font_size_override("mono_font_size", 18)
	_article.add_theme_color_override("default_color", INK)
	_article.add_theme_constant_override("line_separation", 5)
	_article.add_theme_constant_override("table_h_separation", 0)
	_article.add_theme_constant_override("table_v_separation", 0)
	_article.add_theme_stylebox_override("normal", _plate(Color(0, 0, 0, 0.2), LINE, 6, 22))
	_article.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_article.meta_underlined = true
	_article.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	_article.meta_clicked.connect(_link)
	reading.add_child(_article)
	_visual = VBoxContainer.new()
	_visual.custom_minimum_size.x = 340
	_visual.add_theme_constant_override("separation", 6)
	_visual.hide()
	body.add_child(_visual)
	_footer = Label.new()
	_footer.add_theme_font_override("font", _sans)
	_footer.add_theme_font_size_override("font_size", 14)
	_footer.add_theme_color_override("font_color", MUTED)
	reading.add_child(_footer)
	resized.connect(_layout)

func _ready() -> void:
	_layout()
	_search.grab_focus.call_deferred()

func _layout() -> void:
	var area := size
	var margin := Vector2(clampf(area.x * 0.04, 12, 64), clampf(area.y * 0.05, 12, 56))
	_frame.position = margin
	_frame.size = area - margin * 2.0
	var narrow := _frame.size.x < 1000
	_side.custom_minimum_size.x = 260 if narrow else 320
	_visual.custom_minimum_size.x = 240 if narrow else 340
	# Narrow windows show either the list or the article, as on a phone.
	if narrow and not _list_toggle.button_pressed: _side.visible = false

# --- Content ------------------------------------------------------------------

## Authored pages and, for each installed game, its encyclopedia in the
## wiki language (built once per language while the wiki is open).
func _data() -> Dictionary:
	if _content.has(language): return _content[language]
	var pages: Array = []
	var categories: Array = []
	var rank := {}
	for category: Dictionary in ELWikiData.CATEGORIES:
		rank[category.id] = categories.size()
		categories.append({"id": category.id, "title": str(category.get(language, category.en)), "catalog": bool(category.get("catalog", false))})
	pages.append_array(ELWikiData.PAGES.get(language, ELWikiData.PAGES.en))
	# One encyclopedia for the installed games, both editions merged.
	pages.append_array(ELWikiCatalog.build(profiles, language).pages)
	# By category; in each, the guides and the list first, then entries by name.
	pages.sort_custom(func(a, b):
		var ca: int = rank.get(a.category, 99)
		var cb: int = rank.get(b.category, 99)
		if ca != cb: return ca < cb
		if int(a.get("order", 0)) != int(b.get("order", 0)): return int(a.get("order", 0)) < int(b.get("order", 0))
		return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	var index := {}
	for row: Dictionary in pages: index[row.key] = row
	_content[language] = {"pages": pages, "categories": categories, "index": index}
	return _content[language]

func _pages() -> Array:
	return _data().pages

func _entry(key: String) -> Dictionary:
	return _data().index.get(key, {})

func _text(key: String) -> String:
	return UI.get(language, UI.en).get(key, UI.en.get(key, key))

## Shows `key` ("home" when unknown); `remember` keeps the current page for Back.
func navigate(key: String, remember := true) -> void:
	# Encyclopedia pages of a game that is not installed lead to the contents.
	var encyclopedia := key.begins_with("card-") or key.begins_with("skill-") or key.begins_with("spec-") or key.begins_with("all-")
	_notice = _text("missing_game") if _entry(key).is_empty() and encyclopedia else ""
	if _entry(key).is_empty(): key = "home"
	if remember and key != page and _article != null:
		_history.append({"page": page, "scroll": _article.get_v_scroll_bar().value})
		_future.clear()
	page = key
	_show(0.0)

func go_back() -> void:
	if _history.is_empty(): return
	_future.append({"page": page, "scroll": _article.get_v_scroll_bar().value})
	var entry: Dictionary = _history.pop_back()
	page = entry.page
	_show(entry.scroll)

func go_forward() -> void:
	if _future.is_empty(): return
	_history.append({"page": page, "scroll": _article.get_v_scroll_bar().value})
	var entry: Dictionary = _future.pop_back()
	page = entry.page
	_show(entry.scroll)

func set_language(lang: String) -> void:
	if not lang in ELWikiData.LANGUAGES: return
	var keep := _article.get_v_scroll_bar().value if lang == language else 0.0
	language = lang
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("wiki", "language", lang)
	config.save(SETTINGS)
	_show(keep)

func _show(scroll: float) -> void:
	var row := _entry(page)
	_article.clear()
	var code := ELWikiHtml.to_bbcode(str(row.get("html", "")))
	if not _notice.is_empty() and page == "home": code = "[i][color=#%s]%s[/color][/i]\n\n" % [MUTED.to_html(false), _notice.replace("[", "[lb]")] + code
	_notice = ""
	_article.parse_bbcode(code)
	_show_visual(row)
	_restore_scroll.call_deferred(scroll)
	_title.text = _text("title")
	_home.text = _text("home")
	_close.text = _text("close")
	_back.tooltip_text = _text("back_tip")
	_forward.tooltip_text = _text("forward_tip")
	_close.tooltip_text = _text("close_tip")
	_list_toggle.tooltip_text = _text("list")
	_search.placeholder_text = _text("search")
	_footer.text = _text("online") + "  ·  Demiurges " + ELWikiData.VERSION
	_back.disabled = _history.is_empty()
	_forward.disabled = _future.is_empty()
	for lang: String in _languages:
		_languages[lang].set_pressed_no_signal(lang == language)
		_languages[lang].tooltip_text = _text("language_tip")
	_fill_list()
	# On a narrow window a chosen page replaces the list.
	if _frame.size.x < 1000 and page != "home" and _list_toggle.button_pressed:
		_list_toggle.button_pressed = false

## The live creature of a creature page, or the icon of another card.
func _show_visual(row: Dictionary) -> void:
	for child: Node in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	_preview = null
	# Story pages list heroes to show (from the installed games only).
	var heroes: Array = []
	for hero: Variant in row.get("heroes", []):
		var profile: ELProfile = profiles.get(hero[0])
		if profile != null and not profile.table("HeroTemplates").get(hero[1], {}).is_empty(): heroes.append(hero)
	if not heroes.is_empty():
		_visual.visible = true
		_show_heroes(heroes)
		return
	var card := str(row.get("card", ""))
	# The editions to show, newest first, among the installed games.
	var editions: Array = []
	for edition: Variant in row.get("models", []):
		if profiles.get(edition) != null: editions.push_front(edition)
	for edition: Variant in row.get("games", []):
		if editions.is_empty() and profiles.get(edition) != null: editions.append(edition)
	_visual.visible = not editions.is_empty() and not card.is_empty()
	if not _visual.visible: return
	var profile: ELProfile = profiles[editions[0]]
	if row.get("kind") == "creature":
		var preview := ELWikiPreview.new()
		if preview.show_creature(profile, card):
			# Etherlords draws this creature differently: switch between them.
			if editions.size() > 1:
				var switch := HBoxContainer.new()
				var group := ButtonGroup.new()
				for edition: String in editions:
					var choice := _button(ELWikiCatalog.LABELS.get(language, ELWikiCatalog.LABELS.en)[edition])
					choice.toggle_mode = true
					choice.button_group = group
					choice.button_pressed = edition == editions[0]
					choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					choice.pressed.connect(func(): preview.show_creature(profiles[edition], card))
					switch.add_child(choice)
				_visual.add_child(switch)
			preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
			preview.custom_minimum_size = Vector2(0, 320)
			_visual.add_child(preview)
			_preview = preview
			_add_animation_controls(preview)
			var hint := Label.new()
			hint.text = _text("turn")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_override("font", _sans)
			hint.add_theme_font_size_override("font_size", 14)
			hint.add_theme_color_override("font_color", MUTED)
			_visual.add_child(hint)
			var reset := _button(_text("reset"))
			reset.pressed.connect(preview.reset_view)
			_visual.add_child(reset)
		else:
			preview.free()
	var icon := profile.card_icon(card)
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(100, 100)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_visual.add_child(picture)

## The heroes of a story page ([game, HeroTemplates row, caption]), one at a
## time, with a choice between them.
func _show_heroes(heroes: Array) -> void:
	var preview := ELWikiPreview.new()
	if heroes.size() > 1:
		var choice := OptionButton.new()
		choice.fit_to_longest_item = false
		for hero: Array in heroes: choice.add_item(str(hero[2]))
		choice.item_selected.connect(func(index: int): preview.show_hero(profiles[heroes[index][0]], heroes[index][1]))
		_visual.add_child(choice)
	preview.show_hero(profiles[heroes[0][0]], heroes[0][1])
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(0, 320)
	_visual.add_child(preview)
	_preview = preview
	_add_animation_controls(preview)
	var hint := Label.new()
	hint.text = (str(heroes[0][2]) + "\n" if heroes.size() == 1 else "") + _text("turn")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", _sans)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", MUTED)
	_visual.add_child(hint)
	var reset := _button(_text("reset"))
	reset.pressed.connect(preview.reset_view)
	_visual.add_child(reset)

func _add_animation_controls(preview: ELWikiPreview) -> void:
	var controls := HBoxContainer.new()
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.fit_to_longest_item = false
	var labels: Array = CLIP_LABELS.get(language, CLIP_LABELS.en)
	var play := _button(labels.back())
	controls.add_child(options)
	controls.add_child(play)
	_visual.add_child(controls)
	var refresh := func():
		options.clear()
		for clip: String in preview.animations():
			options.add_item(labels[ELWikiPreview.ANIMATIONS.find(clip)])
			options.set_item_metadata(options.item_count - 1, clip)
		controls.visible = options.item_count > 0
		if controls.visible: options.select(0)
	preview.creature_changed.connect(refresh)
	refresh.call()
	play.pressed.connect(func():
		if options.selected >= 0:
			var settings := ELSettings.new()
			settings.load_file()
			preview.play_animation(options.get_selected_metadata(), float(settings.values.get("effects", 0.8))))

func _restore_scroll(value: float) -> void:
	_article.get_v_scroll_bar().value = value

func _matches(row: Dictionary, words: PackedStringArray) -> bool:
	var title := str(row.title).to_lower()
	for word: String in words:
		if not (word in title or word in str(row.search)): return false
	return true

func _fill_list() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var words := _search.text.strip_edges().to_lower().split(" ", false)
	var found := 0
	var current := str(_entry(page).get("category", ""))
	for category: Dictionary in _data().categories:
		var heading: TreeItem = null
		for row: Dictionary in _pages():
			if row.category != category.id or not _matches(row, words): continue
			if heading == null:
				heading = _tree.create_item(root)
				heading.set_text(0, str(category.title).to_upper())
				# Encyclopedia lists open while searching or around the page read.
				heading.collapsed = category.catalog and words.is_empty() and category.id != current
				heading.set_selectable(0, false)
				heading.set_custom_color(0, MUTED)
				heading.set_custom_font_size(0, 14)
			var item := _tree.create_item(heading)
			# An entry that only one game has names it (I or II).
			var games: Array = row.get("games", [])
			item.set_text(0, row.title + ("   " + ("I" if games[0] == "el1" else "II") if games.size() == 1 and profiles.size() > 1 else ""))
			item.set_metadata(0, row.key)
			if row.key == page:
				item.select(0)
				item.set_custom_color(0, GOLD)
			found += 1
	if found == 0:
		var none := _tree.create_item(root)
		none.set_text(0, _text("nothing"))
		none.set_selectable(0, false)
		none.set_custom_color(0, MUTED)

func _tree_chosen() -> void:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(0) == null: return
	var key := str(item.get_metadata(0))
	if key != page: navigate.call_deferred(key)

func _open_first_result() -> void:
	var item := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	if item != null and item.get_first_child() != null and item.get_first_child().get_metadata(0) != null:
		navigate(str(item.get_first_child().get_metadata(0)))

func _link(meta: Variant) -> void:
	var url := str(meta)
	var key := ELWikiHtml.key_from_url(url)
	if not key.is_empty(): navigate(key)
	elif url.begins_with("https://"): OS.shell_open(url)

# --- Keys ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode in [KEY_ESCAPE, KEY_F6] and not key.echo:
			close()
		elif key.alt_pressed and key.keycode == KEY_LEFT: go_back()
		elif key.alt_pressed and key.keycode == KEY_RIGHT: go_forward()
		elif key.ctrl_pressed and key.keycode == KEY_F: _search.grab_focus()
		elif key.keycode in [KEY_PAGEDOWN, KEY_PAGEUP] and not _search.has_focus():
			_article.get_v_scroll_bar().value += _article.size.y * 0.85 * (1 if key.keycode == KEY_PAGEDOWN else -1)
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_XBUTTON1: go_back()
		elif button.button_index == MOUSE_BUTTON_XBUTTON2: go_forward()
		else: return
		get_viewport().set_input_as_handled()
