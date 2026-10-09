class_name ELSecondInventory
extends RefCounted
## Second-game hero bag (InventoryScreen). The screen edits a copy of the
## hero's reserve ("bag", one entry per copy) and of the 16-slot active deck;
## OK validates and commits, Cancel discards. Original behaviour
## (the original):
## - pick/place state machine: bag click, deck click,
##   right-click drop; the deck is a fixed grid with blank slots;
## - Hook_OnInventorySpellMoved only after a bag card is placed in
##   the deck;
## - OK (0xeb1): deck must hold 16 cards (T_MB_SHOP_DECK_NOT_FULL)
##   with at most four copies of a spell (T_MB_SHOP_4_EQUAL_SPELLS_IN_DECK,
## ), then Hook_ForbidDialogClose("Inventory"), then commit
##   (: reserve, deck in slot order, active specialisation);
## - Cancel (0xeb2, Esc): Hook_ForbidDialogClose("InventoryCancel"), no commit;
## - no colour gate on moves; banned colours are tinted and sorted
##   first in the bag.
const DECK_SLOTS := 16
const MAX_COPIES := 4
const COLORS := ["Red", "Green", "Blue", "Black", "White"]
const SELECT := "Buttons/Select3.wav"
const ERROR := "Buttons/Error.wav"

var state: ELAdventureSession
var hero_id := -1
var deck: Array[String] = []
var bag: Array[String] = []
var specialization := "NONE"
## Carried card: "bag" or "deck" and its index, or "" / -1.
var picked_zone := ""
var picked := -1
var error := ""
var moves := 0
var last_sound := ""

func open(session: ELAdventureSession, id: int) -> bool:
	state = session
	hero_id = id
	error = ""
	var hero := state.object(hero_id)
	if hero.is_empty() or hero.get("type") != "hero": return _fail("This hero's bag is unavailable.")
	deck.clear()
	bag.clear()
	for card: String in hero.cards:
		# A book larger than the deck grid keeps its extra cards in the bag
		# (remake safeguard; player heroes never exceed 16).
		if deck.size() < DECK_SLOTS: deck.append(card)
		else: bag.append(card)
	while deck.size() < DECK_SLOTS: deck.append("")
	for card: String in hero.spell_stock:
		for copy in int(hero.spell_stock[card]): bag.append(card)
	bag = sorted_bag(state.map.profile, hero, bag)
	specialization = str(hero.get("specialization", "NONE"))
	picked_zone = ""
	picked = -1
	moves = 0
	return true

## Bag order at opening: banned colours first, then colour, rarity
## and class; equal keys keep their reserve order. Rarity follows the game's
## enum (Cantrip, Common, Rare, Unique); colour and class ids are not resolved
## and follow COLORS and the class list.
static func sorted_bag(profile: ELProfile, hero: Dictionary, cards: Array[String]) -> Array[String]:
	var spells := profile.table("CombatSpells")
	var keyed: Array = []
	for index in cards.size():
		var row: Dictionary = spells.get(cards[index], {})
		var color := str(row.get("Color", ""))
		keyed.append([0 if banned(hero, cards[index], profile) else 1, COLORS.find(color) if COLORS.has(color) else COLORS.size(),
			["Cantrip", "Common", "Rare", "Unique"].find(str(row.get("Rarity", ""))), ["Creature", "Enchantment", "Sorcery"].find(str(row.get("Class", ""))), index, cards[index]])
	keyed.sort_custom(func(a: Array, b: Array):
		for k in 5:
			if a[k] != b[k]: return a[k] < b[k]
		return false)
	var result: Array[String] = []
	for entry: Array in keyed: result.append(entry[5])
	return result

## Colour excluded by the scenario (ExAllowCardColor false).
static func banned(hero: Dictionary, card: String, profile: ELProfile) -> bool:
	var color := str(profile.table("CombatSpells").get(card, {}).get("Color", ""))
	return color in COLORS and not hero.get("allowed_colors", {}).get(color, true)

func carried() -> String:
	if picked_zone == "bag" and picked >= 0 and picked < bag.size(): return bag[picked]
	if picked_zone == "deck" and picked >= 0 and picked < deck.size(): return deck[picked]
	return ""

func deck_count() -> int:
	var count := 0
	for card: String in deck:
		if not card.is_empty(): count += 1
	return count

func _pick(zone: String, index: int) -> String:
	picked_zone = zone
	picked = index
	return _sound(SELECT)

func _drop_pick() -> void:
	picked_zone = ""
	picked = -1

func _sound(name: String) -> String:
	last_sound = name
	return name

## A click on the bag; index -1 (or past the last card) is empty space.
func click_bag(index: int) -> String:
	if index >= bag.size(): index = -1
	if picked_zone == "bag":
		if index == -1 or index == picked:
			_drop_pick()
			return _sound(SELECT)
		return _pick("bag", index)
	if picked_zone == "deck":
		# A deck card returns to the bag (appended, not re-sorted); its slot
		# stays blank. No inventory hook on this path.
		var card := deck[picked]
		deck[picked] = ""
		bag.append(card)
		_drop_pick()
		return _sound(SELECT)
	if index == -1: return _sound(ERROR)
	return _pick("bag", index)

## A click on deck slot `index` (0..15), or -1 outside the slots.
func click_deck(index: int) -> String:
	if index >= DECK_SLOTS: index = -1
	if picked_zone == "bag":
		if index >= 0:
			# Swap the carried bag card with the slot; a blank slot just takes it.
			var from_bag := bag[picked]
			var from_deck := deck[index]
			deck[index] = from_bag
			if from_deck.is_empty(): bag.remove_at(picked)
			else: bag[picked] = from_deck
			moves += 1
			_drop_pick()
			if not state.hook("Hook_OnInventorySpellMoved"): error = state.error
			return _sound(SELECT)
		_drop_pick()
		return _sound(SELECT)
	if picked_zone == "deck":
		if index == -1: return ""
		if index == picked:
			_drop_pick()
			return _sound(SELECT)
		var card := deck[picked]
		deck[picked] = deck[index]
		deck[index] = card
		_drop_pick()
		return _sound(SELECT)
	if index == -1: return ""
	if deck[index].is_empty(): return _sound(ERROR)
	return _pick("deck", index)

## Right mouse button: the carried card goes back.
func right_click() -> bool:
	if picked_zone.is_empty(): return false
	_drop_pick()
	_sound(SELECT)
	return true

## Text id of the OK refusal, or "".
func problem() -> String:
	if deck_count() != DECK_SLOTS: return "T_MB_SHOP_DECK_NOT_FULL"
	var copies := {}
	for card: String in deck:
		copies[card] = int(copies.get(card, 0)) + 1
		if copies[card] > MAX_COPIES: return "T_MB_SHOP_4_EQUAL_SPELLS_IN_DECK"
	return ""

## Hook_ForbidDialogClose(name): a missing hook allows closing; nil,
## false and 0 allow; any other result forbids.
func forbidden(name: String) -> bool:
	if state.vm == null or not state.vm.has_function("Hook_ForbidDialogClose"): return false
	var result: Array = state.vm.invoke("Hook_ForbidDialogClose", [name])
	if not state.vm.error.is_empty():
		error = state.vm.error
		return false
	if result.is_empty() or result[0] == null or result[0] is bool and not result[0]: return false
	if result[0] is float or result[0] is int: return result[0] != 0
	return true

## OK: "" when the screen may close (and the edits were committed), otherwise
## the refusal text id or "forbidden" when the script keeps the window open.
func accept() -> String:
	error = ""
	_drop_pick()
	var refusal := problem()
	if not refusal.is_empty(): return refusal
	if forbidden("Inventory"): return "forbidden"
	var hero := state.object(hero_id)
	hero.cards.clear()
	for card: String in deck:
		if not card.is_empty(): hero.cards.append(card)
	hero.spell_stock.clear()
	for card: String in bag: hero.spell_stock[card] = int(hero.spell_stock.get(card, 0)) + 1
	if specialization != str(hero.get("specialization", "NONE")) and state.specializations(hero).has(specialization):
		state.choose_specialization(hero_id, specialization)
	state.event.emit({"kind": "inventory_changed", "id": hero_id})
	return ""

## Cancel / Esc: true when the screen may close; nothing is committed.
func cancel() -> bool:
	error = ""
	_drop_pick()
	return not forbidden("InventoryCancel")

func _fail(message: String) -> bool:
	error = message
	return false
