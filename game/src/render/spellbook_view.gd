class_name ELSpellbookView
extends PanelContainer
signal closed
var state: ELAdventureSession
var hero_id := -1
var book: ItemList
var reserve: ItemList
var heading: Label
var resources: Label
var details: RichTextLabel
var message: Label
var equip: Button
var unequip: Button
## Second game: the hero's artifacts with their charges (InventoryScreen rows).
var artifacts: ItemList
var _reserve_cards: Array[String] = []
var _reserve_indices: Array[int] = []

func build(session: ELAdventureSession, id: int) -> void:
	state = session
	hero_id = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 44
	offset_right = -44
	offset_top = 70
	offset_bottom = -44
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)
	var title_row := HBoxContainer.new()
	rows.add_child(title_row)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 23)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(heading)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(func(): closed.emit())
	title_row.add_child(close)
	resources = Label.new()
	resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resources.add_theme_font_size_override("font_size", 14)
	rows.add_child(resources)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	rows.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var label := Label.new()
		label.text = "Equipped spellbook" if side == 0 else "Reserve spells"
		column.add_child(label)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.fixed_icon_size = Vector2i(36, 36)
		list.add_theme_font_size_override("font_size", 16)
		column.add_child(list)
		var button := Button.new()
		column.add_child(button)
		if side == 0:
			book = list
			unequip = button
			button.text = "Move to reserve  →"
			button.pressed.connect(_unequip)
			list.item_selected.connect(func(_index: int): reserve.deselect_all(); _deselect_artifacts(); _select())
			list.item_activated.connect(func(_index: int): _unequip())
		else:
			reserve = list
			equip = button
			button.text = "←  Add to spellbook"
			button.pressed.connect(_equip)
			list.item_selected.connect(func(_index: int): book.deselect_all(); _deselect_artifacts(); _select())
			list.item_activated.connect(func(_index: int): _equip())
	if ELSecondArtifacts.applies(state.map.profile):
		var caption := Label.new()
		caption.text = "Artifacts"
		rows.add_child(caption)
		artifacts = ItemList.new()
		artifacts.max_columns = 0
		artifacts.icon_mode = ItemList.ICON_MODE_TOP
		artifacts.fixed_icon_size = Vector2i(40, 40)
		artifacts.fixed_column_width = 64
		artifacts.custom_minimum_size.y = 76
		artifacts.add_theme_font_size_override("font_size", 14)
		artifacts.item_selected.connect(_select_artifact)
		rows.add_child(artifacts)
	details = RichTextLabel.new()
	details.custom_minimum_size.y = 82
	details.add_theme_font_size_override("normal_font_size", 16)
	rows.add_child(details)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
	rows.add_child(message)
	refresh()

func refresh() -> void:
	var hero := state.object(hero_id)
	var profile := state.map.profile
	heading.text = "%s · Spellbook %d / %d" % [hero.get("title", hero.get("name", "")), hero.cards.size(), ELSpellInventory.book_size(profile)]
	resources.text = ELResources.describe(profile.id, state.players.get(hero.owner, {}).get("resources", {}))
	book.clear()
	reserve.clear()
	_reserve_cards.clear()
	_reserve_indices.clear()
	for index in hero.cards.size():
		var card: String = hero.cards[index]
		var runes := "  ·  " + _runes(hero.rune_uses[index]) if profile.id == "el1" else ""
		book.add_item(_name(card) + runes, profile.card_icon(card))
	var cards: Array[String] = []
	for card: String in hero.spell_stock:
		if int(hero.spell_stock[card]) > 0: cards.append(card)
	cards.sort_custom(func(a: String, b: String): return _name(a).naturalnocasecmp_to(_name(b)) < 0)
	for card: String in cards:
		if profile.id == "el1":
			var counts: Array = hero.rune_stock[card]
			var shown: Array[int] = []
			for index in counts.size():
				var uses := int(counts[index])
				if shown.has(uses): continue
				shown.append(uses)
				_reserve_cards.append(card)
				_reserve_indices.append(index)
				reserve.add_item("%s  ·  %s  ×%d" % [_name(card), _runes(uses), counts.count(uses)], profile.card_icon(card))
		else:
			_reserve_cards.append(card)
			_reserve_indices.append(0)
			reserve.add_item("%s  ×%d" % [_name(card), hero.spell_stock[card]], profile.card_icon(card))
	if artifacts != null:
		artifacts.clear()
		for item: Dictionary in hero.get("artifacts", []):
			var index := artifacts.add_item(str(int(item.get("charges", 0))), profile.card_icon(ELSecondArtifacts.spell(profile, item)))
			artifacts.set_item_tooltip(index, ELSecondArtifacts.tooltip(profile, item))
	message.text = "Select a spell to move it between your book and reserve."
	if hero.cards.is_empty(): message.text = "Add a spell to your book before entering battle."
	_select()

func _name(card: String) -> String:
	return state.map.profile.text(str(state.map.profile.table("CombatSpells").get(card, {}).get("Name", card)))

func _runes(count: int) -> String:
	return "unlimited" if count < 0 else "%d rune%s" % [count, "" if count == 1 else "s"]

func _select() -> void:
	var hero := state.object(hero_id)
	var selected := book.get_selected_items()
	var stored := reserve.get_selected_items()
	unequip.disabled = selected.is_empty()
	equip.disabled = true
	var card := ""
	if not selected.is_empty(): card = hero.cards[selected[0]]
	elif not stored.is_empty():
		card = _reserve_cards[stored[0]]
		equip.disabled = hero.cards.size() >= ELSpellInventory.book_size(state.map.profile) or not ELSpellInventory.allows(state.map.profile, hero, card)
	if card.is_empty():
		details.text = ""
		return
	var row: Dictionary = state.map.profile.table("CombatSpells").get(card, {})
	details.text = "%s · %s · %d ether\n%s" % [_name(card), row.get("Color", ""), int(row.get("Cost", 0)), state.map.profile.text(str(row.get("ToolTip", "")))]
	if state.map.profile.id == "el1":
		var count: int = hero.rune_uses[selected[0]] if not selected.is_empty() else hero.rune_stock[card][_reserve_indices[stored[0]]]
		details.text += "\n" + ("Unlimited cantrip." if count < 0 else "%s remaining. When this copy runs out, drawing it chooses a cantrip of the same color and spell class." % _runes(count))
	if not stored.is_empty():
		if hero.cards.size() >= ELSpellInventory.book_size(state.map.profile): message.text = "Move a spell to reserve to make room."
		elif not ELSpellInventory.allows(state.map.profile, hero, card): message.text = "This hero cannot use that spell's magic color."
		else: message.text = "Add this copy to your equipped spellbook."

func _deselect_artifacts() -> void:
	if artifacts != null: artifacts.deselect_all()

func _select_artifact(index: int) -> void:
	book.deselect_all()
	reserve.deselect_all()
	unequip.disabled = true
	equip.disabled = true
	var list: Array = state.object(hero_id).get("artifacts", [])
	if index < 0 or index >= list.size(): return
	var profile := state.map.profile
	var code := ELSecondArtifacts.spell(profile, list[index])
	details.text = ELSecondArtifacts.tooltip(profile, list[index]) + "\n" + profile.text(str(profile.table("CombatSpells").get(code, {}).get("ToolTip", "")))

func _equip() -> void:
	var selected := reserve.get_selected_items()
	if selected.is_empty() or equip.disabled: return
	var card := _reserve_cards[selected[0]]
	if not state.move_spell(hero_id, card, -1, _reserve_indices[selected[0]]):
		message.text = state.error
		return
	refresh()
	book.select(book.item_count - 1)
	_select()

func _unequip() -> void:
	var selected := book.get_selected_items()
	if selected.is_empty() or unequip.disabled: return
	var card: String = state.object(hero_id).cards[selected[0]]
	var count := int(state.object(hero_id).rune_uses[selected[0]]) if state.map.profile.id == "el1" else 0
	if not state.move_spell(hero_id, "", selected[0]):
		message.text = state.error
		return
	refresh()
	for index in _reserve_cards.size():
		if _reserve_cards[index] == card and (state.map.profile.id != "el1" or state.object(hero_id).rune_stock[card][_reserve_indices[index]] == count):
			reserve.select(index)
			break
	_select()
