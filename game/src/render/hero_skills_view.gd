class_name ELHeroSkillsView
extends PanelContainer
signal closed
var state: ELAdventureSession
var hero_id := -1
var heading: Label
## Item lists here; the second game's level-up dialog supplies its own strips
## with the same selection interface.
var learned
var offers
var details: RichTextLabel
var accept: BaseButton
var message: Label
var _learned: Array[String] = []
var spec_row: HBoxContainer
var spec_pick: OptionButton
var _specs: Array[String] = []

func build(session: ELAdventureSession, id: int) -> void:
	state = session
	hero_id = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 44
	offset_right = -44
	offset_top = 70
	offset_bottom = -44
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	add_child(rows)
	var top := HBoxContainer.new()
	rows.add_child(top)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 23)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	rows.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var label := Label.new()
		label.text = "Learned skills · Five slots" if side == 0 else "Choose one skill to learn or improve"
		column.add_child(label)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.fixed_icon_size = Vector2i(40, 40)
		list.add_theme_font_size_override("font_size", 18)
		column.add_child(list)
		if side == 0:
			learned = list
			list.item_selected.connect(func(_index: int): offers.deselect_all(); _select())
		else:
			offers = list
			list.item_selected.connect(func(_index: int): learned.deselect_all(); _select())
	details = RichTextLabel.new()
	details.custom_minimum_size.y = 130
	details.add_theme_font_size_override("normal_font_size", 18)
	rows.add_child(details)
	# Second-game heroes choose which of their specialisations is active.
	spec_row = HBoxContainer.new()
	spec_row.add_theme_constant_override("separation", 12)
	var spec_label := Label.new()
	spec_label.text = "Active specialization"
	spec_row.add_child(spec_label)
	spec_pick = OptionButton.new()
	spec_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spec_pick.item_selected.connect(_choose_spec)
	spec_row.add_child(spec_pick)
	rows.add_child(spec_row)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(message)
	var learn := Button.new()
	learn.text = "Learn selected skill"
	learn.pressed.connect(_choose)
	rows.add_child(learn)
	accept = learn
	refresh()

func refresh() -> void:
	var hero := state.object(hero_id)
	var pending := int(hero.skill_points)
	heading.text = "%s · Skills · %d choice%s available" % [hero.get("title", hero.name), pending, "s" if pending != 1 else ""]
	_learned.assign(hero.skills.keys())
	learned.clear()
	offers.clear()
	for code: String in _learned: learned.add_item(_label(code, hero.skills[code]), _icon(code, hero.skills[code]))
	for code: String in hero.get("skill_offers", []):
		var rank := int(hero.skills.get(code, -1)) + 1
		offers.add_item(_label(code, rank), _icon(code, rank))
	message.text = "Choose carefully: learning a skill spends one level-up choice." if pending > 0 else "Gain a level to learn or improve a skill."
	_specs.clear()
	if state.map.profile.id == "el2": _specs.assign(state.specializations(hero))
	spec_row.visible = not _specs.is_empty()
	spec_pick.clear()
	for code: String in _specs:
		spec_pick.add_item(state.map.profile.text(str(state.map.profile.table("HeroesSpecs").get(code, {}).get("Name", code))))
		spec_pick.set_item_tooltip(spec_pick.item_count - 1, state.map.profile.text(str(state.map.profile.table("HeroesSpecs").get(code, {}).get("Desc", ""))))
	if not _specs.is_empty(): spec_pick.select(maxi(0, _specs.find(str(hero.get("specialization", "NONE")))))
	_select()

func _choose_spec(index: int) -> void:
	if index < 0 or index >= _specs.size(): return
	if not state.choose_specialization(hero_id, _specs[index]): message.text = state.error
	else: message.text = "Active specialization: " + spec_pick.get_item_text(index)

func _label(code: String, rank: int) -> String:
	var row := ELHeroSkills.definition(state.map.profile, code, rank)
	return "%s  ·  %s" % [state.map.profile.text(str(row.get("Name", code))), ["I", "II", "III"][rank]]

func _icon(code: String, rank: int) -> Texture2D:
	var index := int(ELHeroSkills.definition(state.map.profile, code, rank).get("Icon", -1))
	if index < 0: return null
	var icon := AtlasTexture.new()
	icon.atlas = state.map.profile.texture("Interface/Skills/icon_1")
	icon.region = Rect2((index / 5) * 50, (index % 5) * 50, 50, 50)
	icon.filter_clip = true
	return icon

func _select() -> void:
	var hero := state.object(hero_id)
	var offered: PackedInt32Array = offers.get_selected_items()
	var known: PackedInt32Array = learned.get_selected_items()
	accept.disabled = offered.is_empty()
	var code := ""
	var rank := 0
	if not offered.is_empty():
		code = str(hero.skill_offers[offered[0]])
		rank = int(hero.skills.get(code, -1)) + 1
	elif not known.is_empty():
		code = _learned[known[0]]
		rank = int(hero.skills[code])
	if code.is_empty():
		details.text = ""
		return
	var row := ELHeroSkills.definition(state.map.profile, code, rank)
	details.text = _label(code, rank) + "\n\n" + state.map.profile.text(str(row.get("Description", "")))

func _choose() -> void:
	var selected: PackedInt32Array = offers.get_selected_items()
	if selected.is_empty() or accept.disabled: return
	var code := str(state.object(hero_id).skill_offers[selected[0]])
	if not state.choose_skill(hero_id, code):
		message.text = state.error
		return
	refresh()
	learned.select(_learned.find(code))
	_select()
