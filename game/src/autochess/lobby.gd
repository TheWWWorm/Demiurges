class_name ELAutochessLobby
extends Control
## The autochess landing, after the Cursed Lands autochess: one framed panel
## over the hero's own battlefield, with the mode tabs, the title, how to
## start on the left and the hero's bust and choice on the right. "Play
## online" turns the panel into the online page: host or join, the address,
## and the nine seats.

signal begin(game: ELAutochessMatch, seat: int, online: ELAutochessOnline)
signal left
signal hero_changed(id: String)

const H := preload("res://src/autochess/hud.gd")
const SETTINGS := "user://autochess.cfg"
const SEATS := 9

var profile: ELProfile
var hero := ""
var online: ELAutochessOnline
var _panel: H.Frame
var _body: VBoxContainer
var _bust: ELAutochessBust
var _picker: OptionButton
var _faction: Label
var _seed: LineEdit
var _name: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label
var _roster: VBoxContainer
var _online_page := false
var _join_mode := false
var _choices: Array[String] = []

func _t(text: String) -> String:
	return ELAutochessText.t(profile, text)

func build(data: ELProfile) -> void:
	profile = data
	H.sound_profile = data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var look := Theme.new()
	look.default_font_size = 16
	look.set_color("font_color", "Label", H.PAPER)
	theme = look
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.06, 0.52)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_choices = ELAutochessCharacters.choices(profile)
	var config := ConfigFile.new()
	config.load(SETTINGS)
	hero = ELAutochessCharacters.valid(profile, String(config.get_value("autochess", "hero", _choices[0] if not _choices.is_empty() else "")))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = H.Frame.new()
	_panel.surface = Color(0.035, 0.055, 0.065, 0.96)
	_panel.custom_minimum_size.x = 900
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	margin.add_child(_body)
	_name = _edit(String(config.get_value("autochess", "name", _default_name())), 24)
	_address = _edit(String(config.get_value("autochess", "address", "")), 120)
	_address.placeholder_text = _t("e.g. 192.168.1.20:%d") % ELAutochessOnline.PORT
	_port = _edit(str(config.get_value("autochess", "port", ELAutochessOnline.PORT)), 5)
	_seed = _edit("", 12)
	_seed.placeholder_text = _t("Random seed")
	_seed.tooltip_text = _t("Optional: enter a whole number to replay the same shops and opponents.")
	_status = H.wrap(null, "", 15, H.GOLD)
	_bust = ELAutochessBust.new()
	_bust.shift = 0.0
	_bust.custom_minimum_size = Vector2(240, 220)
	_bust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_picker = OptionButton.new()
	_picker.custom_minimum_size.y = 40
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.tooltip_text = _t("Your hero represents you on the board and picks the battlefield. It does not change your army.")
	for id: String in _choices:
		_picker.add_icon_item(ELAutochessCharacters.portrait(profile, id), ELAutochessCharacters.title(profile, id))
	var popup := _picker.get_popup()
	popup.add_theme_constant_override("icon_max_width", 36)
	_picker.add_theme_constant_override("icon_max_width", 30)
	_picker.item_selected.connect(func(index: int): _pick(_choices[index]))
	_faction = H.wrap(null, "", 15, H.GOLD)
	_faction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 3)

func _default_name() -> String:
	var user := OS.get_environment("USERNAME")
	if user.is_empty(): user = OS.get_environment("USER")
	return user.left(24) if not user.is_empty() else "Player"

func _edit(text: String, length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.max_length = length
	edit.custom_minimum_size.y = 38
	edit.add_theme_stylebox_override("normal", H.style(Color("141b1c"), Color("4b5143"), Vector2(10, 6)))
	edit.add_theme_stylebox_override("focus", H.style(Color("141b1c"), H.GOLD, Vector2(10, 6)))
	return edit

func open() -> void:
	show()
	_status.text = ""
	_online_page = false
	_rebuild()

func _remember() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("autochess", "hero", hero)
	config.set_value("autochess", "name", _player_name())
	config.set_value("autochess", "address", _address.text.strip_edges())
	config.set_value("autochess", "port", _port_number())
	config.save(SETTINGS)

func _player_name() -> String:
	var value := _name.text.strip_edges()
	return value if not value.is_empty() else "Player"

func _port_number() -> int:
	var value := _port.text.strip_edges()
	return clampi(int(value), 1024, 65535) if value.is_valid_int() else ELAutochessOnline.PORT

# --- Pages ------------------------------------------------------------------

## Detaches the shared widgets, then frees the rest of the page.
func _clear() -> void:
	for keep: Control in [_seed, _name, _address, _port, _status, _bust, _picker, _faction, _roster]:
		if keep.get_parent() != null: keep.get_parent().remove_child(keep)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_clear()
	_build_modes()
	var title := H.wrap(_body, _t("Online autochess") if _online_page else _t("Autochess"), 46, H.PAPER)
	title.add_theme_font_override("font", H.serif())
	_rule(_body)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	_body.add_child(columns)
	var left_column := VBoxContainer.new()
	left_column.custom_minimum_size.x = 320
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 16)
	columns.add_child(left_column)
	if _online_page: _build_online(left_column)
	else: _build_solo(left_column)
	_build_showcase(columns)
	_pick(hero, false)

## The top row: only Back, on the right (the other modes have their own
## entries on the main menu).
func _build_modes() -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := H.button(row, _t("Back"), _back)
	back.custom_minimum_size = Vector2(110, 40)

func _build_solo(column: VBoxContainer) -> void:
	H.wrap(column, _t("Recruit your army"), 28, H.GOLD).add_theme_font_override("font", H.serif())
	H.wrap(column, _t("Recruit creatures from the shared pool and collect three copies to evolve them."), 17, H.PAPER)
	H.wrap(column, _t("Starting ether: %d") % ELAutochessRules.OPENING_ETHER, 24, H.GOLD)
	var saved_round := _saved_round()
	if saved_round > 0:
		var resume := H.button(column, _t("Continue · round %d") % saved_round, _resume, true)
		resume.tooltip_text = _t("Resume with the same army and shop.")
		resume.custom_minimum_size.y = 44
	var toggle := H.button(column, _t("Set seed"), func(): _seed.visible = not _seed.visible)
	toggle.tooltip_text = _seed.tooltip_text
	toggle.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.y = 28
	column.add_child(_seed)
	_seed.visible = not _seed.text.is_empty()
	var start := H.button(column, _t("Start game"), _new, saved_round <= 0)
	start.custom_minimum_size.y = 52
	start.add_theme_font_size_override("font_size", 20)
	if saved_round > 0: start.tooltip_text = _t("Starts a new tournament; the saved one is replaced.")
	var play_online := H.button(column, _t("Play online"), func():
		_online_page = true
		_join_mode = false
		_rebuild())
	play_online.tooltip_text = _t("Host or join a nine-hero tournament. Computers fill empty seats.")
	play_online.custom_minimum_size.y = 44
	column.add_child(_status)

func _build_online(column: VBoxContainer) -> void:
	var connected := online != null
	H.wrap(column, _t("Host or join a nine-hero tournament. Computers fill empty seats."), 16, H.MUTED)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for index in 2:
		var tab := H.button(tabs, _t("Host") if index == 0 else _t("Join"), func():
			if connected: return
			_join_mode = index == 1
			_rebuild())
		tab.toggle_mode = true
		tab.set_pressed_no_signal(_join_mode == (index == 1))
		tab.disabled = connected and _join_mode != (index == 1)
		tab.custom_minimum_size = Vector2(140, 40)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_stylebox_override("pressed", H.style(Color("424033"), H.GOLD, Vector2(8, 4)))
		tab.add_theme_stylebox_override("normal", H.style(Color("202726"), Color("4b5143"), Vector2(8, 4)))
	H.wrap(column, _t("Enter a friend's address and compete with your own army.") if _join_mode else _t("Create a tournament and share your address with friends."), 15, H.PAPER)
	_field(column, _t("Your name"), _name)
	if _join_mode: _field(column, _t("Host's address"), _address)
	else: _field(column, _t("Port"), _port)
	for edit: LineEdit in [_name, _address, _port]: edit.editable = not connected
	if not connected:
		var action := H.button(column, _t("Join") if _join_mode else _t("Start hosting"), _join if _join_mode else _host, true)
		action.custom_minimum_size.y = 48
		action.add_theme_font_size_override("font_size", 19)
	else:
		if online.is_host:
			var addresses := PackedStringArray()
			for address: String in IP.get_local_addresses():
				if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."): addresses.append("%s:%d" % [address, _port_number()])
			H.wrap(column, _t("Friends join with:") + "\n" + ("\n".join(addresses) if not addresses.is_empty() else _t("No network address found.")), 15, H.GOLD)
			var start := H.button(column, _t("Start game"), _start_hosted, true)
			start.custom_minimum_size.y = 52
			start.add_theme_font_size_override("font_size", 20)
		else:
			H.wrap(column, _t("Connected. Waiting for the host to start the game."), 15, H.PAPER)
		H.button(column, _t("Leave"), func():
			_close_online()
			_rebuild())
	column.add_child(_status)

func _field(column: VBoxContainer, caption: String, edit: LineEdit) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	column.add_child(row)
	H.label(row, caption, 14, H.GOLD)
	row.add_child(edit)

func _build_showcase(columns: HBoxContainer) -> void:
	var showcase := VBoxContainer.new()
	showcase.custom_minimum_size.x = 330
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.add_theme_constant_override("separation", 8)
	columns.add_child(showcase)
	var heading := H.label(showcase, _t("Choose your hero"), 24, H.GOLD, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bust.custom_minimum_size = Vector2(330, 170) if _online_page else Vector2(330, 220)
	showcase.add_child(_bust)
	showcase.add_child(_picker)
	_picker.disabled = online != null
	showcase.add_child(_faction)
	_rule(showcase)
	if _online_page:
		_roster_rows()
		showcase.add_child(_roster)
		return
	var facts := H.wrap(showcase, _t("Face eight other heroes. The last hero standing wins."), 16, H.PAPER)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var help := H.wrap(showcase, _t("Start with %d health. Fight neutral creatures in rounds 1–3 and every fifth round, and other heroes in between.") % ELAutochessRules.START_HEALTH, 14, H.MUTED)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _rule(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = Color(H.GOLD, 0.35)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

## The nine seats: joined players with their heroes, the rest computers.
func _roster_rows() -> void:
	for child: Node in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	var rows: Array = online.lobby if online != null else []
	H.label(_roster, _t("Players: %d / %d") % [maxi(1, rows.size()), SEATS], 16, H.PAPER)
	for seat in SEATS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		_roster.add_child(line)
		var member: Dictionary = rows[seat] if seat < rows.size() else {}
		if seat == 0 and member.is_empty(): member = {"name": _player_name(), "character": hero}
		var picture := TextureRect.new()
		picture.custom_minimum_size = Vector2(26, 20)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.texture = ELAutochessCharacters.portrait(profile, String(member.character)) if not member.is_empty() else null
		line.add_child(picture)
		var name := H.label(line, "%d. %s" % [seat + 1, String(member.name) if not member.is_empty() else _t("Computer")], 14, Color("f2b36f") if not member.is_empty() else H.MUTED)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		if not member.is_empty(): H.label(line, ELAutochessCharacters.title(profile, String(member.character)), 13, H.MUTED)

func _pick(id: String, announce := true) -> void:
	if id.is_empty(): return
	hero = id
	_picker.select(_choices.find(id))
	_bust.show_hero(profile, id)
	var faction := String({"Red": "chaots", "Blue": "kinets", "Green": "vitals", "Black": "synthets"}.get(ELAutochessCharacters.color(profile, id), ""))
	_faction.text = _t(String(ELAutochessAlliances.RULES[faction].name)) if ELAutochessAlliances.RULES.has(faction) else ""
	_faction.add_theme_color_override("font_color", H.FACTION.get(ELAutochessCharacters.color(profile, id), H.GOLD))
	hero_changed.emit(id)
	if announce:
		H.play_sound("Buttons/ChooseHero.wav")
		_remember()
		if online != null: _roster_rows()

func _saved_round() -> int:
	if not ELAutochessMatch.has_save(): return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ELAutochessMatch.SAVE_PATH))
	return maxi(1, int(parsed.get("round", 1))) if parsed is Dictionary else 0

# --- Actions ----------------------------------------------------------------

func _seed_value() -> int:
	var text := _seed.text.strip_edges()
	if text.is_valid_int(): return int(text) & 0x7fffffff
	return randi() & 0x7fffffff

func _new() -> void:
	if not _seed.text.strip_edges().is_empty() and not _seed.text.strip_edges().is_valid_int():
		_status.text = _t("Enter a whole number for the seed.")
		return
	_remember()
	var game := ELAutochessMatch.new()
	var names: Array[String] = [_player_name()]
	game.begin(profile, _seed_value(), hero, [], names)
	begin.emit(game, 0, null)

func _resume() -> void:
	var game := ELAutochessMatch.new()
	if not game.load_saved(profile):
		_status.text = _t("The saved tournament could not be read.")
		ELAutochessMatch.delete_save()
		_rebuild()
		return
	begin.emit(game, 0, null)

func _host() -> void:
	_close_online()
	_remember()
	online = ELAutochessOnline.new()
	_connect_online()
	if online.host(profile, _port_number(), _player_name(), hero) != OK:
		_status.text = _t("Could not host on port %d.") % _port_number()
		online = null
	_rebuild()

func _join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		_status.text = _t("Enter the host's address.")
		return
	_close_online()
	_remember()
	var port := ELAutochessOnline.PORT
	if address.contains(":") and address.get_slice(":", 1).is_valid_int():
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	online = ELAutochessOnline.new()
	_connect_online()
	if online.join(profile, address, port, _player_name(), hero) != OK:
		_status.text = _t("Could not connect.")
		online = null
	else: _status.text = _t("Connecting…")
	_rebuild()

func _connect_online() -> void:
	online.message.connect(func(text: String): _status.text = _t(text))
	online.lobby_changed.connect(_roster_rows)
	online.closed.connect(func(reason: String):
		_status.text = _t(reason)
		online = null
		if visible and _online_page: _rebuild())
	online.started.connect(func(game: ELAutochessMatch, seat: int): begin.emit(game, seat, online))

func _start_hosted() -> void:
	if online == null or not online.is_host: return
	online.start_match(_seed_value())

func _close_online() -> void:
	if online != null: online.close()
	online = null

func _back() -> void:
	if _online_page:
		_close_online()
		_online_page = false
		_status.text = ""
		_rebuild()
		return
	left.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if online != null and online.game == null: online.poll(delta)
