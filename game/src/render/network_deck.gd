class_name ELNetworkDeck
extends AcceptDialog
## A round draft exchanges an active slot with one of the preset's owned spells.

var _link: ELNetworkDuel
var _active := ItemList.new()
var _reserve := ItemList.new()
var _swap := Button.new()
var _message := Label.new()
var _time := Label.new()

func build(link: ELNetworkDuel) -> void:
	_link = link
	title = tr("Change deck")
	exclusive = true
	min_size = Vector2i(620, 440)
	get_ok_button().text = tr("Back to score")
	var body := VBoxContainer.new()
	add_child(body)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_list_column(columns, _active, tr("Active deck"))
	_list_column(columns, _reserve, tr("Reserve"))
	_swap.text = tr("Swap selected spells")
	_swap.pressed.connect(_exchange)
	body.add_child(_swap)
	_message.custom_minimum_size = Vector2(570, 38)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.text = tr("Select a spell in each column to swap them.")
	body.add_child(_message)
	body.add_child(_time)
	_refresh()
	show_time(_link.deck_time_remaining())

func _list_column(parent: Control, list: ItemList, caption: String) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var header := Label.new()
	header.text = caption
	column.add_child(header)
	list.fixed_icon_size = Vector2i(26, 26)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(_index: int): _update_swap())
	column.add_child(list)

func _refresh() -> void:
	var preset := _link.round_preset()
	_active.clear()
	_reserve.clear()
	for code: String in preset.cards:
		_active.add_item(_link.duel.card_name(code), _link.profile.card_icon(code))
	var codes: Array = preset.reserve.keys().filter(func(code: String): return int(preset.reserve[code]) > 0)
	codes.sort_custom(func(a: String, b: String): return _link.duel.card_name(a).nocasecmp_to(_link.duel.card_name(b)) < 0)
	for code: String in codes:
		var index := _reserve.add_item("%s ×%d" % [_link.duel.card_name(code), preset.reserve[code]], _link.profile.card_icon(code))
		_reserve.set_item_metadata(index, code)
	_update_swap()

func _update_swap() -> void:
	_swap.disabled = not _active.is_anything_selected() or not _reserve.is_anything_selected()

func _exchange() -> void:
	if _swap.disabled: return
	var code := String(_reserve.get_item_metadata(_reserve.get_selected_items()[0]))
	if not _link.swap_round_spell(_active.get_selected_items()[0], code):
		_message.text = tr("That swap is unavailable. A deck can hold at most four copies of a spell.")
		return
	_message.text = tr("Swap staged for the next round.")
	_refresh()

func show_time(seconds: int) -> void:
	_time.visible = seconds >= 0
	if _time.visible: _time.text = tr("Deck change time left  %02d:%02d") % [seconds / 60, seconds % 60]
