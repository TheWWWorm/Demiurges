class_name ELRunes
extends RefCounted
## First-game rune uses belong to owned copies, including copies in reserve.

static func unlimited(profile: ELProfile, hero: Dictionary, card: String) -> bool:
	return hero.get("type", hero.get("kind", "hero")) != "monster" and profile.table("CombatSpells").get(card, {}).get("Rarity") == "Cantrip"

static func capacity(hero: Dictionary) -> int:
	return [5, 7, 10, 15][int(hero.get("skills", {}).get("PRVD", -1)) + 1]

static func initialize(profile: ELProfile, hero: Dictionary, authored: Array = []) -> void:
	# A new book has nothing waiting under its slots.
	hero.erase("rune_under")
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
## Bought over a cantrip, a laboratory spell keeps it underneath. A spell that
## spends its last rune stays in the book with none, as in the original; in a
## battle the cantrip under it is drawn in its place (ELSpellCharges), and it
## takes the slot back only when the spell is stored in the reserve.
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

## Saves from before the book kept its cantrips (a laboratory spell simply
## overwrote one, before 0.13.0) lost the cantrip under a bought spell, so
## storing that spell took the slot away. `start` is the book the hero began
## the mission with: a cantrip it began with and no longer has, in the book
## or under a spell, goes back under a spell that is not one of the starting
## book's own; first the spell in that cantrip's starting slot, then a spell
## of its colour and class (the cantrip a spent spell falls back to), then
## any. No other cantrip is given and the book keeps its size.
static func adopt_lost_cantrips(profile: ELProfile, hero: Dictionary, start: Array) -> void:
	if hero.get("type", "hero") != "hero" or not hero.has("rune_uses"): return
	var cards: Array = hero.get("cards", [])
	var codes := under(hero)
	var missing := {}
	for card: Variant in start:
		if card is String and unlimited(profile, hero, card): missing[card] = int(missing.get(card, 0)) + 1
	for card: Variant in cards + codes:
		if missing.has(card): missing[card] = int(missing[card]) - 1
	var open: Array[int] = []
	for slot in cards.size():
		if codes[slot].is_empty() and not unlimited(profile, hero, str(cards[slot])) and not (slot < start.size() and start[slot] == cards[slot]): open.append(slot)
	var spells := profile.table("CombatSpells")
	var same_kind := func(cantrip: String, card: String) -> bool:
		var a: Dictionary = spells.get(cantrip, {})
		var b: Dictionary = spells.get(card, {})
		return a.get("Color") == b.get("Color") and a.get("Class") == b.get("Class")
	for step in 3:
		for slot: int in open.duplicate():
			var choice := ""
			if step == 0:
				if slot < start.size() and int(missing.get(start[slot], 0)) > 0: choice = str(start[slot])
			else:
				for card: Variant in start:
					if int(missing.get(card, 0)) > 0 and (step == 2 or same_kind.call(card, str(cards[slot]))):
						choice = str(card)
						break
			if choice.is_empty(): continue
			codes[slot] = choice
			missing[choice] = int(missing[choice]) - 1
			open.erase(slot)
	set_under(hero, codes)

## The basic spells a hero of `colour` is meant to begin with: the starting
## book of that colour's hireable heroes (templates that are no quest hero),
## where it is all cantrips (EL1 Red: STR1, 4 Strength, 3 Fire Wall, 4 Shock,
## 4 Lesser Strength). Empty when the game has none.
static func basic_book(profile: ELProfile, colour: String) -> Array[String]:
	var templates: Dictionary = profile.table("HeroTemplates")
	var votes := {}
	for name: String in templates:
		var row: Dictionary = templates[name]
		if str(row.get("Color", "")) != colour or str(row.get("Quest", "")) != "-": continue
		var deck := str(row.get("StartDeck", ""))
		votes[deck] = int(votes.get(deck, 0)) + 1
	var best := ""
	for deck: String in votes:
		if best.is_empty() or int(votes[deck]) > int(votes[best]): best = deck
	var result: Array[String] = []
	var hero := {"type": "hero"}
	for card: String in ELCatalog.deck(profile, best):
		if not unlimited(profile, hero, card): return []
		result.append(card)
	return result

## A hero freed from a prison begins with a book of the chapter's spells and
## no cantrip of its own (Thaereid, Mauleen). Its colour's basic spells go
## under that book, slot by slot, so a stored spell leaves the slot to a
## basic spell and a spent one draws it in battle, as for any hero (#167).
## The book itself is unchanged.
static func give_basic_under(profile: ELProfile, hero: Dictionary) -> void:
	# Once: a later load does not give them again.
	if hero.get("basic_under", false): return
	hero.basic_under = true
	var cards: Array = hero.get("cards", [])
	if cards.any(func(card: String) -> bool: return unlimited(profile, hero, card)): return
	var colour := str(profile.table("HeroTemplates").get(hero.get("name", ""), {}).get("Color", ""))
	var basic := basic_book(profile, colour)
	if basic.is_empty(): return
	var codes := under(hero)
	for slot in mini(codes.size(), basic.size()):
		if codes[slot].is_empty(): codes[slot] = basic[slot]
	set_under(hero, codes)

static func valid_count(profile: ELProfile, hero: Dictionary, card: String, value: Variant) -> bool:
	if unlimited(profile, hero, card): return ELLuaSave._integer(value, -1, -1)
	return ELLuaSave._integer(value, 0, ELResources.MAX_AMOUNT)
