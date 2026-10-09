class_name ELSecondSpellShop
extends RefCounted
## Second-game spell shop screen state (SpellShopScreen) over an ELSpellShop
## trade. The screen lists every copy separately: the hero's reserve ("bag",
## 8x5 cells), the 16-slot active deck (blank slots kept) and the shop stock
## (5x5 cells). Cards are picked with a click and placed with a second click,
## as on the inventory screen; the right button puts a carried card back.
##
## Each card remembers where it came from ("hero" or "shop"). A card on the
## other side of the counter is marked (drawn with a blue tint) and is valued
## at the quote ELSpellShop gives its origin: a shop card costs its full
## price, a hero card is worth half. Buying adds the carried card's value to
## the bill, selling subtracts it, so returning a card refunds it exactly.
##
## OK checks, in the original order, the resources (T_MB_SHOP_NOT_ENOUGH_RESOURCES),
## a full deck (T_MB_SHOP_DECK_NOT_FULL) and at most four copies of a spell in
## the deck (T_MB_SHOP_4_EQUAL_SPELLS_IN_DECK); ELSpellShop.commit then runs
## Hook_OnSpellShopSpellBuyed (a purchase only), Hook_ForbidDialogClose and
## applies the trade.
const DECK_SLOTS := 16
const MAX_COPIES := 4
const SELECT := "Buttons/Select3.wav"
const ERROR := "Buttons/Error.wav"
const NOT_ENOUGH := "T_MB_SHOP_NOT_ENOUGH_RESOURCES"
const DECK_NOT_FULL := "T_MB_SHOP_DECK_NOT_FULL"
const TOO_MANY := "T_MB_SHOP_4_EQUAL_SPELLS_IN_DECK"

var trade: ELSpellShop
## Entries {card, origin}; deck slots hold {} when blank.
var bag: Array[Dictionary] = []
var deck: Array[Dictionary] = []
var shop: Array[Dictionary] = []
## Carried card: "bag", "deck" or "shop" and its index, or "" / -1.
var picked_zone := ""
var picked := -1
## False until the first click; the price fields show "-" until then.
var touched := false
var error := ""
var last_sound := ""

func open(exchange: ELSpellShop) -> void:
	trade = exchange
	var state := trade.state
	var hero := state.object(trade.hero_id)
	bag.clear()
	deck.clear()
	shop.clear()
	for card: String in hero.cards:
		if deck.size() < DECK_SLOTS: deck.append({"card": card, "origin": "hero"})
		else: bag.append({"card": card, "origin": "hero"})
	while deck.size() < DECK_SLOTS: deck.append({})
	# The bag keeps the reserve order: unlike the inventory, the shop does not sort it.
	for card: String in hero.spell_stock:
		for copy in int(hero.spell_stock[card]): bag.append({"card": card, "origin": "hero"})
	for card: String in state.object(trade.shop_id).shop_stock: shop.append({"card": card, "origin": "shop"})
	picked_zone = ""
	picked = -1
	touched = false

func zone(name: String) -> Array[Dictionary]:
	match name:
		"bag": return bag
		"deck": return deck
	return shop

## The carried entry, or {}.
func carried() -> Dictionary:
	if picked_zone.is_empty() or picked < 0 or picked >= zone(picked_zone).size(): return {}
	return zone(picked_zone)[picked]

## A card on the other side of the counter (blue tint).
static func marked(where: String, entry: Dictionary) -> bool:
	if entry.is_empty(): return false
	return entry.origin == ("hero" if where == "shop" else "shop")

## Value of a card for the trade: full price for a shop card, half for a hero card.
func value(entry: Dictionary) -> Dictionary:
	if entry.is_empty(): return ELResources.empty("el2")
	return trade.quote(entry)

## Price of the carried card (the "selected spell" row).
func selected_price() -> Dictionary:
	return value(carried())

## Bill: what bought cards cost minus what sold cards bring.
func bill() -> Dictionary:
	var result := ELResources.empty("el2")
	for where: String in ["bag", "deck", "shop"]:
		for entry: Dictionary in zone(where):
			if not marked(where, entry): continue
			var price := value(entry)
			var sign_value := -1 if where == "shop" else 1
			for kind: String in result: result[kind] += int(price[kind]) * sign_value
	return result

func wallet() -> Dictionary:
	var hero := trade.state.object(trade.hero_id)
	return trade.state.players.get(hero.get("owner"), {}).get("resources", {})

func deck_count() -> int:
	var count := 0
	for entry: Dictionary in deck:
		if not entry.is_empty(): count += 1
	return count

func _sound(name: String) -> String:
	last_sound = name
	return name

func _pick(where: String, index: int) -> String:
	picked_zone = where
	picked = index
	return _sound(SELECT)

func _drop_pick() -> void:
	picked_zone = ""
	picked = -1

## Moves the carried bag or deck card into the shop stock (a sale).
func _sell() -> void:
	var entry := carried()
	if picked_zone == "deck": deck[picked] = {}
	else: bag.remove_at(picked)
	shop.append(entry)

## A click on a bag cell; -1 (or past the last card) is empty space.
func click_bag(index: int) -> String:
	touched = true
	if index >= bag.size(): index = -1
	match picked_zone:
		"bag":
			if index == -1 or index == picked:
				_drop_pick()
				return _sound(SELECT)
			return _pick("bag", index)
		"deck":
			# Anywhere in the bag: the deck card is appended, its slot left blank.
			bag.append(deck[picked])
			deck[picked] = {}
			_drop_pick()
			return _sound(SELECT)
		"shop":
			# Buying into the bag.
			bag.append(shop[picked])
			shop.remove_at(picked)
			_drop_pick()
			return _sound(SELECT)
	if index == -1: return _sound(ERROR)
	return _pick("bag", index)

## A click on deck slot `index` (0..15), or -1 outside the slots.
func click_deck(index: int) -> String:
	touched = true
	if index >= DECK_SLOTS: index = -1
	match picked_zone:
		"bag":
			if index == -1:
				# Outside the slots: into the first blank slot while the deck has room.
				var blank := _first_blank()
				if blank >= 0:
					deck[blank] = bag[picked]
					bag.remove_at(picked)
			else:
				# Swap with the slot; a blank slot just takes the card.
				var previous: Dictionary = deck[index]
				deck[index] = bag[picked]
				if previous.is_empty(): bag.remove_at(picked)
				else: bag[picked] = previous
			_drop_pick()
			return _sound(SELECT)
		"shop":
			# Buying straight into the deck; a card in the slot goes to the bag.
			var target := index if index >= 0 else _first_blank()
			if target >= 0:
				if not deck[target].is_empty(): bag.append(deck[target])
				deck[target] = shop[picked]
				shop.remove_at(picked)
			_drop_pick()
			return _sound(SELECT)
		"deck":
			if index == -1: return ""
			if index == picked:
				_drop_pick()
				return _sound(SELECT)
			var card: Dictionary = deck[picked]
			deck[picked] = deck[index]
			deck[index] = card
			_drop_pick()
			return _sound(SELECT)
	if index == -1: return ""
	if deck[index].is_empty(): return _sound(ERROR)
	return _pick("deck", index)

## A click on a shop cell; -1 (or past the last card) is empty space.
func click_shop(index: int) -> String:
	touched = true
	if index >= shop.size(): index = -1
	match picked_zone:
		"shop":
			if index == -1 or index == picked:
				_drop_pick()
				return _sound(SELECT)
			return _pick("shop", index)
		"bag", "deck":
			_sell()
			_drop_pick()
			return _sound(SELECT)
	if index == -1: return _sound(ERROR)
	return _pick("shop", index)

## Right button: puts a carried card back.
func right_click() -> bool:
	if picked_zone.is_empty(): return false
	_drop_pick()
	_sound(SELECT)
	return true

func _first_blank() -> int:
	for index in DECK_SLOTS:
		if deck[index].is_empty(): return index
	return -1

## The refusal OK shows, in the original order, or "".
func refusal() -> String:
	var total := bill()
	var money := wallet()
	for kind: String in total:
		if int(total[kind]) > int(money.get(kind, 0)): return NOT_ENOUGH
	if deck_count() != DECK_SLOTS: return DECK_NOT_FULL
	var copies := {}
	for entry: Dictionary in deck:
		if entry.is_empty(): continue
		copies[entry.card] = int(copies.get(entry.card, 0)) + 1
		if copies[entry.card] > MAX_COPIES: return TOO_MANY
	return ""

## Writes the screen's lists into the trade (deck in slot order).
func stage() -> void:
	trade.zones = {"book": [], "reserve": [], "shop": []}
	for entry: Dictionary in deck:
		if not entry.is_empty(): trade.zones.book.append({"card": entry.card, "origin": entry.origin, "count": 1})
	for entry: Dictionary in bag: trade._add("reserve", entry.card, entry.origin)
	for entry: Dictionary in shop: trade._add("shop", entry.card, entry.origin)

## OK: "" when the trade closed, a text key for a refusal, "forbidden" when
## the scenario keeps the shop open, or the trade's own error.
func accept() -> String:
	_drop_pick()
	error = refusal()
	if not error.is_empty(): return error
	stage()
	if trade.commit(): return ""
	error = trade.error
	return "forbidden" if error.is_empty() else error

## Cancel: true when the shop may close (Hook_ForbidDialogClose("SpellShop")).
func cancel() -> bool:
	_drop_pick()
	return trade.cancel()
