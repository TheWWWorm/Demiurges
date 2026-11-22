extends SceneTree
## Regression check for #293: the first game's laboratory raises a spell's
## price with every other copy the hero keeps, reserve copies included.
##
## The original's quote counts the copies in the
## hero's spell list except the replaced slot, whose purchase overwrites it,
## and multiplies the base price by 1, 2, 3, 5, 10, ... for that count. The
## remake keeps a reserve and sends a replaced spell there, so:
## - copies in the reserve count like copies in the book;
## - copies the purchase draft sends from the book to the reserve count,
##   including the replaced slot's own copy when buying the same spell over it;
## - storing a bought copy in the reserve no longer resets the price;
## - with an empty reserve and other spells replaced the original prices stay;
## - the computer's price estimate (the static price) sees the reserve too.
##
##   godot --headless --path game --script ../tools/issues_293_check.gd
##
## Needs Etherlords (user://profiles.json); skipped without it. Nothing is saved.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: Etherlords files are not configured")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: Etherlords files could not be mounted")
		quit(0)
		return
	_prices(profile)
	print("ISSUE 293: %d failure(s)" % failures)
	quit(int(failures > 0))

## A campaign mission with the player's hero, a laboratory selling it at least
## two rune spells, and a book of cantrips.
func _session(profile: ELProfile) -> Dictionary:
	var ids := ELCampaign.available(profile)
	var campaign := ELCampaign.new()
	if ids.is_empty() or not campaign.load_campaign(profile, ids[0]): return {}
	for mission in mini(10, campaign.scenarios.size()):
		var map := ELAdventureMap.new()
		if not map.load_map(profile, str(campaign.scenarios[mission].file_name)): continue
		var state := ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, false): continue
		var hero_id := -1
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player:
				hero_id = int(item.uid)
				break
		var hero := state.object(hero_id)
		if hero_id < 0 or not hero.cards.all(func(code: String) -> bool: return ELRunes.unlimited(profile, hero, code)): continue
		for item: Dictionary in state.objects.values():
			if item.get("group") != "laboratories": continue
			var trade := ELFirstSpellShop.new()
			if not trade.open(state, hero_id, int(item.uid), true): continue
			var spells: Array = []
			for card: String in trade.stock:
				if not ELRunes.unlimited(profile, hero, card) and not spells.has(card): spells.append(card)
			trade.cancel()
			if spells.size() >= 2 and not trade.free_exchange(): return {"state": state, "hero": hero_id, "shop": int(item.uid), "spells": spells}
		state.close()
	return {}

## The base price times the multiplier for `copies` other copies.
static func expected(profile: ELProfile, hero: Dictionary, card: String, copies: int) -> Dictionary:
	var result := ELResources.empty("el1")
	var row: Dictionary = profile.table("CombatSpells")[card]
	var multiplier: int = ELFirstSpellShop.COPY_MULTIPLIERS[mini(copies, ELFirstSpellShop.COPY_MULTIPLIERS.size() - 1)]
	for kind: String in result:
		result[kind] = ELResources.bargain_price(float(row.get("Cost" + kind, 0)) * multiplier, int(hero.get("skills", {}).get("BARG", -1)))
	return result

static func _sum(prices: Array) -> Dictionary:
	var result := ELResources.empty("el1")
	for price: Dictionary in prices:
		for kind: String in result: result[kind] += int(price[kind])
	return result

func _open(session: Dictionary) -> ELFirstSpellShop:
	var trade := ELFirstSpellShop.new()
	return trade if trade.open(session.state, session.hero, session.shop, true) else null

func _prices(profile: ELProfile) -> void:
	var session := _session(profile)
	check(not session.is_empty(), "a campaign mission has a laboratory selling rune spells to a hero with a book of cantrips")
	if session.is_empty(): return
	var state: ELAdventureSession = session.state
	var hero := state.object(session.hero)
	for kind: String in state.players[hero.owner].resources: state.players[hero.owner].resources[kind] = 1000000
	var card: String = session.spells[0]
	var other: String = session.spells[1]
	var price := func(copies: int) -> Dictionary: return expected(profile, hero, card, copies)
	check(price.call(1) != price.call(0), "%s costs more for a second copy" % card)

	# The original's prices: no copy, then copies in other book slots.
	var trade := _open(session)
	check(trade.quote(card, 1) == price.call(0), "first copy: the base price")
	trade.replace(0, card)
	check(trade.quote(card, 1) == price.call(1), "one copy in another book slot (staged): the second price")
	check(trade.bill() == price.call(0), "bill of one copy: the base price")
	check(trade.commit(), "the first copy is bought")
	trade = _open(session)
	check(trade.quote(card, 1) == price.call(1), "one copy in the book: the second price")
	trade.replace(1, other)
	check(trade.bill() == expected(profile, hero, other, 0), "another spell over a cantrip: its base price")
	trade.cancel()

	# The report: copies in the reserve were not counted.
	check(state.move_spell(session.hero, card, 0), "the bought copy goes to the reserve from the book")
	check(int(hero.spell_stock.get(card, 0)) == 1 and not hero.cards.has(card), "the copy is in the reserve only")
	trade = _open(session)
	check(trade.quote(card, 1) == price.call(1), "one copy in the reserve: the second price (it was the base price)")
	trade.replace(1, card)
	check(trade.bill() == price.call(1), "bill for a copy with one in the reserve: the second price")
	check(trade.commit(), "the second copy is bought")
	check(ELSpellInventory.add(profile, hero, card, 2), "two more copies stored in the reserve")
	trade = _open(session)
	check(trade.quote(card, 2) == price.call(4), "one copy in the book and three in the reserve: the fifth price")
	check(ELFirstSpellShop.price(profile, hero, hero.cards, card, 2) == price.call(4), "the computer's estimate counts the reserve too")
	trade.replace(2, card)
	trade.replace(3, card)
	check(trade.bill() == _sum([price.call(4), price.call(5)]), "two staged copies with four kept: the fifth and sixth prices")
	trade.cancel()

	# The replaced slot's copy goes to the reserve, so buying it again counts it.
	trade = _open(session)
	var held: int = hero.cards.find(card)
	check(held >= 0, "a copy is in the book")
	trade.replace(held, card)
	check(trade.bill() == price.call(4), "the same spell bought over its own slot counts that copy: the fifth price")
	trade.clear()
	# A copy sent to the reserve by this draft counts for a later slot.
	trade.replace(held, other)
	var later := 5 if held != 5 else 6
	trade.replace(later, card)
	check(trade.bill() == _sum([expected(profile, hero, other, 0), price.call(4)]), "a copy replaced in the same draft still counts for the next purchase")
	check(trade.quote(card, later) == price.call(4), "the shown price matches the bill")
	trade.cancel()
	state.close()
