class_name ELFirstBookView
extends ELHeroScreenView
## First game: the hero's spellbook and spell reserve on the laboratory panel
## (Controls "SpellShop", the same original art as the shop). The left half is
## the hero panel with the equipped book; the right half lists the reserve,
## one cell per spell and rune count ("×n" for several copies). The price
## table shows the selected spell's rune price and the owner's resources.
##
## A click selects a spell; a double or right click moves it at once between
## the book and the reserve, as do the two arrow buttons. OK, Cancel and
## Escape close the screen. The moves go through ELAdventureSession.move_spell
## (or the network order in a strategic session).
## The laboratory panel's places (as in ELFirstSpellShopView).
const RESERVE_CELL := Vector2(516, 107)
const RESERVE_COLUMNS := 2
const RESERVE_ROWS := 8
const PRICE_COLUMNS := [400.0, 452.0]
const PRICE_TOP := 162.0
const PRICE_STEP := 35.0
const PRICE_BOX := Vector2(30, 18)
const TIPS := {"SpellTt1": Rect2(346, 132, 26, 24), "SpellTt2": Rect2(397, 132, 30, 24), "SpellTt3": Rect2(450, 134, 30, 22), "SpellTt4": Rect2(447, 135, 30, 23)}
const PICK := Color("e8e0cc")
const WHITE := Color(1, 1, 1)

var hero_id := -1
## Reserve cells: {card, index (rune_stock position), uses, count}.
var entries: Array[Dictionary] = []
var book_pick := -1
var reserve_pick := -1
var reserve_scroll := 0
var _type_pieces: Array = []

func build_book(owner: ELAdventureDirector, panel: ELAdventureHud, id: int) -> void:
	director = owner
	state = owner.state
	hud = panel
	profile = state.map.profile
	hero_id = id
	heroes = [id]
	exchange = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sheet = Sheet.new()
	sheet.view = self
	sheet.size = Vector2(660, 600)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.tooltip_text = " "
	add_child(sheet)
	var parts := ELFirstSpellShopView.panel_parts(hud, profile)
	_pieces.assign(parts.pieces)
	_type_pieces = parts.Type1
	_build_side(0)
	_header(Rect2(53, 0, 220, 23), _t("Spellbook"), 20)
	_header(Rect2(373, 0, 220, 23), _t("Spell reserve"), 20)
	_header(Rect2(342, 41, 278, 18), _t("Click selects a spell; a double or"), 15)
	_header(Rect2(342, 59, 278, 18), _t("right click moves it to the other side."), 15)
	var into_book := _button("BuySpell", Vector2.ZERO)
	into_book.pressed.connect(equip)
	into_book.tooltip_text = _t("Add the selected reserve spell to the book")
	var into_reserve := _button("RetrieveSpell", Vector2.ZERO)
	into_reserve.pressed.connect(unequip)
	into_reserve.tooltip_text = _t("Move the selected book spell to the reserve")
	_button("AcceptBuy", Vector2.ZERO).pressed.connect(func(): closed.emit())
	_button("DeclineBuy", Vector2.ZERO).pressed.connect(func(): closed.emit())
	_button("SShopUp", Vector2.ZERO).pressed.connect(func(): scroll_reserve(-1))
	_button("SShopDown", Vector2.ZERO).pressed.connect(func(): scroll_reserve(1))
	_build_online_message()
	resized.connect(_layout)
	_layout()
	refresh()

func _t(text: String) -> String:
	return ELRemakeText.t(text, profile)

func _header(rect: Rect2, text: String, size: int) -> Label:
	while size > 11 and hud._bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x: size -= 1
	return _label(rect, text, size, CAPTION, hud._bold)

func hero() -> Dictionary:
	return state.object(hero_id)

func _name(card: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(card, {}).get("Name", card)))

## Reserve cells by name, one per card and rune count.
func _collect() -> void:
	entries.clear()
	var owner := hero()
	var cards: Array[String] = []
	for card: String in owner.get("spell_stock", {}):
		if int(owner.spell_stock[card]) > 0: cards.append(card)
	cards.sort_custom(func(a: String, b: String): return _name(a).naturalnocasecmp_to(_name(b)) < 0)
	for card: String in cards:
		var counts: Array = owner.get("rune_stock", {}).get(card, [])
		if counts.is_empty():
			entries.append({"card": card, "index": 0, "uses": -1, "count": int(owner.spell_stock[card])})
			continue
		var shown: Array[int] = []
		for index in counts.size():
			var uses := int(counts[index])
			if shown.has(uses): continue
			shown.append(uses)
			entries.append({"card": card, "index": index, "uses": uses, "count": counts.count(uses)})

func book_cards(_side: int) -> Array:
	return hero().get("cards", [])

func book_uses(_side: int) -> Array:
	return hero().get("rune_uses", [])

func book_rect(index: int) -> Rect2:
	return Rect2(Vector2(29 + 53 * (index % 5), 389 + 52 * (index / 5)), ICON)

func reserve_rect(index: int) -> Rect2:
	var visible := index - reserve_scroll * RESERVE_COLUMNS
	return Rect2(RESERVE_CELL + Vector2(STEP * (visible % RESERVE_COLUMNS), 52 * (visible / RESERVE_COLUMNS)), ICON)

func max_scroll() -> int:
	return maxi(0, ceili(entries.size() / float(RESERVE_COLUMNS)) - RESERVE_ROWS)

func scroll_reserve(delta: int) -> void:
	reserve_scroll = clampi(reserve_scroll + delta, 0, max_scroll())
	refresh()

func book_at(point: Vector2) -> int:
	for index in mini(15, book_cards(0).size()):
		if book_rect(index).has_point(point): return index
	return -1

func reserve_at(point: Vector2) -> int:
	for index in range(reserve_scroll * RESERVE_COLUMNS, mini(entries.size(), (reserve_scroll + RESERVE_ROWS) * RESERVE_COLUMNS)):
		if reserve_rect(index).has_point(point): return index
	return -1

func press(point: Vector2) -> void:
	var book := book_at(point)
	if book >= 0:
		book_pick = book
		reserve_pick = -1
		if double_click: unequip()
		else: refresh()
		return
	var index := reserve_at(point)
	if index >= 0:
		reserve_pick = index
		book_pick = -1
		if double_click: equip()
		else: refresh()

func right_press(point: Vector2) -> bool:
	var book := book_at(point)
	if book >= 0:
		book_pick = book
		reserve_pick = -1
		unequip()
		return true
	var index := reserve_at(point)
	if index < 0: return false
	reserve_pick = index
	book_pick = -1
	equip()
	return true

func wheel(point: Vector2, direction: int) -> bool:
	if not Rect2(RESERVE_CELL, Vector2(STEP * RESERVE_COLUMNS, 52 * RESERVE_ROWS)).has_point(point): return false
	scroll_reserve(direction)
	return true

func _can_act() -> bool:
	if _purchase_pending: return false
	return strategic_session.can_plan() if strategic_session != null else true

## Why the selected reserve spell cannot join the book ("" when it can).
func equip_problem() -> String:
	if reserve_pick < 0 or reserve_pick >= entries.size(): return "Select a reserve spell."
	if book_cards(0).size() >= ELSpellInventory.book_size(profile): return "Move a spell to reserve to make room."
	if not ELSpellInventory.allows(profile, hero(), str(entries[reserve_pick].card)): return "This hero cannot use that spell's magic color."
	return ""

func equip() -> void:
	if not _can_act() or not equip_problem().is_empty(): return
	var entry := entries[reserve_pick]
	if strategic_session != null:
		_manage_online(["equip", hero_id, entry.card, int(entry.index)])
		return
	if not state.move_spell(hero_id, str(entry.card), -1, int(entry.index)):
		_say(state.error)
		return
	book_pick = book_cards(0).size() - 1
	reserve_pick = -1
	refresh()

func unequip() -> void:
	if not _can_act() or book_pick < 0 or book_pick >= book_cards(0).size(): return
	var card := str(book_cards(0)[book_pick])
	if strategic_session != null:
		_manage_online(["reserve", hero_id, card, book_pick])
		return
	var uses := int(book_uses(0)[book_pick]) if book_pick < book_uses(0).size() else -1
	if not state.move_spell(hero_id, "", book_pick):
		_say(state.error)
		return
	book_pick = -1
	refresh()
	# The moved copy stays selected in the reserve.
	for index in entries.size():
		if entries[index].card == card and (int(entries[index].uses) == uses or int(entries[index].uses) == -1):
			reserve_pick = index
			break
	refresh()

func _say(text: String) -> void:
	if text.is_empty(): return
	if _online_message == null: _online_message = _label(Rect2(12, 603, 613, 20), "", 13, TEXT, hud._bold)
	_online_message.text = _t(text)

func refresh() -> void:
	_collect()
	_refresh_sides()
	reserve_scroll = clampi(reserve_scroll, 0, max_scroll())
	if book_pick >= book_cards(0).size(): book_pick = -1
	if reserve_pick >= entries.size(): reserve_pick = -1
	buttons.BuySpell.disabled = not _can_act() or not equip_problem().is_empty()
	buttons.RetrieveSpell.disabled = not _can_act() or book_pick < 0
	buttons.SShopUp.disabled = reserve_scroll <= 0
	buttons.SShopDown.disabled = reserve_scroll >= max_scroll()
	sheet.queue_redraw()

func selected_card() -> String:
	if book_pick >= 0 and book_pick < book_cards(0).size(): return str(book_cards(0)[book_pick])
	if reserve_pick >= 0 and reserve_pick < entries.size(): return str(entries[reserve_pick].card)
	return ""

## Price of one rune of the selected spell (the Charge columns), or {}.
func rune_price() -> Dictionary:
	var card := selected_card()
	if card.is_empty(): return {}
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	var result := ELResources.empty("el1")
	for kind: String in result: result[kind] = int(row.get("Charge" + kind, 0))
	return result

func _draw_sheet() -> void:
	super._draw_sheet()
	for piece: Dictionary in _type_pieces: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var font: Font = hud._bold
	if book_pick >= 0: sheet.draw_rect(book_rect(book_pick).grow(1), PICK, false, 2.0)
	for index in range(reserve_scroll * RESERVE_COLUMNS, mini(entries.size(), (reserve_scroll + RESERVE_ROWS) * RESERVE_COLUMNS)):
		var entry := entries[index]
		var rect := reserve_rect(index)
		var allowed := ELSpellInventory.allows(profile, hero(), str(entry.card))
		sheet.draw_texture_rect(profile.card_icon(str(entry.card)), rect, false, WHITE if allowed else Color(0.45, 0.45, 0.45))
		if int(entry.uses) >= 0: _digits(rect, str(int(entry.uses)), font)
		if int(entry.count) > 1:
			var text := "×%d" % int(entry.count)
			sheet.draw_string(font, rect.position + Vector2(4, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.9))
			sheet.draw_string(font, rect.position + Vector2(3, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6e7a8"))
		if index == reserve_pick: sheet.draw_rect(rect.grow(1), PICK, false, 2.0)
	var kinds := ELResources.types("el1")
	var wallet: Dictionary = state.players.get(int(hero().get("owner", 0)), {}).get("resources", {})
	var columns := [rune_price(), wallet]
	for column in 2:
		var values: Dictionary = columns[column]
		for row in kinds.size():
			var text := "-" if values.is_empty() else str(int(values.get(kinds[row], 0)))
			var box := Rect2(Vector2(PRICE_COLUMNS[column], PRICE_TOP + PRICE_STEP * row), PRICE_BOX)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := Vector2(box.get_center().x - width * 0.5, box.position.y + 14)
			sheet.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
			sheet.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)

func _spell_tip(card: String, uses: int) -> String:
	var runes := _t("Unlimited cantrip.") if uses < 0 else (_t("Runes left: %d") % uses)
	return _name(card) + "\n" + profile.card_description(card) + "\n" + runes

func tooltip_at(point: Vector2) -> String:
	var book := book_at(point)
	if book >= 0:
		var uses := int(book_uses(0)[book]) if book < book_uses(0).size() else -1
		return _spell_tip(str(book_cards(0)[book]), uses) + "\n\n" + _t("Right click: move to the reserve.")
	var index := reserve_at(point)
	if index >= 0:
		var entry := entries[index]
		var tip := _spell_tip(str(entry.card), int(entry.uses))
		if int(entry.count) > 1: tip += "\n" + (_t("Copies: %d") % int(entry.count))
		var problem := ""
		if book_cards(0).size() >= ELSpellInventory.book_size(profile): problem = "Move a spell to reserve to make room."
		elif not ELSpellInventory.allows(profile, hero(), str(entry.card)): problem = "This hero cannot use that spell's magic color."
		return tip + "\n\n" + (_t(problem) if not problem.is_empty() else _t("Right click: add to the book."))
	if TIPS.SpellTt2.has_point(point): return _t("Price of one rune of the selected spell")
	if TIPS.SpellTt3.has_point(point) or TIPS.SpellTt4.has_point(point): return _t("Your resources")
	if TIPS.SpellTt1.has_point(point): return profile.text("CtrlTtSpellTt1")
	return super.tooltip_at(point)

func cancel() -> void:
	closed.emit()
