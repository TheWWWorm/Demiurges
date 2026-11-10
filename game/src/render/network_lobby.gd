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

func build(profile: ELProfile, lan := false) -> void:
	lan_mode = lan
	_profile = profile
	title = "LAN duel" if lan_mode else "Network duel"
	exclusive = true
	min_size = Vector2i(420, 406 if lan_mode else 293)
	get_ok_button().text = "Close"
	var fields := VBoxContainer.new()
	_fields = fields
	add_child(fields)
	_address.placeholder_text = "Host name or IP address"
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = ELNetworkDuel.PORT
	_rounds.min_value = 1
	_rounds.max_value = ELDuelMatch.MAX_ROUNDS
	_rounds.value = 1
	_decks.fit_to_longest_item = false
	_load_presets()
	var levels := ELDuelCosts.resource_levels(profile)
	for level in range(levels.x, levels.y + 1):
		_levels.add_item(str(level), level)
	_levels.item_selected.connect(func(_index: int):
		_filter_presets()
		_update_buttons(false))
	_filter_presets()
	_arenas.fit_to_longest_item = false
	for id: String in ELDuelMatch.arenas(profile):
		var arena_name := profile.text(str(profile.table("ScenesNames")[id].get("ELKName", id)))
		_arenas.add_item(arena_name)
		_arenas.set_item_metadata(_arenas.item_count - 1, id)
		_arena_names[id] = arena_name
	if lan_mode:
		_discovery = ELNetworkDiscovery.new()
		var label := Label.new()
		label.text = "Waiting LAN duels"
		fields.add_child(label)
		_sessions = ItemList.new()
		_sessions.name = "LANMatches"
		_sessions.custom_minimum_size.y = 90
		_sessions.allow_reselect = true
		_sessions.item_selected.connect(_select_session)
		_sessions.item_activated.connect(func(index: int):
			if _join.disabled: return
			_select_session(index)
			_request(&"join"))
		fields.add_child(_sessions)
	_field(fields, "Resource cap", _levels)
	_field(fields, "Rounds", _rounds)
	if profile.id == "el2":
		_turn_limit = _time_field(fields, tr("Turn limit (s)"))
		_deck_limit = _time_field(fields, tr("Deck change (s)"))
	_field(fields, "Hero preset", _decks)
	if profile.id == "el2":
		var editor_buttons := HBoxContainer.new()
		editor_buttons.alignment = BoxContainer.ALIGNMENT_END
		fields.add_child(editor_buttons)
		_new_hero = Button.new()
		_new_hero.text = tr("New hero")
		_new_hero.pressed.connect(_request_editor.bind(true))
		editor_buttons.add_child(_new_hero)
		_edit_hero = Button.new()
		_edit_hero.text = tr("Edit hero")
		_edit_hero.pressed.connect(_request_editor.bind(false))
		editor_buttons.add_child(_edit_hero)
	_field(fields, "Host arena", _arenas)
	_field(fields, "Join address", _address)
	_field(fields, "UDP port", _port)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 46)
	_status.text = "Select a LAN duel or enter the host’s address." if lan_mode else "Host a duel, or enter the host’s address to join."
	fields.add_child(_status)
	_host = add_button("Host", true, "host")
	_join = add_button("Join", true, "join")
	custom_action.connect(_request)
	set_waiting(false)

func _field(fields: VBoxContainer, caption: String, input: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 120
	row.add_child(label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	fields.add_child(row)

func _time_field(fields: VBoxContainer, caption: String) -> SpinBox:
	var limit := SpinBox.new()
	limit.min_value = 0
	limit.max_value = ELNetworkDuel.MAX_TURN_SECONDS
	limit.tooltip_text = tr("0 for unlimited, or 10–3600 seconds.")
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
		set_status(tr("Set each time limit to 0 or between 10 and 3600 seconds."))
		return
	requested.emit(hosting, address, int(_port.value), deck, arena, _levels.get_selected_id(), int(_rounds.value), seconds, deck_seconds)

func set_status(message: String) -> void:
	_status.text = message

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
	_join.text = "Join"
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
	_join.text = "Ready"
	_join.disabled = _decks.item_count == 0
	set_status("Host’s resource cap is %d. Choose a hero and press Ready." % resource_level if not _join.disabled else "No hero preset fits the host’s resource cap.")

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
