class_name ELSpellShop
extends RefCounted
## EL2 trades stage distinct copies, so reversing a transfer refunds its exact
## quote. A sold copy remains in that particular shop after accepting the trade.
var state: ELAdventureSession
var hero_id := -1
var shop_id := -1
var zones := {"book": [], "reserve": [], "shop": []}
var error := ""
var finished := false
var _before: Dictionary

static func authored_stock(profile: ELProfile, node: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for tier: Dictionary in ELXml.children(node, "spells"):
		for spell: Dictionary in ELXml.children(tier, "spell"):
			var code := str(spell.get("text", "")).strip_edges()
			if ELSpellInventory.is_spell(profile, code): result.append(code)
	return result

func open(session: ELAdventureSession, actor: int, building: int) -> bool:
	state = session
	hero_id = actor
	shop_id = building
	error = ""
	finished = false
	var hero := state.object(hero_id)
	var shop := state.object(shop_id)
	if state.map.profile.id != "el2": return _fail("This edition's shop rules are not available yet.")
	if hero.is_empty() or hero.type != "hero" or not hero.alive or hero.owner != state.current_player: return _fail("This hero cannot trade.")
	if shop.is_empty() or shop.group != "laboratories" or not shop.alive or not shop.visible or not shop.enabled: return _fail("This shop is unavailable.")
	if not state.players.has(hero.owner): return _fail("This hero has no resource balance.")
	_before = {"book": hero.cards.duplicate(), "reserve": hero.spell_stock.duplicate(), "shop": shop.shop_stock.duplicate()}
	zones = {"book": [], "reserve": [], "shop": []}
	for card: String in hero.cards: _add("book", card, "hero")
	for card: String in hero.spell_stock:
		_add("reserve", card, "hero", int(hero.spell_stock[card]))
	for card: String in shop.shop_stock: _add("shop", card, "shop")
	return true

func _add(zone: String, card: String, origin: String, count := 1) -> void:
	if count <= 0: return
	if zone != "book":
		for entry: Dictionary in zones[zone]:
			if entry.card == card and entry.origin == origin:
				entry.count += count
				return
	zones[zone].append({"card": card, "origin": origin, "count": count})

func quote(entry: Dictionary) -> Dictionary:
	var result := ELResources.spell_price(state.map.profile, str(entry.card))
	if entry.origin == "hero":
		for kind: String in result: result[kind] = int(result[kind]) / 2
	return result

func move(from: String, index: int, to: String) -> bool:
	error = ""
	if finished or from == to or not zones.has(from) or not zones.has(to) or index < 0 or index >= zones[from].size(): return _fail("Select a spell to move.")
	var entry: Dictionary = zones[from][index]
	if to == "book":
		if zones.book.size() >= ELSpellInventory.BOOK_SIZE: return _fail("The spellbook already contains 16 spells.")
		# No colour gate: neither the transfer nor acceptance tests colour
		# or the hero's colour bans (has no shop caller).
	entry.count -= 1
	if entry.count == 0: zones[from].remove_at(index)
	_add(to, entry.card, entry.origin)
	return true

func bill() -> Dictionary:
	var result := ELResources.empty(state.map.profile.id)
	for zone: String in zones:
		for entry: Dictionary in zones[zone]:
			var sign_value := -1 if zone == "shop" and entry.origin == "hero" else (1 if zone != "shop" and entry.origin == "shop" else 0)
			if sign_value == 0: continue
			var price := quote(entry)
			for kind: String in result: result[kind] += int(price[kind]) * sign_value * int(entry.count)
	return result

func problem() -> String:
	if finished: return "This trade has already closed."
	var hero := state.object(hero_id)
	var shop := state.object(shop_id)
	if not hero.get("alive", false) or hero.get("owner") != state.current_player or not shop.get("alive", false) or not shop.get("enabled", false): return "The trade is no longer available."
	if hero.cards != _before.book or hero.spell_stock != _before.reserve or shop.shop_stock != _before.shop: return "The inventory changed. Reopen the shop to trade."
	var wallet: Dictionary = state.players.get(hero.owner, {}).get("resources", {})
	var total := bill()
	for kind: String in total:
		if int(wallet.get(kind, 0)) < int(total[kind]): return "Not enough resources for this trade."
		if int(wallet.get(kind, 0)) - int(total[kind]) > ELResources.MAX_AMOUNT: return "The resource balance would exceed its limit."
	if zones.book.size() != ELSpellInventory.BOOK_SIZE: return "Equip exactly 16 spells before accepting the trade."
	var copies := {}
	for entry: Dictionary in zones.book:
		copies[entry.card] = int(copies.get(entry.card, 0)) + 1
		if copies[entry.card] > 4: return "The spellbook can contain at most four copies of a spell."
	var reserve_counts := {}
	for entry: Dictionary in zones.reserve:
		reserve_counts[entry.card] = int(reserve_counts.get(entry.card, 0)) + int(entry.count)
		if reserve_counts[entry.card] > ELSpellInventory.MAX_COPIES: return "The reserve would exceed its limit."
	var stock_count := 0
	for entry: Dictionary in zones.shop: stock_count += int(entry.count)
	if stock_count > 100000: return "The shop stock would exceed its limit."
	return ""

func commit() -> bool:
	error = problem()
	if not error.is_empty(): return false
	var total := bill()
	var purchase := false
	for amount: int in total.values():
		if amount > 0: purchase = true
	if purchase and not state.hook("Hook_OnSpellShopSpellBuyed"): return _fail(state.error)
	if not _close_hook(): return false
	# A scenario hook can mutate balances; recheck before changing any inventory.
	error = problem()
	if not error.is_empty(): return false
	var hero := state.object(hero_id)
	var wallet: Dictionary = state.players[hero.owner].resources
	for kind: String in total: wallet[kind] = int(wallet.get(kind, 0)) - int(total[kind])
	hero.cards.clear()
	hero.spell_stock.clear()
	state.object(shop_id).shop_stock.clear()
	for entry: Dictionary in zones.book: hero.cards.append(entry.card)
	for entry: Dictionary in zones.reserve: ELSpellInventory.add(state.map.profile, hero, entry.card, entry.count)
	for entry: Dictionary in zones.shop:
		for copy in int(entry.count): state.object(shop_id).shop_stock.append(entry.card)
	finished = true
	state.event.emit({"kind": "trade_finished", "hero": hero_id, "shop": shop_id})
	return true

func cancel() -> bool:
	if finished: return false
	if not _close_hook(): return false
	finished = true
	return true

## Hook_ForbidDialogClose("SpellShop") at OK and Cancel:
## a missing hook or a script error allows closing; a true result keeps the
## shop open (the script shows its own message box).
func _close_hook() -> bool:
	if state.vm == null or not state.vm.has_function("Hook_ForbidDialogClose"): return true
	var result := state.vm.invoke("Hook_ForbidDialogClose", ["SpellShop"])
	if not state.vm.error.is_empty():
		push_warning("Hook_ForbidDialogClose: " + state.vm.error)
		state.vm.error = ""
		return true
	if not result.is_empty() and ELAdventureSession._truthy_flag(result[0]): return _fail("")
	return true

func _fail(message: String) -> bool:
	error = message
	return false
