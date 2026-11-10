class_name ELStrategicLobby
extends AcceptDialog
## LAN and direct-address setup for two human seats on an authored first-game map.
signal requested(hosting: bool, address: String, port: int, map_id: String, players: Vector2i, difficulty: int)
signal load_requested

const DEFAULT_DIFFICULTY := 2
const MINIMUM_SIZE := Vector2i(480, 345)
const INSTRUCTIONS := "Host a map for one guest, or enter the host’s address to join."
const LAN_INSTRUCTIONS := "Host a map, select a waiting LAN game, or enter the host’s address."

var _maps := OptionButton.new()
var _map_details := Label.new()
var _host_seat := OptionButton.new()
var _guest_seat := OptionButton.new()
var _difficulty := OptionButton.new()
var _turn_seconds := SpinBox.new()
var _combat_seconds := SpinBox.new()
var _address := LineEdit.new()
var _port := LineEdit.new()
var _status := Label.new()
var _host: Button
var _join: Button
var _load: Button
var _sessions: OptionButton
var _discovery: ELNetworkDiscovery
var _map_titles := {}
var _seats := Vector2i.ZERO
var _waiting := false
var save_path := ""
var pending_save := {}

func _exit_tree() -> void:
	if _discovery != null: _discovery.close()
	if not pending_save.is_empty(): pending_save.state.close()

func build(profile: ELProfile, saved_path := "", saved_details := "", lan := false) -> void:
	save_path = saved_path
	title = "Strategic multiplayer preview"
	exclusive = true
	min_size = MINIMUM_SIZE
	get_ok_button().text = "Close"
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 8)
	add_child(fields)
	var new_match := VBoxContainer.new()
	new_match.add_theme_constant_override("separation", 8)
	fields.add_child(new_match)
	new_match.visible = save_path.is_empty()
	if not save_path.is_empty():
		var details := Label.new()
		details.text = saved_details
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fields.add_child(details)

	_maps.name = "StrategicMap"
	_maps.fit_to_longest_item = false
	if save_path.is_empty():
		for entry: Dictionary in catalogue(profile):
			var index := _maps.item_count
			_maps.add_item(entry.title)
			_maps.set_item_metadata(index, entry)
			_maps.set_item_tooltip(index, entry.title)
			_map_titles[entry.id] = entry.title
	_maps.item_selected.connect(_select_map)
	_field(new_match, "Host map", _maps)
	_map_details.add_theme_color_override("font_color", Color("b9b5a7"))
	new_match.add_child(_map_details)

	_host_seat.name = "HostSeat"
	_guest_seat.name = "GuestSeat"
	_host_seat.fit_to_longest_item = false
	_guest_seat.fit_to_longest_item = false
	_host_seat.item_selected.connect(_select_seat.bind(true))
	_guest_seat.item_selected.connect(_select_seat.bind(false))
	_field(new_match, "Host seat", _host_seat)
	_field(new_match, "Guest seat", _guest_seat)
	for difficulty in 5: _difficulty.add_item(str(difficulty + 1), difficulty)
	_difficulty.select(DEFAULT_DIFFICULTY)
	_field(new_match, "Difficulty", _difficulty)
	_turn_seconds.name = "AdventureTimeLimit"
	_turn_seconds.max_value = ELNetworkStrategy.MAX_TURN_SECONDS
	_turn_seconds.suffix = "s"
	_turn_seconds.tooltip_text = ELRemakeText.t("Adventure time limit in seconds. Zero is unlimited.", profile)
	_field(new_match, ELRemakeText.t("Adventure time limit", profile), _turn_seconds)
	_combat_seconds.name = "CombatTimeLimit"
	_combat_seconds.max_value = ELNetworkStrategy.MAX_TURN_SECONDS
	_combat_seconds.suffix = "s"
	_combat_seconds.tooltip_text = ELRemakeText.t("Seconds per attack or defence phase. Zero is unlimited.", profile)
	_field(new_match, ELRemakeText.t("Combat time limit", profile), _combat_seconds)
	new_match.add_child(HSeparator.new())
	if lan and save_path.is_empty():
		_discovery = ELNetworkDiscovery.new(ELNetworkStrategy.DISCOVERY_PORT, ELNetworkStrategy.PROTOCOL)
		_sessions = OptionButton.new()
		_sessions.name = "StrategicLanSessions"
		_sessions.fit_to_longest_item = false
		_sessions.clip_text = true
		_sessions.item_selected.connect(_select_session)
		_field(new_match, "LAN games", _sessions)

	_address.name = "JoinAddress"
	_address.placeholder_text = "Host name or IP address"
	_address.max_length = 253
	_address.text_submitted.connect(func(_value: String): _request(&"join"))
	_port.name = "StrategicPort"
	_port.text = str(ELNetworkStrategy.PORT)
	_port.max_length = 5
	_port.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_field(new_match, "Join address", _address)
	_field(fields, "UDP port", _port)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	# The popup measures the wrapping label before the container lays it out.
	_status.size.x = MINIMUM_SIZE.x - 32
	fields.add_child(_status)
	_host = add_button("Host", true, "host")
	if save_path.is_empty():
		_join = add_button("Join", true, "join")
		_load = add_button("Load", true, "load")
	custom_action.connect(_request)

	if not save_path.is_empty():
		set_status("Host the saved match, then have the guest join again.")
	elif _maps.item_count > 0:
		_select_map(0)
		set_status(LAN_INSTRUCTIONS if lan else INSTRUCTIONS)
	else:
		set_status("No installed maps have two strategic seats. You can still join by address.")
	set_waiting(false)

## The original Strategy picker shares the non-campaign catalogue with Single Mission.
static func catalogue(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != ELNetworkStrategy.EDITION: return result
	for entry: Dictionary in ELSingleScenario.catalog(profile):
		if entry.players.size() < 2 or not ELNetworkStrategy._valid_map_id(entry.id): continue
		var map := ELAdventureMap.new()
		if not map.load_map(profile, entry.id): continue
		var eligible := ELNetworkStrategy.authored_seats(map)
		var seats: Array[Dictionary] = []
		for player: Dictionary in entry.players:
			if not eligible.has(player.id): continue
			eligible.erase(player.id)
			var caption := profile.text(player.name) if not String(player.name).is_empty() else String(player.color)
			seats.append({"id": player.id, "caption": "%d · %s" % [player.id, caption]})
		if seats.size() >= 2:
			result.append({"id": entry.id, "title": ELSingleScenario.title(profile, entry), "seats": seats, "size": Vector2i(map.width, map.height), "seat_count": map.players.size()})
	return result

func _field(fields: VBoxContainer, caption: String, input: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 156
	row.add_child(label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	fields.add_child(row)

func _select_map(index: int) -> void:
	var entry: Dictionary = _maps.get_item_metadata(index)
	_host_seat.clear()
	_guest_seat.clear()
	for seat: Dictionary in entry.seats:
		_host_seat.add_item(seat.caption, seat.id)
		_guest_seat.add_item(seat.caption, seat.id)
	_host_seat.select(0)
	_guest_seat.select(1)
	_seats = Vector2i(_host_seat.get_selected_id(), _guest_seat.get_selected_id())
	var dimensions: Vector2i = entry.size
	_map_details.text = "%d × %d · %d authored seats" % [dimensions.x, dimensions.y, entry.seat_count]

func _select_seat(index: int, hosting: bool) -> void:
	# Choosing the other person's seat swaps the two assignments.
	if hosting and index == _guest_seat.selected:
		_guest_seat.select(_guest_seat.get_item_index(_seats.x))
	elif not hosting and index == _host_seat.selected:
		_host_seat.select(_host_seat.get_item_index(_seats.y))
	_seats = Vector2i(_host_seat.get_selected_id(), _guest_seat.get_selected_id())

func _request(action: StringName) -> void:
	if _waiting: return
	if action == &"load" and save_path.is_empty():
		load_requested.emit()
		return
	if action not in [&"host", &"join"] or (action == &"join" and not save_path.is_empty()): return
	var hosting := action == &"host"
	var address := _address.text.strip_edges()
	if not hosting and address.is_empty():
		set_status("Enter the host’s address.")
		_address.grab_focus()
		return
	var port := int(_port.text)
	if not _port.text.is_valid_int() or port < 1024 or port > 65535:
		set_status("Enter a UDP port from 1024 to 65535.")
		_port.grab_focus()
		return
	if hosting:
		if not save_path.is_empty():
			requested.emit(true, "", port, "", Vector2i.ZERO, DEFAULT_DIFFICULTY)
			return
		if _maps.selected < 0 or _seats.x == _seats.y: return
		var entry: Dictionary = _maps.get_selected_metadata()
		requested.emit(true, "", port, entry.id, _seats, _difficulty.get_selected_id())
	else:
		requested.emit(false, address, port, "", Vector2i.ZERO, DEFAULT_DIFFICULTY)

func set_status(message: String) -> void:
	_status.text = message

func set_waiting(waiting: bool) -> void:
	_waiting = waiting
	var no_maps := _maps.item_count == 0
	_host.disabled = waiting or (no_maps and save_path.is_empty())
	if _join != null: _join.disabled = waiting
	if _load != null: _load.disabled = waiting
	for control: OptionButton in [_maps, _host_seat, _guest_seat, _difficulty]:
		control.disabled = waiting or no_maps
	_address.editable = not waiting
	_port.editable = not waiting
	_turn_seconds.editable = not waiting and not no_maps
	_combat_seconds.editable = not waiting and not no_maps
	if _discovery == null: return
	_discovery.close()
	_sessions.disabled = waiting
	_refresh_sessions()
	var listening := not waiting and _discovery.browse(ELNetworkStrategy.VERSION, ELNetworkStrategy.EDITION, ELNetworkStrategy.MAX_DAY) == OK
	set_process(listening)
	if not waiting and not listening: set_status("LAN discovery unavailable. You can join by address.")

func _process(_delta: float) -> void:
	if _discovery != null and _discovery.poll(): _refresh_sessions()

func _refresh_sessions() -> void:
	var selected: Variant = _sessions.get_selected_metadata()
	_sessions.clear()
	_sessions.add_item(tr("No waiting LAN games"))
	for id: String in _discovery.sessions:
		var session: Dictionary = _discovery.sessions[id]
		if not _map_titles.has(session.location): continue
		var caption := tr("%s · Day %d · %s:%d") % [_map_titles[session.location], session.detail, session.address, session.port]
		_sessions.add_item(caption)
		var index := _sessions.item_count - 1
		_sessions.set_item_metadata(index, id)
		_sessions.set_item_tooltip(index, caption)
		if id == selected: _sessions.select(index)
	if _sessions.item_count > 1: _sessions.set_item_text(0, tr("Choose a LAN game…"))

func _select_session(index: int) -> void:
	var session: Dictionary = _discovery.sessions.get(_sessions.get_item_metadata(index), {})
	if session.is_empty(): return
	_address.text = session.address
	_port.text = str(session.port)

func turn_limit() -> int:
	_turn_seconds.apply()
	return int(_turn_seconds.value)

func combat_limit() -> int:
	_combat_seconds.apply()
	return int(_combat_seconds.value)
