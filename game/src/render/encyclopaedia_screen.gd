class_name ELEncyclopaediaScreen
extends RefCounted
## Second-game Encyclopaedia (Encyclopaedia panel) on the ELFrontMenu canvas:
## race emblem with EncRaceLeft/Right (Red, Green, Blue, Black, White,
## artifacts), the mode popup (creatures, enchantments, sorcery), column sorts,
## the card list and, for creatures, the encyclopaedia picture with the name and
## description; EncOkBtn returns to the main menu (or, hosted from the
## adventure Esc menu, to that menu). Creature rows are 55 px
## (icon, name, cost, power/toughness); enchantment and sorcery rows span the
## Type2 table and grow with their description. The creature page names the
## card in EncHdrRight and lists its ability icons (16 px CombatSymbols cells,
## 20 px apart) at the top of EncRightMonstaBounds. The creature list and the
## enchantment/sorcery list each keep their own sort and a direction per
## column: every press of a column flips its direction (the first ascending).
## Catalogue: ELEncyclopaedia.

const ROW := 55.0
const ROW_INK := Color("d6bb88")
const CHOSEN_INK := Color.WHITE
const POPUP_ROW := 26.0
## Creature picture origin in the panel.
const PICTURE := Vector2(403, 25)

var menu: ELFrontMenu
var race := 0
var mode := 0
var sort := ELEncyclopaedia.SORT_NONE
## Direction of the current sort, and per list (0 creatures, 1 the others)
## the chosen column and each column's direction (true ascending).
var ascending := true
var lists: Array[Dictionary] = []
const ICON_STEP := 20.0
var selected := ""
var popup_open := false
var list: CardList
var popup: ModePopup
var picture: CreaturePicture
var _codes: Array[String] = []

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func creatures() -> bool:
	return mode == 0

## Opening starts at the first race and creatures; both lists
## reset their directions and sort by rarity ascending; the first row is chosen.
func open() -> void:
	race = 0
	mode = 0
	lists = [{"sort": "rarity", "up": {"rarity": true}}, {"sort": "rarity", "up": {"rarity": true}}]
	_apply_list()
	selected = ""
	popup_open = false
	menu.show_screen("encyclopaedia")

func art_exclude(target: String) -> Array:
	if target != "encyclopaedia": return []
	var result: Array = ["Type2" if creatures() else "Type1"]
	for index in ELEncyclopaedia.RACE_COUNT:
		if index != race: result.append("Phase%d" % (index + 1))
	return result

func codes() -> Array[String]:
	return _codes

func _rect(control: String) -> Rect2:
	return menu.control_rect(control)

func _button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button == null: return null
	# Controls whose resting picture is part of the panel art draw nothing at rest.
	if menu.rows(control, ["Free"], ["Light"]).is_empty(): button.parts.normal = {}
	button.pressed.connect(action)
	return button

func build_screen() -> void:
	_codes = ELEncyclopaedia.codes(menu.profile, race, mode, sort, ascending)
	if not _codes.has(selected): selected = _codes[0] if not _codes.is_empty() else ""
	menu._label("EncHdrLeft", menu._caption("EncHdrLeft"), _rect("EncHdrLeft"), 18)
	if creatures():
		# The chosen creature's name replaces the header caption.
		var header := menu._label("EncHdrRight", menu._caption("EncHdrRight"), _rect("EncHdrRight"), 18)
		menu.labels["card_name"] = header
	menu._label("EncCurMode", menu.text(ELEncyclopaedia.MODE_TEXTS[mode]), _rect("EncCurMode"), 17, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_button("EncRaceLeft", func(): set_race((race + ELEncyclopaedia.RACE_COUNT - 1) % ELEncyclopaedia.RACE_COUNT))
	_button("EncRaceRight", func(): set_race((race + 1) % ELEncyclopaedia.RACE_COUNT))
	_button("EncDropBtn", toggle_popup)
	for control: String in ["EncSortRarity", "EncSortName"]:
		var text_button := ELDuelScreen.FlatText.new()
		text_button.menu = menu
		text_button.caption = menu._caption(control)
		text_button.font_size = 16
		var rect := _rect(control)
		text_button.position = rect.position
		text_button.size = rect.size
		var key: String = "rarity" if control == "EncSortRarity" else "name"
		text_button.active = sort == key
		var tip := menu.text("CtrlTT" + control)
		if tip != "CtrlTT" + control: text_button.tooltip_text = tip
		menu.canvas.add_child(text_button)
		menu.buttons[control] = text_button
		text_button.pressed.connect(set_sort.bind(key))
	for pair: Array in [["EncSortMana", "cost"], ["EncSortAttack", "power"], ["EncSortDefence", "toughness"]]:
		if not creatures() and pair[1] != "cost": continue
		var sort_button := _button(pair[0], set_sort.bind(pair[1]))
		if sort_button != null: sort_button.active = sort == pair[1]
	list = CardList.new()
	list.screen = self
	var bounds := _rect("EncMonstaListBounds" if creatures() else "EncEnchantBounds")
	list.position = bounds.position
	list.size = bounds.size
	menu.canvas.add_child(list)
	menu.labels["list"] = list
	var up := "EncScrollMU" if creatures() else "EncScrollEU"
	var down := "EncScrollMD" if creatures() else "EncScrollED"
	_button(up, func(): list.scroll(-1))
	_button(down, func(): list.scroll(1))
	if creatures(): _build_detail()
	_button("EncOkBtn", close_screen)
	popup = ModePopup.new()
	popup.screen = self
	var anchor := _rect("EncPopup")
	popup.position = anchor.position
	popup.size = Vector2(anchor.size.x, POPUP_ROW * ELEncyclopaedia.MODES.size())
	popup.visible = popup_open
	menu.canvas.add_child(popup)
	menu.labels["popup"] = popup
	refresh()

func _build_detail() -> void:
	var origin := menu.shift("Encyclopaedia") + PICTURE
	picture = CreaturePicture.new()
	picture.position = origin
	picture.size = Vector2(384, 512)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.canvas.add_child(picture)
	menu.labels["picture"] = picture
	var bounds := _rect("EncRightMonstaBounds")
	var text_bounds := _rect("EncRightMonstaTextBounds")
	var icons := Control.new()
	icons.name = "AbilityIcons"
	icons.position = bounds.position
	icons.size = Vector2(bounds.size.x, ELCombatSymbols.CELL)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.canvas.add_child(icons)
	menu.labels["abilities"] = icons
	var box := menu._text_box(text_bounds, "", 16)
	box.add_theme_color_override("default_color", ELFrontMenu.INK_HOVER)
	box.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	box.add_theme_constant_override("shadow_offset_x", 1)
	box.add_theme_constant_override("shadow_offset_y", 1)

func refresh() -> void:
	if menu.screen != "encyclopaedia": return
	if list != null:
		list.reveal(_codes.find(selected))
		list.queue_redraw()
	if creatures():
		if menu.labels.has("card_name"): menu.labels.card_name.text = ELEncyclopaedia.name(menu.profile, selected) if not selected.is_empty() else menu._caption("EncHdrRight")
		if menu.labels.has("abilities"): _fill_icons(menu.labels.abilities)
		if menu.text_box != null:
			menu.text_box.text = menu.profile.card_description(selected) if not selected.is_empty() else ""
			menu.text_box.get_v_scroll_bar().value = 0
		if picture != null:
			picture.parts = ELEncyclopaedia.picture(menu.profile, selected) if not selected.is_empty() else []
			picture.queue_redraw()

func set_race(index: int) -> void:
	race = clampi(index, 0, ELEncyclopaedia.RACE_COUNT - 1)
	selected = ""
	popup_open = false
	if list != null: list.offset = 0
	menu.show_screen("encyclopaedia")

func set_mode(index: int) -> void:
	mode = clampi(index, 0, ELEncyclopaedia.MODES.size() - 1)
	_apply_list()
	selected = ""
	popup_open = false
	menu.show_screen("encyclopaedia")

## A column press flips that column's direction in the shown list (attack and
## defence always belong to the creature list) and keeps the chosen card.
func set_sort(key: String) -> void:
	if lists.is_empty(): lists = [{"sort": "", "up": {}}, {"sort": "", "up": {}}]
	var target: Dictionary = lists[0 if creatures() or key in ["power", "toughness"] else 1]
	target.up[key] = not bool(target.up.get(key, false))
	target.sort = key
	_apply_list()
	popup_open = false
	menu.show_screen("encyclopaedia")

func _apply_list() -> void:
	if lists.is_empty():
		sort = ELEncyclopaedia.SORT_NONE
		ascending = true
		return
	var current: Dictionary = lists[0 if creatures() else 1]
	sort = str(current.sort)
	ascending = bool(current.up.get(sort, true))

## The creature's ability icons with their caption and text as the tooltip.
func _fill_icons(holder: Control) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	if selected.is_empty(): return
	var sheet := menu.profile.texture("Interface/combatsymbols")
	if sheet == null: return
	var numbers := ELEncyclopaedia.ability_icons(menu.profile, selected)
	for index in numbers.size():
		var number := numbers[index]
		var cell: int = ELCombatSymbols.ICON_CODES[number]
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((cell % 16) * ELCombatSymbols.CELL, (cell / 16) * ELCombatSymbols.CELL, ELCombatSymbols.CELL, ELCombatSymbols.CELL)
		var icon := TextureRect.new()
		icon.texture = atlas
		icon.position = Vector2(ICON_STEP * index, 0)
		icon.size = Vector2(ELCombatSymbols.CELL, ELCombatSymbols.CELL)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		var caption := menu.text("T_CREATURE_ICON_%02dC" % (number + 1)).strip_edges()
		var body := menu.text("T_CREATURE_ICON_%02d" % (number + 1)).strip_edges()
		icon.tooltip_text = caption + ("\n" + body if not body.is_empty() else "")
		holder.add_child(icon)

func toggle_popup() -> void:
	popup_open = not popup_open
	if popup != null: popup.visible = popup_open

func choose(index: int) -> void:
	if index < 0 or index >= _codes.size(): return
	selected = _codes[index]
	refresh()

## EncOkBtn (0xef4, also the Esc accelerator) closes the panel: the main menu,
## or whatever the host showed beneath it (the adventure Esc menu).
func close_screen() -> void:
	menu.leave_screen()

## Esc closes the open popup first.
func escape() -> bool:
	if popup_open:
		toggle_popup()
		return true
	return false

## Card list: fixed 55 px creature rows; enchantment and sorcery rows grow
## with their wrapped description.
class CardList extends Control:
	var screen: ELEncyclopaediaScreen
	var offset := 0
	var _heights: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func columns() -> Dictionary:
		var origin := position
		var name_rect := screen._rect("EncSortName")
		var mana := screen._rect("EncSortMana")
		return {"icon": 0.0, "name": name_rect.position.x - origin.x, "cost": mana.position.x - origin.x, "cost_w": mana.size.x,
			"extra": mana.end.x - origin.x + 1, "extra_end": size.x}

	func row_height(code: String) -> float:
		if screen.creatures(): return ELEncyclopaediaScreen.ROW
		if not _heights.has(code):
			var font := screen.menu.arial
			var cols := columns()
			var width: float = cols.extra_end - cols.extra - 8
			var text_height := font.get_multiline_string_size(screen.menu.profile.card_description(code), HORIZONTAL_ALIGNMENT_LEFT, width, 15).y
			_heights[code] = maxf(ELEncyclopaediaScreen.ROW, ceilf(text_height) + 6)
		return _heights[code]

	func visible_count() -> int:
		var codes := screen.codes()
		var used := 0.0
		var count := 0
		for index in range(offset, codes.size()):
			used += row_height(codes[index])
			if used > size.y + 0.5: break
			count += 1
		return maxi(1, count)

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, _last_offset())
		queue_redraw()

	## Smallest offset from which every remaining row fits.
	func _last_offset() -> int:
		var codes := screen.codes()
		var start := codes.size()
		var used := 0.0
		while start > 0:
			used += row_height(codes[start - 1])
			if used > size.y + 0.5: break
			start -= 1
		return start

	func reveal(index: int) -> void:
		if index < 0: return
		if index < offset: offset = index
		while index >= offset + visible_count() and offset < index: offset += 1
		offset = mini(offset, _last_offset())

	func row_at(y: float) -> int:
		var codes := screen.codes()
		var top := 0.0
		for index in range(offset, codes.size()):
			var height := row_height(codes[index])
			if y >= top and y < top + height: return index
			top += height
		return -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
			elif event.button_index == MOUSE_BUTTON_LEFT: screen.choose(row_at(event.position.y))
			accept_event()

	func _draw() -> void:
		var codes := screen.codes()
		var profile := screen.menu.profile
		var font := screen.menu.arial
		var cols := columns()
		var top := 0.0
		for index in range(offset, codes.size()):
			if top >= size.y: break
			var code: String = codes[index]
			var height := row_height(code)
			var ink := ELEncyclopaediaScreen.CHOSEN_INK if code == screen.selected else ELEncyclopaediaScreen.ROW_INK
			var icon := profile.card_icon(code)
			var icon_top := top + (minf(height, ELEncyclopaediaScreen.ROW) - 50.0) * 0.5
			if icon != null: draw_texture_rect(icon, Rect2(Vector2((float(cols.name) - 50.0) * 0.5, icon_top), Vector2(50, 50)), false)
			var middle := top + ELEncyclopaediaScreen.ROW * 0.5 - font.get_height(17) * 0.5 + font.get_ascent(17)
			var name_x: float = cols.name + 4
			draw_string(font, Vector2(name_x, middle), ELEncyclopaedia.name(profile, code), HORIZONTAL_ALIGNMENT_LEFT, float(cols.cost) - name_x - 4, 17, ink)
			var cost := str(ELEncyclopaedia.cost(profile, code))
			draw_string(font, Vector2(float(cols.cost), middle), cost, HORIZONTAL_ALIGNMENT_CENTER, float(cols.cost_w), 17, ink)
			if screen.creatures():
				draw_string(font, Vector2(float(cols.extra), middle), ELEncyclopaedia.strength(profile, code), HORIZONTAL_ALIGNMENT_CENTER, float(cols.extra_end) - float(cols.extra), 17, ink)
			else:
				var width: float = cols.extra_end - cols.extra - 8
				draw_multiline_string(font, Vector2(float(cols.extra) + 4, top + 3 + font.get_ascent(15)), profile.card_description(code), HORIZONTAL_ALIGNMENT_LEFT, width, 15, -1, ink)
			top += height
			if not screen.creatures(): draw_line(Vector2(0, top - 0.5), Vector2(size.x, top - 0.5), Color(0.55, 0.47, 0.35, 0.45), 1.0)

## Creature picture: _1 top-left, _2 below it, _3's halves in the right column.
class CreaturePicture extends Control:
	var parts: Array = []

	func _draw() -> void:
		if parts.size() < 3: return
		draw_texture_rect(parts[0], Rect2(0, 0, 256, 256), false)
		draw_texture_rect(parts[1], Rect2(0, 256, 256, 256), false)
		draw_texture_rect_region(parts[2], Rect2(256, 0, 128, 256), Rect2(0, 0, 128, 256))
		draw_texture_rect_region(parts[2], Rect2(256, 256, 128, 256), Rect2(128, 0, 128, 256))

## Mode list under EncDropBtn: each 26 px row is the left, tiled
## middle and right 10 px strips of EncPopupTexturesCtrl (the hovered row
## elements 0..2, the others 3..5); the current mode is white.
class ModePopup extends Control:
	var screen: ELEncyclopaediaScreen
	var hover := -1
	var _strips: Array[Dictionary] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(func():
			hover = -1
			queue_redraw())
		var rows := screen.menu.rows("EncPopupTexturesCtrl")
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.TxtL) < int(b.TxtL))
		for row: Dictionary in rows:
			var piece := screen.menu.cut(row)
			if not piece.is_empty(): _strips.append(piece)

	func row_at(y: float) -> int:
		var index := int(floorf(y / ELEncyclopaediaScreen.POPUP_ROW))
		return index if index >= 0 and index < ELEncyclopaedia.MODES.size() else -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var at := row_at(event.position.y)
			if at != hover:
				hover = at
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var index := row_at(event.position.y)
			if index >= 0: screen.set_mode(index)
			accept_event()

	func _draw() -> void:
		var font := screen.menu.arial
		var height := ELEncyclopaediaScreen.POPUP_ROW
		for row in ELEncyclopaedia.MODES.size():
			var top := row * height
			if _strips.size() >= 6:
				var first := 0 if row == hover else 3
				var left: Dictionary = _strips[first]
				var middle: Dictionary = _strips[first + 1]
				var right: Dictionary = _strips[first + 2]
				var step: float = left.source.size.x
				draw_texture_rect_region(left.texture, Rect2(0, top, step, height), left.source)
				var x := step
				while x + 2 * step <= size.x:
					draw_texture_rect_region(middle.texture, Rect2(x, top, step, height), middle.source)
					x += step
				draw_texture_rect_region(right.texture, Rect2(x, top, step, height), right.source)
			else:
				draw_rect(Rect2(0, top, size.x, height), Color(0.05, 0.05, 0.04, 0.97))
			var ink := ELEncyclopaediaScreen.CHOSEN_INK if row == screen.mode else ELEncyclopaediaScreen.ROW_INK
			var baseline := top + (height - font.get_height(17)) * 0.5 + font.get_ascent(17)
			draw_string(font, Vector2(8, baseline), screen.menu.text(ELEncyclopaedia.MODE_TEXTS[row]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 17, ink)
