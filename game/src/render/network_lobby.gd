class_name ELNetworkLobby
extends AcceptDialog
## LAN games can be picked from the session list or joined by address.
signal requested(hosting: bool, address: String, port: int, deck: String, arena: String, resource_level: int, rounds: int, turn_seconds: int, deck_seconds: int)
signal preset_confirmed(deck: String)
signal edit_requested(preset: Dictionary, cap: int)

var lan_mode := false
var _address := LineEdit.new()
var _port := SpinBox.new()
var _decks := OptionButton.new()
var _levels := OptionButton.new()
var _rounds := SpinBox.new()
var _turn_limit: SpinBox
var _deck_limit: SpinBox
var _arenas := OptionButton.new()
var _status := Label.new()
var _fields: VBoxContainer
var _chat: ELNetworkChat
var _host: Button
var _join: Button
var _new_hero: Button
var _edit_hero: Button
var _discovery: ELNetworkDiscovery
var _sessions: ItemList
var _arena_names := {}
var _profile: ELProfile
var _presets: Array[Dictionary] = []
var _host_rules := Vector2i(-1, -1)
var _host_rounds := 1
var _host_turn_seconds := 0
var _host_deck_seconds := 0
var _guest_selecting := false
var _join_caption := ""

func build(profile: ELProfile, lan := false) -> void:
	lan_mode = lan
	_profile = profile
	title = profile.text("CtrlMSLAN" if lan_mode else "CtrlMSTCPIP")
	style_dialog(self, profile, "Multiplayer" if lan_mode else "TCPIPDialog")
	min_size = Vector2i(680, 470 if lan_mode else 360)
	size = min_size
	var fields := VBoxContainer.new()
	_fields = fields
	add_child(fields)
	fields.add_theme_constant_override("separation", 8)
	fields.add_child(heading(title))
	_address.placeholder_text = "IP / DNS"
	_address.text_submitted.connect(func(_value: String): _request(&"join"))
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = ELNetworkDuel.PORT
	_rounds.min_value = 1
	_rounds.max_value = ELDuelMatch.MAX_ROUNDS
	_rounds.value = 1
	_decks.fit_to_longest_item = false
	_decks.clip_text = true
	_load_presets()
	var levels := ELDuelCosts.resource_levels(profile)
	for level in range(levels.x, levels.y + 1):
		_levels.add_item(str(level), level)
	_levels.item_selected.connect(func(_index: int):
		_filter_presets()
		_update_buttons(false))
	_filter_presets()
	_arenas.fit_to_longest_item = false
	_arenas.clip_text = true
	for id: String in ELDuelMatch.arenas(profile):
		var arena_name := profile.text(str(profile.table("ScenesNames")[id].get("ELKName", id)))
		_arenas.add_item(arena_name)
		_arenas.set_item_metadata(_arenas.item_count - 1, id)
		_arena_names[id] = arena_name
	if lan_mode:
		_discovery = ELNetworkDiscovery.new()
		fields.add_child(heading(ELRemakeText.t("LAN games", profile), false))
		_sessions = ItemList.new()
		_sessions.name = "LANMatches"
		_sessions.custom_minimum_size.y = 90
		_sessions.add_theme_constant_override("v_separation", 5)
		_sessions.allow_reselect = true
		_sessions.item_selected.connect(_select_session)
		_sessions.item_activated.connect(func(index: int):
			if _join.disabled: return
			_select_session(index)
			_request(&"join"))
		fields.add_child(_sessions)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	fields.add_child(columns)
	var setup := group(columns, profile.text("CtrlMuCreateHost" if lan_mode else "CtrlTCPCreate"))
	var connection := group(columns, profile.text("CtrlMuJoin" if lan_mode else "CtrlTCPJoin"))
	_field(setup, "Resource cap", _levels)
	_field(setup, "Rounds", _rounds)
	if profile.id == "el2":
		_turn_limit = _time_field(setup, "Turn limit (s)")
		_deck_limit = _time_field(setup, "Deck change (s)")
	_field(setup, "Host arena", _arenas)
	_field(connection, profile.text("CtrlTCPStatic2"), _address)
	_field(connection, "UDP port", _port)
	# The same selection is used when creating the duel or accepting an offer.
	_field(connection, "Hero preset", _decks)
	if profile.id == "el2":
		var editor_buttons := HBoxContainer.new()
		editor_buttons.alignment = BoxContainer.ALIGNMENT_END
		connection.add_child(editor_buttons)
		_new_hero = Button.new()
		_new_hero.text = ELRemakeText.t("New hero", profile)
		_new_hero.pressed.connect(_request_editor.bind(true))
		editor_buttons.add_child(_new_hero)
		_edit_hero = Button.new()
		_edit_hero.text = ELRemakeText.t("Edit hero", profile)
		_edit_hero.pressed.connect(_request_editor.bind(false))
		editor_buttons.add_child(_edit_hero)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 38
	_status.size.x = min_size.x - 64
	set_status("Select a LAN duel or enter the host’s address." if lan_mode else "Host a duel, or enter the host’s address to join.")
	fields.add_child(_status)
	_join_caption = profile.text("CtrlMuJoin" if lan_mode else "CtrlTCPJoin")
	_host = add_button(profile.text("CtrlMuCreateHost" if lan_mode else "CtrlTCPCreate"), false, "host")
	_join = add_button(_join_caption, false, "join")
	style_button(_host, profile, "MuCreateHost" if lan_mode else "TCPCreate")
	style_button(_join, profile, "MuJoin" if lan_mode else "TCPJoin")
	get_ok_button().get_parent().move_child(get_ok_button(), 0)
	_host.get_parent().move_child(_host, _join.get_index())
	custom_action.connect(_request)
	set_waiting(false)

func _field(fields: VBoxContainer, caption: String, input: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = ELRemakeText.t(caption, _profile)
	label.custom_minimum_size.x = 120
	row.add_child(label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	fields.add_child(row)

func _time_field(fields: VBoxContainer, caption: String) -> SpinBox:
	var limit := SpinBox.new()
	limit.min_value = 0
	limit.max_value = ELNetworkDuel.MAX_TURN_SECONDS
	limit.tooltip_text = ELRemakeText.t("0 for unlimited, or 10–3600 seconds.", _profile)
	_field(fields, caption, limit)
	return limit

func _request(action: StringName) -> void:
	var hosting := action == &"host"
	if _guest_selecting:
		if not hosting and not _join.disabled: preset_confirmed.emit(_decks.get_selected_metadata())
		return
	if (_host.disabled if hosting else _join.disabled): return
	var address := _address.text.strip_edges()
	if not hosting and address.is_empty():
		set_status("Enter the host’s address.")
		_address.grab_focus()
		return
	var deck := String(_decks.get_selected_metadata()) if hosting else ""
	var arena := String(_arenas.get_selected_metadata()) if hosting else ""
	var seconds := int(_turn_limit.value) if hosting and _turn_limit != null else 0
	var deck_seconds := int(_deck_limit.value) if hosting and _deck_limit != null else 0
	if not ELNetworkDuel.valid_time_limit(_profile, seconds) or not ELNetworkDuel.valid_time_limit(_profile, deck_seconds):
		set_status("Set each time limit to 0 or between 10 and 3600 seconds.")
		return
	requested.emit(hosting, address, int(_port.value), deck, arena, _levels.get_selected_id(), int(_rounds.value), seconds, deck_seconds)

func set_status(message: String) -> void:
	_status.text = ELRemakeText.t(message, _profile)

func set_waiting(waiting: bool) -> void:
	if not waiting and _chat != null:
		_chat.hide()
		_chat.queue_free()
		_chat = null
	if not waiting and _host_rules.x >= 0:
		_levels.select(_host_rules.x)
		_arenas.select(_host_rules.y)
		_rounds.value = _host_rounds
		if _turn_limit != null: _turn_limit.value = _host_turn_seconds
		if _deck_limit != null: _deck_limit.value = _host_deck_seconds
		_host_rules = Vector2i(-1, -1)
		_filter_presets()
	_guest_selecting = false
	_join.text = _join_caption
	_update_buttons(waiting)
	_decks.disabled = waiting
	_update_editor_buttons()
	_levels.disabled = waiting
	_rounds.editable = not waiting
	if _turn_limit != null: _turn_limit.editable = not waiting
	if _deck_limit != null: _deck_limit.editable = not waiting
	_arenas.disabled = waiting
	_address.editable = not waiting
	_port.editable = not waiting
	if _discovery == null: return
	if waiting:
		_discovery.close()
		_sessions.clear()
		set_process(false)
	else:
		var listening := _discovery.browse(ELNetworkDuel.VERSION, _profile.id, ELDuelCosts.resource_levels(_profile).y) == OK
		set_process(listening)
		if not listening: set_status("LAN discovery unavailable. You can join by address.")

func show_chat(link: ELNetworkDuel) -> void:
	if _chat != null: return
	_chat = ELNetworkChat.new()
	_fields.add_child(_chat)
	_chat.build(link)

func show_offer(resource_level: int, arena: String, rounds: int, turn_seconds: int, deck_seconds: int) -> void:
	_host_rules = Vector2i(_levels.selected, _arenas.selected)
	_host_rounds = int(_rounds.value)
	_levels.select(_levels.get_item_index(resource_level))
	_rounds.value = rounds
	if _turn_limit != null:
		_host_turn_seconds = int(_turn_limit.value)
		_turn_limit.value = turn_seconds
	if _deck_limit != null:
		_host_deck_seconds = int(_deck_limit.value)
		_deck_limit.value = deck_seconds
	for index in _arenas.item_count:
		if _arenas.get_item_metadata(index) == arena:
			_arenas.select(index)
			break
	_filter_presets()
	_guest_selecting = true
	_decks.disabled = false
	_update_editor_buttons()
	_join.text = ELRemakeText.t("Ready", _profile)
	_join.disabled = _decks.item_count == 0
	if _join.disabled: set_status("No hero preset fits the host’s resource cap.")
	else: _status.text = ELRemakeText.t("Host’s resource cap is %d. Choose a hero and press Ready.", _profile) % resource_level

func _load_presets() -> void:
	_presets.assign(ELDuelPresets.shipped(_profile) + ELDuelPresets.load_user(_profile))

func reload_presets(saved_id: String) -> void:
	_load_presets()
	_filter_presets(saved_id)
	_update_buttons(_levels.disabled)
	if _guest_selecting: _join.disabled = _decks.item_count == 0

func _request_editor(new_hero: bool) -> void:
	if _decks.disabled: return
	var cap := _levels.get_selected_id()
	var selected := ELDuelPresets.find(_presets, str(_decks.get_selected_metadata()))
	if new_hero:
		selected = ELDuelPresets.blank(str(selected.get("faction", "Red")), cap)
	if not selected.is_empty(): edit_requested.emit(selected, cap)

func _update_editor_buttons() -> void:
	if _new_hero == null: return
	_new_hero.disabled = _decks.disabled
	_edit_hero.disabled = _decks.disabled or _decks.item_count == 0

func _filter_presets(saved_id := "") -> void:
	var selected: Variant = _decks.get_selected_metadata() if saved_id.is_empty() else saved_id
	var cap := _levels.get_selected_id()
	_decks.clear()
	for preset: Dictionary in _presets:
		if not ELDuelMatch.side_valid(_presets, preset, cap): continue
		_decks.add_item("%s [%d]" % [preset.name, preset.resource_level])
		var index := _decks.item_count - 1
		_decks.set_item_metadata(index, preset.id)
		if preset.id == selected: _decks.select(index)
	_update_editor_buttons()

func _update_buttons(waiting: bool) -> void:
	_host.disabled = waiting or _decks.item_count == 0 or _arenas.item_count == 0
	_join.disabled = waiting

func _process(_delta: float) -> void:
	if _discovery == null or not _discovery.poll(): return
	var selected := _sessions.get_selected_items()
	var selection: Variant = _sessions.get_item_metadata(selected[0]) if not selected.is_empty() else null
	_sessions.clear()
	for id: String in _discovery.sessions:
		var session: Dictionary = _discovery.sessions[id]
		if not _arena_names.has(session.location): continue
		_sessions.add_item("%s [%d]  —  %s:%d" % [_arena_names[session.location], session.detail, session.address, session.port])
		var index := _sessions.item_count - 1
		_sessions.set_item_metadata(index, id)
		if id == selection: _sessions.select(index)

func _select_session(index: int) -> void:
	var session: Dictionary = _discovery.sessions.get(_sessions.get_item_metadata(index), {})
	if session.is_empty(): return
	_address.text = session.address
	_port.value = session.port

func _exit_tree() -> void:
	if _discovery != null: _discovery.close()

static func heading(value: String, centered := true) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_color_override("font_color", ELFrontMenu.INK_HOVER)
	return label

static func group(parent: HBoxContainer, caption: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(heading(caption, false))
	return column

## The panel edges and buttons come from the original Cuts tables. The middle
## is resized to leave room for the remake's connection and match settings.
static func style_dialog(dialog: AcceptDialog, profile: ELProfile, panel: String) -> void:
	dialog.exclusive = true
	dialog.borderless = true
	dialog.theme = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	font.font_weight = 700
	dialog.theme.default_font = font
	dialog.theme.default_font_size = 16
	var picture := _panel_image(profile, panel)
	var list_art: Texture2D
	var margin := 42 if panel == "StrategicScreen" else 24
	var background: StyleBox = _field_style(Color("1a1e19"))
	if picture != null:
		var inside := Rect2i(margin, 24, picture.get_width() - 2 * margin, picture.get_height() - 48)
		if panel == "Multiplayer":
			list_art = ImageTexture.create_from_image(picture.get_region(Rect2i(24, 75, 752, 104)))
		if panel == "StrategicScreen":
			picture.fill_rect(inside, Color("20241f"))
		else:
			var swatch := Rect2i(margin, 165, inside.size.x, 170) if panel == "TCPIPDialog" else Rect2i(margin, 523, inside.size.x, 52)
			var fill := picture.get_region(swatch)
			fill.resize(inside.size.x, inside.size.y, Image.INTERPOLATE_BILINEAR)
			picture.blit_rect(fill, Rect2i(Vector2i.ZERO, inside.size), inside.position)
		var frame := StyleBoxTexture.new()
		frame.texture = ImageTexture.create_from_image(picture)
		frame.set_texture_margin_all(margin)
		frame.texture_margin_top = 24
		frame.texture_margin_bottom = 24
		background = frame
	background.content_margin_left = margin + 8
	background.content_margin_right = margin + 8
	background.content_margin_top = 7
	background.content_margin_bottom = 26
	dialog.theme.set_stylebox("panel", "AcceptDialog", background)
	var field := _field_style(Color("131613"))
	for type: String in ["LineEdit", "ItemList", "PopupMenu", "PanelContainer"]:
		dialog.theme.set_stylebox("normal" if type == "LineEdit" else "panel", type, field)
	if list_art != null:
		var list := StyleBoxTexture.new()
		list.texture = list_art
		list.set_content_margin_all(4)
		dialog.theme.set_stylebox("panel", "ItemList", list)
	for type: String in ["Button", "OptionButton"]:
		dialog.theme.set_stylebox("normal", type, field)
		dialog.theme.set_stylebox("hover", type, _field_style(Color("373329")))
		dialog.theme.set_stylebox("pressed", type, _field_style(Color("493c2a")))
		dialog.theme.set_stylebox("disabled", type, _field_style(Color("191c19")))
	for type: String in ["Label", "Button", "OptionButton", "ItemList", "LineEdit", "PopupMenu"]:
		dialog.theme.set_color("font_color", type, ELFrontMenu.BODY_INK)
	dialog.theme.set_stylebox("selected", "ItemList", _field_style(Color("493c2a")))
	dialog.theme.set_stylebox("selected_focus", "ItemList", _field_style(Color("493c2a")))
	dialog.theme.set_color("font_placeholder_color", "LineEdit", Color("a59a85"))
	var back := dialog.get_ok_button()
	back.text = ""
	back.tooltip_text = ELRemakeText.t("Back", profile)
	style_button(back, profile, "TCPBack" if panel == "TCPIPDialog" else "MuBack")

static func _field_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("625340")
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	return style

static func _panel_image(profile: ELProfile, panel: String) -> Image:
	var bounds := Rect2i(250, 109, 300, 382) if panel == "TCPIPDialog" else Rect2i(0, 0, 800, 600)
	var picture := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	picture.fill(Color("1a1e19"))
	var pieces := 0
	var paths := _texture_paths(profile)
	for row: Dictionary in profile.table("CutParts").values():
		if row.get("Ctrl") != panel or str(row.Txt).begins_with("_MAIN_PANEL_"): continue
		var texture := profile.texture(str(paths.get(row.Txt, "")))
		if texture == null: continue
		var sheet := texture.get_image()
		sheet.convert(Image.FORMAT_RGBA8)
		picture.blit_rect(sheet, Rect2i(row.TxtL, row.TxtT, row.TxtW, row.TxtH), Vector2i(row.ScrL, row.ScrT) - bounds.position)
		pieces += 1
	return picture if pieces > 0 else null

static func _texture_paths(profile: ELProfile) -> Dictionary:
	var paths := {}
	for row: Dictionary in profile.table("InterfaceTextures").values():
		paths[row.Name] = "Interface/" + str(row.Path).replace("\\", "/")
	return paths

static func style_button(button: Button, profile: ELProfile, control: String) -> void:
	var paths := _texture_paths(profile)
	var normal: StyleBoxTexture
	var cut := Rect2()
	var glow: Dictionary
	for row: Dictionary in profile.table("CutParts").values():
		if row.get("Ctrl") != control: continue
		var mask: Variant = row.get("Msk", "")
		if mask is Array:
			if "Light" in mask and "Free" in mask: glow = row
			continue
		if mask not in ["Free", "Push"]: continue
		var texture := profile.texture(str(paths.get(row.Txt, "")))
		if texture == null: continue
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.region_rect = Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH)
		style.set_content_margin_all(6)
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		var text_width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		style.content_margin_left = maxf(6.0, (float(row.TxtW) - text_width) * 0.5)
		style.content_margin_right = style.content_margin_left
		button.add_theme_stylebox_override("normal" if mask == "Free" else "pressed", style)
		if mask == "Free":
			normal = style
			cut = Rect2(row.ScrL, row.ScrT, row.TxtW, row.TxtH)
	if normal == null:
		if button.text.is_empty(): button.text = button.tooltip_text
		return
	button.custom_minimum_size = cut.size
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_disabled_color", Color("8c806e"))
	var highlight := normal
	if not glow.is_empty():
		var texture := profile.texture(str(paths.get(glow.Txt, "")))
		if texture != null:
			var blended := normal.texture.get_image().get_region(Rect2i(normal.region_rect))
			var sheet := texture.get_image()
			blended.convert(Image.FORMAT_RGBA8)
			sheet.convert(Image.FORMAT_RGBA8)
			blended.blend_rect(sheet, Rect2i(glow.TxtL, glow.TxtT, glow.TxtW, glow.TxtH), Vector2i(Vector2(glow.ScrL, glow.ScrT) - cut.position))
			highlight = normal.duplicate()
			highlight.texture = ImageTexture.create_from_image(blended)
			highlight.region_rect = Rect2(Vector2.ZERO, cut.size)
	button.add_theme_stylebox_override("hover", highlight)
