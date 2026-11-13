class_name ELGameChoice
extends HBoxContainer
## The two games side by side (a remake addition), on the main menu and the
## game files screen. Choosing an installed game emits `selected`; choosing a
## missing one emits `missing` so the host can offer to add it.
signal selected(edition: String)
signal missing(edition: String)
signal expedition_requested
signal autochess_requested

const INK := Color("d6bb88")
var current := ""
## Editions that can be played now: {edition: true}.
var available: Dictionary = {}
var buttons: Dictionary = {}
var font_size := 16
## Opens the wiki (ELWikiScreen).
var wiki_button: Button
var expedition_available := false
var _expedition_button: Button
var _autochess_button: Button
## A caption in the current game's language: Russian game texts open the wiki
## in Russian until the player picks a language there.
var wiki_hint := ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for edition: String in ELContentLibrary.EDITIONS:
		var button := Button.new()
		button.name = edition
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(176, 46)
		button.add_theme_font_size_override("font_size", font_size)
		for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color(INK, 0.85))
		for state: String in ["font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(state, INK.lightened(0.25))
		button.add_theme_stylebox_override("normal", _plate(0.72, Color(INK, 0.3)))
		button.add_theme_stylebox_override("hover", _plate(0.8, Color(INK, 0.6)))
		button.add_theme_stylebox_override("pressed", _plate(0.88, INK))
		button.add_theme_stylebox_override("hover_pressed", _plate(0.88, INK))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_chosen.bind(edition))
		add_child(button)
		buttons[edition] = button
	# The remake's wiki (also F6 anywhere).
	wiki_button = Button.new()
	wiki_button.name = "Wiki"
	wiki_button.focus_mode = Control.FOCUS_NONE
	wiki_button.custom_minimum_size = Vector2(96, 46)
	wiki_button.add_theme_font_size_override("font_size", font_size)
	_plain(wiki_button)
	wiki_button.pressed.connect(func():
		var wiki := ELWikiScreen.open(self, "", wiki_hint)
		if not wiki.closed.is_connected(_refresh): wiki.closed.connect(_refresh))
	add_child(wiki_button)
	if expedition_available:
		_expedition_button = Button.new()
		_expedition_button.name = "Expedition"
		_expedition_button.custom_minimum_size = Vector2(138, 46)
		_expedition_button.add_theme_font_size_override("font_size", font_size)
		_plain(_expedition_button)
		_expedition_button.pressed.connect(func(): expedition_requested.emit())
		add_child(_expedition_button)
		_autochess_button = Button.new()
		_autochess_button.name = "Autochess"
		_autochess_button.custom_minimum_size = Vector2(138, 46)
		_autochess_button.add_theme_font_size_override("font_size", font_size)
		_plain(_autochess_button)
		_autochess_button.pressed.connect(func(): autochess_requested.emit())
		add_child(_autochess_button)
	_refresh()


## The look shared by the wiki, Expedition and Autochess buttons (the same
## plate as an edition that is not chosen).
func _plain(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	for state: String in ["font_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color(INK, 0.85))
	button.add_theme_color_override("font_hover_color", INK.lightened(0.25))
	button.add_theme_stylebox_override("normal", _plate(0.72, Color(INK, 0.3)))
	button.add_theme_stylebox_override("hover", _plate(0.8, Color(INK, 0.6)))
	button.add_theme_stylebox_override("pressed", _plate(0.88, INK))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _plate(alpha: float, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, alpha)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


## Shows `edition` as chosen and which games can be played.
func show_state(edition: String, playable: Dictionary) -> void:
	current = edition
	available = playable
	_refresh()


func _refresh() -> void:
	for edition: String in buttons:
		var button: Button = buttons[edition]
		var title := ELContentLibrary.title(edition)
		button.text = title if available.has(edition) else title + "\nnot installed — add…"
		button.tooltip_text = ("Play " + title) if available.has(edition) else ("Add your copy of " + title)
		button.set_pressed_no_signal(edition == current)
	if wiki_button != null:
		var russian := ELWikiScreen.remembered_language(wiki_hint) == "ru"
		wiki_button.text = "Вики" if russian else "Wiki"
		wiki_button.tooltip_text = "Справка по игре на движке Demiurges (F6)" if russian else "How to play on the Demiurges engine (F6)"
		if _expedition_button != null:
			_expedition_button.text = "Экспедиция" if russian else "Expedition"
		if _autochess_button != null:
			_autochess_button.text = "Автошахматы" if russian else "Autochess"
			_autochess_button.tooltip_text = "Девять героев, общий запас существ, бои в реальном времени" if russian else "Nine heroes, one pool of creatures, real-time battles"


func _chosen(edition: String) -> void:
	if not available.has(edition):
		_refresh()
		missing.emit(edition)
		return
	if edition == current:
		_refresh()
		return
	current = edition
	_refresh()
	selected.emit(edition)
