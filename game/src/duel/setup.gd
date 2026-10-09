class_name ELDuelSetup
extends PanelContainer
signal begin(edition: String, options: Dictionary, mode: int)
signal resume_requested
signal campaign_requested

var profiles: Dictionary
var edition: OptionButton
var factions: Array[OptionButton] = []
var levels: Array[SpinBox] = []
var summaries: Array[Label] = []
var spellbooks: Array = [[], []]
var mode: OptionButton
var battlefield: OptionButton
var editor: Window
var library: ItemList
var book: ItemList
var count: Label
var description: Label
var editing_side := 0
var working_cards: Array[String] = []
var library_cards: Array[String] = []
var save_deck_button: Button

func build(available: Dictionary, initial_edition: String, previous: Dictionary = {}) -> void:
	profiles = available
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)
	rows.add_child(_label("ETHERLORDS", 30))
	rows.add_child(_label("Choose your duel", 18))
	edition = OptionButton.new()
	for key: String in profiles:
		edition.add_item(profiles[key].title)
		edition.set_item_metadata(edition.item_count - 1, key)
		if key == initial_edition: edition.select(edition.item_count - 1)
	rows.add_child(edition)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	rows.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size.x = 250
		column.add_theme_constant_override("separation", 9)
		columns.add_child(column)
		column.add_child(_label("Your hero" if side == 0 else "Opponent", 19))
		var faction := OptionButton.new()
		for key: String in ELCatalog.FACTIONS:
			faction.add_item(ELCatalog.FACTIONS[key])
			faction.set_item_metadata(faction.item_count - 1, key)
		column.add_child(faction)
		factions.append(faction)
		var level_row := HBoxContainer.new()
		column.add_child(level_row)
		level_row.add_child(_label("Level", 16))
		var level := SpinBox.new()
		level.min_value = 1
		level.max_value = 15
		level.value = 1
		level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_row.add_child(level)
		levels.append(level)
		var summary := _label("", 14)
		column.add_child(summary)
		summaries.append(summary)
		var edit := Button.new()
		edit.text = "Edit spellbook…"
		edit.pressed.connect(_edit_deck.bind(side))
		column.add_child(edit)
		faction.item_selected.connect(func(_index: int): _reset_deck(side))
	battlefield = OptionButton.new()
	battlefield.tooltip_text = "Battlefield"
	rows.add_child(battlefield)
	_reset_arenas(String(previous.get("arena", "Green.001")))
	# Practice is against the computer; two-player play is the HotSeat duel.
	mode = OptionButton.new()
	mode.add_item("Play against computer")
	mode.visible = false
	rows.add_child(mode)
	var start := Button.new()
	start.text = "Begin duel"
	start.custom_minimum_size.y = 46
	start.pressed.connect(_begin)
	rows.add_child(start)
	var campaign := Button.new()
	campaign.text = "Campaigns…"
	campaign.pressed.connect(func(): campaign_requested.emit())
	rows.add_child(campaign)
	var resume := Button.new()
	resume.text = "Resume saved duel"
	resume.disabled = not FileAccess.file_exists("user://duel-save.json")
	resume.pressed.connect(func(): resume_requested.emit())
	rows.add_child(resume)
	var cancel := Button.new()
	cancel.text = "Return to current duel"
	cancel.pressed.connect(hide)
	rows.add_child(cancel)
	edition.item_selected.connect(func(_index: int):
		_reset_arenas()
		for side in 2: _reset_deck(side))
	for side in 2:
		var choice: Dictionary = previous.get("players", [{}, {}])[side]
		var wanted := String(choice.get("faction", "Red" if side == 0 else "Black"))
		for i in factions[side].item_count:
			if factions[side].get_item_metadata(i) == wanted: factions[side].select(i)
		_reset_deck(side)
		levels[side].value = choice.get("level", 1)
		if choice.has("cards"):
			spellbooks[side] = choice.cards.duplicate()
			_summary(side)

func _profile() -> ELProfile:
	return profiles[edition.get_selected_metadata()]

func _reset_arenas(wanted := "Green.001") -> void:
	battlefield.clear()
	for id: String in _profile().table("CombatSceneDB"):
		battlefield.add_item(ELArena.title(id))
		battlefield.set_item_metadata(battlefield.item_count - 1, id)
		if id == wanted: battlefield.select(battlefield.item_count - 1)

func _faction(side: int) -> String:
	return factions[side].get_selected_metadata()

func _reset_deck(side: int) -> void:
	spellbooks[side] = ELCatalog.deck(_profile(), ELCatalog.STARTERS[_faction(side)])
	_summary(side)

func _summary(side: int) -> void:
	var creatures := 0
	for card: String in spellbooks[side]:
		if _profile().table("CombatCreatures").has(card): creatures += 1
	summaries[side].text = "%d spells · %d summons" % [spellbooks[side].size(), creatures]

func _begin() -> void:
	var players := []
	for side in 2:
		players.append({"faction": _faction(side), "level": int(levels[side].value), "cards": spellbooks[side].duplicate()})
	# Remake quick battle: no original mode of its own, so it follows the Duel
	# rule (an independent coin flip for the first attack phase).
	begin.emit(_profile().id, {"players": players, "arena": battlefield.get_selected_metadata(), "first_side": randi() & 1}, mode.selected)

func _edit_deck(side: int) -> void:
	editing_side = side
	working_cards.assign(spellbooks[side])
	library_cards = ELCatalog.available_cards(_profile(), _faction(side))
	if editor != null: editor.queue_free()
	editor = Window.new()
	editor.title = ELCatalog.FACTIONS[_faction(side)] + " spellbook"
	editor.transient = true
	editor.exclusive = true
	editor.close_requested.connect(func(): editor.hide())
	add_child(editor)
	var margin := MarginContainer.new()
	editor.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	count = _label("", 18)
	rows.add_child(count)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	library = ItemList.new()
	book = ItemList.new()
	for list: ItemList in [library, book]:
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.fixed_icon_size = Vector2i(36, 36)
		columns.add_child(list)
	for card: String in library_cards:
		library.add_item("%d  %s" % [int(_profile().table("CombatSpells")[card].Cost), _profile().text(card + "Nm")], _profile().card_icon(card))
	library.item_selected.connect(func(index: int): description.text = _profile().card_description(library_cards[index]))
	book.item_selected.connect(func(index: int): description.text = _profile().card_description(working_cards[index]))
	library.item_activated.connect(_add_card)
	book.item_activated.connect(_remove_card)
	var controls := HBoxContainer.new()
	rows.add_child(controls)
	controls.add_child(_button("Add →", func():
		if not library.get_selected_items().is_empty(): _add_card(library.get_selected_items()[0])))
	controls.add_child(_button("← Remove", func():
		if not book.get_selected_items().is_empty(): _remove_card(book.get_selected_items()[0])))
	controls.add_child(_button("Starter deck", func():
		working_cards = ELCatalog.deck(_profile(), ELCatalog.STARTERS[_faction(editing_side)])
		_refresh_book()))
	description = _label("Select a spell to read its effect. Double-click to add or remove.", 14)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 68
	rows.add_child(description)
	save_deck_button = _button("Use spellbook", func():
		spellbooks[editing_side] = working_cards.duplicate()
		_summary(editing_side)
		editor.hide())
	rows.add_child(save_deck_button)
	_refresh_book()
	editor.popup_centered(Vector2i(760, 520))

func _add_card(index: int) -> void:
	if working_cards.size() < (15 if _profile().id == "el1" else 16):
		working_cards.append(library_cards[index])
		_refresh_book()

func _remove_card(index: int) -> void:
	working_cards.remove_at(index)
	_refresh_book()

func _refresh_book() -> void:
	book.clear()
	for card: String in working_cards:
		book.add_item("%d  %s" % [int(_profile().table("CombatSpells")[card].Cost), _profile().text(card + "Nm")], _profile().card_icon(card))
	var required := 15 if _profile().id == "el1" else 16
	count.text = "%d / %d spells" % [working_cards.size(), required]
	save_deck_button.disabled = working_cards.size() != required

func _label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	return result

func _button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	return result
