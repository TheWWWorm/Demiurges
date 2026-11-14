class_name ELRunes
extends RefCounted
## First-game rune uses belong to owned copies, including copies in reserve.

static func unlimited(profile: ELProfile, hero: Dictionary, card: String) -> bool:
	return hero.get("type", hero.get("kind", "hero")) != "monster" and profile.table("CombatSpells").get(card, {}).get("Rarity") == "Cantrip"

static func capacity(hero: Dictionary) -> int:
	return [5, 7, 10, 15][int(hero.get("skills", {}).get("PRVD", -1)) + 1]

static func initialize(profile: ELProfile, hero: Dictionary, authored: Array = []) -> void:
	hero.rune_uses = []
	hero.rune_stock = {}
	var starting := {}
	if authored.is_empty():
		var name: String = profile.table("HeroTemplates").get(hero.get("name", ""), {}).get("StartDeck", "")
		var cards := ELCatalog.deck(profile, name)
		var counts := ELCatalog.deck_uses(profile, name)
		for index in cards.size():
			if not starting.has(cards[index]): starting[cards[index]] = []
			starting[cards[index]].append(counts[index])
	for index in hero.cards.size():
		var card: String = hero.cards[index]
		var count := int(authored[index]) if index < authored.size() else 0
		if authored.is_empty() and not starting.get(card, []).is_empty(): count = starting[card].pop_front()
		hero.rune_uses.append(-1 if unlimited(profile, hero, card) else maxi(0, count))
	for card: String in hero.spell_stock:
		var counts: Array[int] = []
		counts.resize(int(hero.spell_stock[card]))
		counts.fill(-1 if unlimited(profile, hero, card) else 0)
		hero.rune_stock[card] = counts

static func restore(profile: ELProfile, hero: Dictionary) -> bool:
	if hero.has("rune_uses") != hero.has("rune_stock"): return false
	if not hero.has("rune_uses"): initialize(profile, hero)
	if hero.rune_uses is not Array or hero.rune_uses.size() != hero.cards.size() or hero.rune_stock is not Dictionary: return false
	for index in hero.cards.size():
		if not valid_count(profile, hero, hero.cards[index], hero.rune_uses[index]): return false
		hero.rune_uses[index] = int(hero.rune_uses[index])
	if hero.rune_stock.size() != hero.spell_stock.size(): return false
	for card: Variant in hero.rune_stock:
		if card is not String or not hero.spell_stock.has(card) or hero.rune_stock[card] is not Array or hero.rune_stock[card].size() != int(hero.spell_stock[card]): return false
		for index in hero.rune_stock[card].size():
			if not valid_count(profile, hero, card, hero.rune_stock[card][index]): return false
			hero.rune_stock[card][index] = int(hero.rune_stock[card][index])
	if hero.has("rune_under"):
		if hero.rune_under is not Array: return false
		for code: Variant in hero.rune_under:
			if code is not String or (not code.is_empty() and not unlimited(profile, hero, code)): return false
		# A book changed by a path that does not keep the list loses it.
		if hero.rune_under.size() != hero.cards.size() or hero.rune_under.all(func(code: String): return code.is_empty()): hero.erase("rune_under")
	return true

## The cantrip waiting under each book slot ("" for none), one per slot.
## Bought over a cantrip, a laboratory spell keeps it underneath; when that
## spell's runes are spent in a battle, the cantrip takes the slot back.
static func under(hero: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var kept: Variant = hero.get("rune_under", [])
	if kept is Array and kept.size() == hero.get("cards", []).size(): result.assign(kept)
	else:
		result.resize(hero.get("cards", []).size())
		result.fill("")
	return result

static func set_under(hero: Dictionary, codes: Array) -> void:
	if codes.any(func(code: String): return not code.is_empty()): hero.rune_under = codes.duplicate()
	else: hero.erase("rune_under")

## After a battle (`before`: the book's runes when it began): a slot whose
## spell spent its last rune gives the slot back to the cantrip under it.
static func return_cantrips(hero: Dictionary, before: Array) -> void:
	if not hero.has("rune_under"): return
	var codes := under(hero)
	for slot in mini(codes.size(), hero.get("rune_uses", []).size()):
		if codes[slot].is_empty() or slot >= before.size() or int(before[slot]) <= 0 or int(hero.rune_uses[slot]) != 0: continue
		hero.cards[slot] = codes[slot]
		hero.rune_uses[slot] = -1
		codes[slot] = ""
	set_under(hero, codes)

static func valid_count(profile: ELProfile, hero: Dictionary, card: String, value: Variant) -> bool:
	if unlimited(profile, hero, card): return ELLuaSave._integer(value, -1, -1)
	return ELLuaSave._integer(value, 0, ELResources.MAX_AMOUNT)
