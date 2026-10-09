class_name ELFirstSpellShopView
extends ELHeroScreenView
## First-game laboratory screen (Controls "SpellShop") composed from the
## original CutParts (1024 set) at the registry ShiftX/ShiftY. The left half is
## the hero panel shared with the HeroScreen; its spellbook shows the shop's
## draft. The right half lists the shop's spells (2 x 8 cells, SShopUp/Down)
## and a price table: the resource column, the selected spell's price for the
## selected book slot, and the total bill or, with ComponentPrice, the rune
## price of the selected spell.
##
## A book click selects the slot to replace, a shop click selects the spell
## (a double click buys it). BuySpell stages the replacement, RetrieveSpell
## undoes the selected slot, AcceptBuy pays and closes, DeclineBuy or Escape
## closes without buying. ELFirstSpellShop keeps the pricing and draft rules.
const PANEL := "SpellShop"
const SHOP_CELL := Vector2(516, 107)
const SHOP_COLUMNS := 2
const SHOP_ROWS := 8
const PRICE_COLUMNS := [400.0, 452.0]
const PRICE_TOP := 162.0
const PRICE_STEP := 35.0
const PRICE_BOX := Vector2(30, 18)
const RED := Color(1, 0, 0)
const WHITE := Color(1, 1, 1)
const PICK := Color("e8e0cc")
const TIPS := {"SpellTt1": Rect2(346, 132, 26, 24), "SpellTt2": Rect2(397, 132, 30, 24), "SpellTt3": Rect2(450, 134, 30, 22), "SpellTt4": Rect2(447, 135, 30, 23)}

var trade: ELFirstSpellShop
## Selected book slot and shop spell; `pick` is -1 when the shop has no spells.
var slot := 0
var pick := 0
## ComponentPrice: false shows the total bill, true the selected spell's rune price.
var rune_price := false
var shop_scroll := 0
var _type_pieces := {"Type1": [], "Type2": []}

func build_shop(owner: ELAdventureDirector, panel: ELAdventureHud, exchange_trade: ELFirstSpellShop) -> void:
	director = owner
	state = owner.state
	hud = panel
	profile = state.map.profile
	trade = exchange_trade
	heroes = [trade.hero_id]
	# The HeroScreen's own right-hand parts (global spells, level-up) are absent.
	exchange = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sheet = Sheet.new()
	sheet.view = self
	sheet.size = Vector2(660, 600)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	_compose()
	_build_side(0)
	_header(Rect2(53, 0, 220, 23), "CtrlSpellHeroCaption", 20)
	# The original sets the shop caption to the laboratory's name on opening.
	_header(Rect2(373, 0, 220, 23), "", 20, ELBuildingScreen.title(profile, state.object(trade.shop_id)))
	_header(Rect2(342, 41, 278, 18), "CtrlSpellShopText1", 17)
	_header(Rect2(342, 59, 278, 18), "CtrlSpellShopText2", 17)
	_button("BuySpell", Vector2.ZERO).pressed.connect(buy)
	_button("RetrieveSpell", Vector2.ZERO).pressed.connect(retrieve)
	_button("AcceptBuy", Vector2.ZERO).pressed.connect(accept)
	_button("DeclineBuy", Vector2.ZERO).pressed.connect(cancel_trade)
	_button("SShopUp", Vector2.ZERO).pressed.connect(func(): scroll_shop(-1))
	_button("SShopDown", Vector2.ZERO).pressed.connect(func(): scroll_shop(1))
	_button("ComponentPrice", Vector2.ZERO).pressed.connect(func(): rune_price = not rune_price; refresh())
	slot = 0
	pick = 0 if not trade.stock.is_empty() else -1
	resized.connect(_layout)
	_layout()
	refresh()

## Panel art in registry order, "Last" pieces on top; the third price
## column's header has a Type1 (bill) and a Type2 (rune price) variant.
func _compose() -> void:
	_pieces.clear()
	var table := profile.table("CutParts")
	var keys: Array = table.keys()
	keys.sort_custom(func(a: Variant, b: Variant): return int(a) < int(b))
	# Generic pieces first, then the 1024 set, then "Last": this order closes
	# the frame (the 1024 border pieces lie over the generic panel corners).
	var generic: Array[Dictionary] = []
	var last: Array[Dictionary] = []
	for key: Variant in keys:
		var row: Dictionary = table[key]
		if str(row.get("Ctrl", "")) != PANEL: continue
		var masks: Variant = row.get("Msk", [])
		if not masks is Array: masks = [masks]
		if masks.has("Res1"): continue
		var piece := hud.cut(row)
		if piece.is_empty(): continue
		if masks.has("Type1") or masks.has("Type2"): _type_pieces["Type1" if masks.has("Type1") else "Type2"].append(piece)
		elif masks.has("Last"): last.append(piece)
		elif not masks.has("Res2"): generic.append(piece)
		else: _pieces.append(piece)
	generic.append_array(_pieces)
	generic.append_array(last)
	_pieces = generic

## Header text, reduced until it fits its original box.
func _header(rect: Rect2, key: String, size: int, text := "") -> Label:
	if text.is_empty(): text = profile.text(key)
	while size > 11 and hud._bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x: size -= 1
	return _label(rect, text, size, CAPTION, hud._bold)

## The ComponentPrice art follows the mode (Type1 bill, Type2 rune price).
func _price_button() -> void:
	var button: ELAdventureHud.CutButton = buttons.ComponentPrice
	var type := "Type2" if rune_price else "Type1"
	var free := hud.rows("ComponentPrice", [type, "Free"])
	var push := hud.rows("ComponentPrice", [type, "Push"])
	var light := hud.rows("ComponentPrice", ["Light", "Free"])
	button.parts = {"normal": hud.cut(free[0]) if not free.is_empty() else {}, "pressed": hud.cut(push[0]) if not push.is_empty() else {},
		"hover": hud.cut(light[0]) if not light.is_empty() else {}, "hover_pressed": {}}
	button.place(Vector2.ZERO)
	var tip := profile.text("CtrlTtComponentPrice")
	if tip != "CtrlTtComponentPrice": button.tooltip_text = tip

func book_cards(_side: int) -> Array:
	return trade.cards

func book_uses(_side: int) -> Array:
	return trade.uses

func shop_rect(index: int) -> Rect2:
	var visible := index - shop_scroll * SHOP_COLUMNS
	return Rect2(SHOP_CELL + Vector2(STEP * (visible % SHOP_COLUMNS), 52 * (visible / SHOP_COLUMNS)), ICON)

func book_rect(index: int) -> Rect2:
	return Rect2(Vector2(29 + 53 * (index % 5), 389 + 52 * (index / 5)), ICON)

func max_scroll() -> int:
	return maxi(0, ceili(trade.stock.size() / float(SHOP_COLUMNS)) - SHOP_ROWS)

func scroll_shop(delta: int) -> void:
	shop_scroll = clampi(shop_scroll + delta, 0, max_scroll())
	refresh()

func shop_at(point: Vector2) -> int:
	for index in range(shop_scroll * SHOP_COLUMNS, mini(trade.stock.size(), (shop_scroll + SHOP_ROWS) * SHOP_COLUMNS)):
		if shop_rect(index).has_point(point): return index
	return -1

func book_at(point: Vector2) -> int:
	for index in mini(15, trade.cards.size()):
		if book_rect(index).has_point(point): return index
	return -1

func press(point: Vector2) -> void:
	var book := book_at(point)
	if book >= 0:
		slot = book
		refresh()
		return
	var index := shop_at(point)
	if index < 0: return
	pick = index
	if double_click: buy()
	else: refresh()

func wheel(point: Vector2, direction: int) -> bool:
	if not Rect2(SHOP_CELL, Vector2(STEP * SHOP_COLUMNS, 52 * SHOP_ROWS)).has_point(point): return false
	scroll_shop(direction)
	return true

func selected_card() -> String:
	return trade.stock[pick] if pick >= 0 and pick < trade.stock.size() else ""

func buy() -> void:
	var card := selected_card()
	if card.is_empty() or slot < 0 or slot >= trade.cards.size(): return
	trade.replace(slot, card)
	refresh()

func retrieve() -> void:
	if slot < 0 or slot >= trade.pending.size() or trade.pending[slot].is_empty(): return
	trade.clear(slot)
	refresh()

func accept() -> void:
	if not trade.commit():
		refresh()
		return
	closed.emit()

func cancel_trade() -> void:
	if trade.cancel(): closed.emit()

## Escape closes the screen without buying.
func cancel() -> void:
	cancel_trade()

func wallet() -> Dictionary:
	return state.players[state.object(trade.hero_id).owner].resources

## The selected spell's price for the selected slot, or {} when it shows "-"
## (no spells, or the slot already holds that spell).
func spell_price() -> Dictionary:
	var card := selected_card()
	if card.is_empty() or slot < 0 or slot >= trade.cards.size() or trade.cards[slot] == card: return {}
	return trade.quote(card, slot)

## The third column: the bill, or the selected spell's rune (Charge) price.
func third_column() -> Dictionary:
	if selected_card().is_empty(): return {}
	if not rune_price: return trade.bill()
	var row: Dictionary = profile.table("CombatSpells").get(selected_card(), {})
	var result := ELResources.empty("el1")
	for kind: String in result: result[kind] = int(row.get("Charge" + kind, 0))
	return result

## Red marks: a price above the stock left after the bill, a bill above the stock.
func price_red(column: int, kind: String) -> bool:
	var money := int(wallet().get(kind, 0))
	if column == 0:
		var price := spell_price()
		return not price.is_empty() and int(price[kind]) > money - int(trade.bill()[kind])
	return not rune_price and not selected_card().is_empty() and int(trade.bill()[kind]) > money

func refresh() -> void:
	_refresh_sides()
	shop_scroll = clampi(shop_scroll, 0, max_scroll())
	slot = clampi(slot, 0, maxi(0, trade.cards.size() - 1))
	if pick >= trade.stock.size(): pick = trade.stock.size() - 1
	var stocked := not trade.stock.is_empty()
	for name: String in ["BuySpell", "RetrieveSpell", "AcceptBuy", "ComponentPrice"]: buttons[name].visible = stocked
	buttons.RetrieveSpell.disabled = slot >= trade.pending.size() or trade.pending[slot].is_empty()
	buttons.AcceptBuy.disabled = not trade.problem().is_empty()
	buttons.SShopUp.disabled = shop_scroll <= 0
	buttons.SShopDown.disabled = shop_scroll >= max_scroll()
	_price_button()
	sheet.queue_redraw()

func _draw_sheet() -> void:
	super._draw_sheet()
	for piece: Dictionary in _type_pieces["Type2" if rune_price else "Type1"]: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	if slot >= 0 and slot < mini(15, trade.cards.size()): sheet.draw_rect(book_rect(slot).grow(1), PICK, false, 2.0)
	for index in range(shop_scroll * SHOP_COLUMNS, mini(trade.stock.size(), (shop_scroll + SHOP_ROWS) * SHOP_COLUMNS)):
		var rect := shop_rect(index)
		sheet.draw_texture_rect(profile.card_icon(trade.stock[index]), rect, false)
		if index == pick: sheet.draw_rect(rect.grow(1), PICK, false, 2.0)
	var font: Font = hud._bold
	var kinds := ELResources.types("el1")
	var columns := [spell_price(), third_column()]
	for column in 2:
		var values: Dictionary = columns[column]
		for row in kinds.size():
			var text := "-" if values.is_empty() else str(int(values[kinds[row]]))
			var box := Rect2(Vector2(PRICE_COLUMNS[column], PRICE_TOP + PRICE_STEP * row), PRICE_BOX)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := Vector2(box.get_center().x - width * 0.5, box.position.y + 14)
			sheet.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
			sheet.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED if not values.is_empty() and price_red(column, kinds[row]) else WHITE)

func tooltip_at(point: Vector2) -> String:
	var index := shop_at(point)
	if index >= 0:
		var row: Dictionary = profile.table("CombatSpells").get(trade.stock[index], {})
		return profile.text(str(row.get("Name", trade.stock[index]))) + "\n" + profile.text(str(row.get("ToolTip", "")))
	for name: String in TIPS:
		if name == ("SpellTt3" if rune_price else "SpellTt4"): continue
		if TIPS[name].has_point(point): return profile.text("CtrlTt" + name)
	return super.tooltip_at(point)
