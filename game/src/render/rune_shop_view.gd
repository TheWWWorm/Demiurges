class_name ELRuneShopView
extends ELHeroScreenView
## First-game component portal (Controls "ComponentShop") composed from the
## original CutParts (1024 set) at the registry ShiftX/ShiftY. The left half is
## the hero panel shared with the HeroScreen; its spellbook shows the rune
## counts including the draft. The right half holds the portal's name and the
## price table: the resource column, the price of one rune for the selected
## book slot and the total cost.
##
## A book click (or the arrow keys: one slot sideways, a row of five up or
## down) selects a spell. CompBuy1/2/3 add one rune, fill the selected spell,
## fill every spell; CompBack1/2/3 return one rune, the selected spell's runes,
## all runes. CompOK pays and closes, CompCancel or Escape closes without
## buying. ELRuneShop keeps the pricing and draft rules.
const PANEL := "ComponentShop"
## The panel's buttons and tooltips carry ShiftX/ShiftY 4/-9 in the registry.
const SHIFT := Vector2(4, -9)
const PRICE_COLUMNS := [462.0, 514.0]
const PRICE_TOP := 167.0
const PRICE_STEP := 35.0
const PRICE_BOX := Vector2(32, 18)
const BOOK_COLUMNS := 5
const RED := Color(1, 0, 0)
const WHITE := Color(1, 1, 1)
const PICK := Color("e8e0cc")
const TIPS := {"CompTt1": Rect2(414, 128, 33, 33), "CompTt2": Rect2(465, 134, 30, 30), "CompTt3": Rect2(517, 128, 30, 30)}
const COMMANDS := ["CompBuy1", "CompBuy2", "CompBuy3", "CompBack1", "CompBack2", "CompBack3", "CompOK", "CompCancel"]

var trade: ELRuneShop
## Selected book slot.
var slot := 0

func build_shop(owner: ELAdventureDirector, panel: ELAdventureHud, exchange_trade: ELRuneShop) -> void:
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
	_header(Rect2(53, 0, 220, 23), profile.text("CtrlCompHeroCaption"), 20)
	# The original sets the caption to the portal's name on opening.
	_header(Rect2(373, 0, 220, 23), ELBuildingScreen.title(profile, state.object(trade.shop_id)), 20)
	_header(Rect2(342, 41, 278, 18), profile.text("CtrlCompShopText1"), 17)
	_header(Rect2(342, 59, 278, 18), profile.text("CtrlCompShopText2"), 17)
	_button("CompBuy1", SHIFT).pressed.connect(func(): _act(trade.change(slot, 1)))
	_button("CompBuy2", SHIFT).pressed.connect(func(): _act(trade.fill(slot)))
	_button("CompBuy3", SHIFT).pressed.connect(func(): _act(trade.fill_all()))
	_button("CompBack1", SHIFT).pressed.connect(func(): _act(trade.change(slot, -1)))
	_button("CompBack2", SHIFT).pressed.connect(func(): _act(trade.clear(slot)))
	_button("CompBack3", SHIFT).pressed.connect(func(): _act(trade.clear()))
	_button("CompOK", SHIFT).pressed.connect(accept)
	_button("CompCancel", SHIFT).pressed.connect(cancel_trade)
	# The arrow keys select book slots, so the buttons never take focus.
	for button: BaseButton in buttons.values(): button.focus_mode = Control.FOCUS_NONE
	slot = 0
	resized.connect(_layout)
	_layout()
	refresh()

## Panel art: generic pieces, then the 1024 set, then "Last" on top.
func _compose() -> void:
	_pieces.clear()
	var table := profile.table("CutParts")
	var keys: Array = table.keys()
	keys.sort_custom(func(a: Variant, b: Variant): return int(a) < int(b))
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
		if masks.has("Last"): last.append(piece)
		elif not masks.has("Res2"): generic.append(piece)
		else: _pieces.append(piece)
	generic.append_array(_pieces)
	generic.append_array(last)
	_pieces = generic

## Header text, reduced until it fits its original box.
func _header(rect: Rect2, text: String, size: int) -> Label:
	while size > 11 and hud._bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x: size -= 1
	return _label(rect, text, size, CAPTION, hud._bold)

func hero() -> Dictionary:
	return state.object(trade.hero_id)

func book_cards(_side: int) -> Array:
	return hero().get("cards", [])

## Rune counts including the draft; cantrips (-1) keep no count.
func book_uses(_side: int) -> Array:
	var uses: Array = hero().get("rune_uses", []).duplicate()
	for index in mini(uses.size(), trade.pending.size()):
		if int(uses[index]) >= 0: uses[index] = int(uses[index]) + trade.pending[index]
	return uses

func book_rect(index: int) -> Rect2:
	return Rect2(Vector2(29 + 53 * (index % BOOK_COLUMNS), 389 + 52 * (index / BOOK_COLUMNS)), ICON)

func book_at(point: Vector2) -> int:
	for index in mini(15, book_cards(0).size()):
		if book_rect(index).has_point(point): return index
	return -1

func press(point: Vector2) -> void:
	var index := book_at(point)
	if index < 0: return
	slot = index
	refresh()

## Arrow keys: -1/+1 sideways, -5/+5 for a row, kept within the book.
func move_selection(delta: int) -> void:
	var target := slot + delta
	if target >= 0 and target < book_cards(0).size(): slot = target
	refresh()

func _act(_ok: bool) -> void:
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
	return state.players[hero().owner].resources

func has_pending() -> bool:
	return trade.pending.any(func(amount: int): return amount > 0)

## Enabled states in the original's order: Buy1 and Buy2 for the selected
## spell, Buy3 for any spell, Back1/Back2 when the selected spell has a draft,
## Back3 when any spell has one, OK when the bill is affordable, Cancel always.
func refresh() -> void:
	_refresh_sides()
	slot = clampi(slot, 0, maxi(0, book_cards(0).size() - 1))
	var selected_pending := slot < trade.pending.size() and trade.pending[slot] > 0
	buttons.CompBuy1.disabled = not trade.can_add(slot)
	buttons.CompBuy2.disabled = not trade.can_add(slot)
	buttons.CompBuy3.disabled = not range(trade.pending.size()).any(func(index: int): return trade.can_add(index))
	buttons.CompBack1.disabled = not selected_pending
	buttons.CompBack2.disabled = not selected_pending
	buttons.CompBack3.disabled = not has_pending()
	buttons.CompOK.disabled = not trade.problem().is_empty()
	buttons.CompCancel.disabled = false
	sheet.queue_redraw()

## The price of one rune for the selected spell, or {} ("-") without one.
func unit_price() -> Dictionary:
	if slot < 0 or slot >= book_cards(0).size(): return {}
	return trade.quote(slot)

## Red marks: a unit price above the stock left after the bill, a bill above
## the stock.
func price_red(column: int, kind: String) -> bool:
	var money := int(wallet().get(kind, 0))
	var bill := trade.bill()
	if column == 0: return int(unit_price().get(kind, 0)) > money - int(bill[kind])
	return int(bill[kind]) > money

func _draw_sheet() -> void:
	super._draw_sheet()
	if slot >= 0 and slot < mini(15, book_cards(0).size()): sheet.draw_rect(book_rect(slot).grow(1), PICK, false, 2.0)
	var font: Font = hud._bold
	var kinds := ELResources.types("el1")
	var columns := [unit_price(), trade.bill() if not book_cards(0).is_empty() else {}]
	for column in 2:
		var values: Dictionary = columns[column]
		for row in kinds.size():
			var text := "-" if values.is_empty() else str(int(values[kinds[row]]))
			var box := Rect2(Vector2(PRICE_COLUMNS[column], PRICE_TOP + PRICE_STEP * row), PRICE_BOX)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := Vector2(box.get_center().x - width * 0.5, box.position.y + 14)
			sheet.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
			sheet.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED if not values.is_empty() and price_red(column, kinds[row]) else WHITE)

func price_rect(column: int, row: int) -> Rect2:
	return Rect2(Vector2(PRICE_COLUMNS[column], PRICE_TOP + PRICE_STEP * row), PRICE_BOX)

func tooltip_at(point: Vector2) -> String:
	for name: String in TIPS:
		if Rect2(TIPS[name].position + SHIFT, TIPS[name].size).has_point(point): return profile.text("CtrlTt" + name)
	var kinds := ELResources.types("el1")
	for row in kinds.size():
		if Rect2(Vector2(415, PRICE_TOP + PRICE_STEP * row - 4), Vector2(26, 26)).has_point(point): return profile.text("T_RESOURCE_NAME_%d" % (row + 1))
	return super.tooltip_at(point)
