class_name ELSpellCharges
extends RefCounted
## Charges belong to individual book slots. Cards in hand reserve, not spend, them.

static func providence(skills: Dictionary) -> int:
	return [1, 2, 4, 7][int(skills.get("PRVD", -1)) + 1]

static func initial(profile: ELProfile, hero: Dictionary, adventure: bool, choice: Dictionary = {}) -> Array[int]:
	var uses: Array[int] = []
	uses.resize(hero.deck.size())
	if profile.id == "el1":
		uses.fill(0 if adventure else ELRunes.capacity(hero))
		var authored: Variant = choice.get("rune_uses", [])
		if authored is not Array: return []
		if choice.has("rune_uses"):
			if authored.size() != hero.deck.size(): return []
			for index in authored.size():
				if not ELRunes.valid_count(profile, hero, hero.deck[index], authored[index]): return []
		if not choice.has("cards"): authored = ELCatalog.deck_uses(profile, str(choice.get("deck", ELCatalog.STARTERS.get(hero.faction, ""))))
		for index in uses.size():
			if index < authored.size(): uses[index] = int(authored[index])
			if ELRunes.unlimited(profile, hero, hero.deck[index]): uses[index] = -1
	else:
		# Every second-game battle start (adventure, Duel mode, replays) sets
		# each book slot of both sides from that hero's Providence rank
		# 1/2/4/7. Authored deck use counts never
		# reach the battle.
		uses.fill(providence(hero.skills))
	return uses

static func available(hero: Dictionary) -> Array[int]:
	var weights: Array[int] = []
	weights.assign(hero.spell_uses)
	for slot: int in hero.hand_slots:
		if slot >= 0 and weights[slot] > 0: weights[slot] -= 1
	return weights

static func choose(hero: Dictionary, random_index: Callable) -> int:
	var weights := available(hero)
	var total := 0
	for count: int in weights: total += count
	if total <= 0: return -1
	if hero.get("kind", "hero") == "monster":
		var pick: int = random_index.call(total)
		for slot in weights.size():
			pick -= weights[slot]
			if pick < 0: return slot
		return -1
	var eligible: Array[int] = []
	for slot in weights.size():
		if weights[slot] > 0 and not hero.drawn.has(slot): eligible.append(slot)
	if eligible.is_empty():
		hero.drawn.clear()
		for slot in weights.size():
			if weights[slot] > 0: eligible.append(slot)
	var slot: int = eligible[random_index.call(eligible.size())]
	hero.drawn.append(slot)
	return slot

static func choose_el1(hero: Dictionary, spells: Dictionary, random_index: Callable) -> Dictionary:
	if hero.deck.is_empty(): return {}
	if hero.get("kind", "hero") == "monster":
		var monster_slot := choose(hero, random_index)
		return {} if monster_slot < 0 else {"card": hero.deck[monster_slot], "slot": monster_slot}
	if hero.drawn.size() == hero.deck.size(): hero.drawn.clear()
	var eligible: Array[int] = []
	for index in hero.deck.size():
		if not hero.drawn.has(index): eligible.append(index)
	var slot: int = eligible[random_index.call(eligible.size())]
	hero.drawn.append(slot)
	var card: String = hero.deck[slot]
	var spell: Dictionary = spells[card]
	if spell.get("Rarity") == "Cantrip": return {"card": card, "slot": -1}
	if hero.spell_uses[slot] > hero.hand_slots.count(slot): return {"card": card, "slot": slot}
	var substitutes: Array[String] = []
	# Preserve registry order: the original enumerates its loaded spell table.
	for code: String in spells:
		var candidate: Dictionary = spells[code]
		if candidate.get("Rarity") == "Cantrip" and candidate.get("Color") == spell.get("Color") and candidate.get("Class") == spell.get("Class"):
			substitutes.append(code)
	if substitutes.is_empty(): return {}
	return {"card": substitutes[random_index.call(substitutes.size())], "slot": -1}

static func migrate(profile: ELProfile, hero: Dictionary, setup: Dictionary, side: int) -> void:
	# Old saves did not record spent charges or card origins. Preserve their hand
	# as generated cards and initialize the book once; do not guess spent history.
	var players: Variant = setup.get("players", [{}, {}])
	var choice: Dictionary = players[side] if players is Array and players.size() == 2 and players[side] is Dictionary else {}
	hero.spell_uses = initial(profile, hero, bool(setup.get("adventure", false)), choice)
	hero.hand_slots = []
	hero.hand_slots.resize(hero.hand.size())
	hero.hand_slots.fill(-1)

static func valid(profile: ELProfile, hero: Dictionary) -> bool:
	if hero.get("spell_uses") is not Array or hero.spell_uses.size() != hero.deck.size(): return false
	if hero.get("hand_slots") is not Array or hero.hand_slots.size() != hero.hand.size(): return false
	var reserved: Array[int] = []
	reserved.resize(hero.deck.size())
	reserved.fill(0)
	for index in hero.spell_uses.size():
		var count: Variant = hero.spell_uses[index]
		if count is not int: return false
		if profile.id == "el1":
			if not ELRunes.valid_count(profile, hero, hero.deck[index], count): return false
		elif count < 0 or count > 0x7fffffff: return false
	for index in hero.hand.size():
		var slot: Variant = hero.hand_slots[index]
		if slot is not int or slot < -1 or slot >= hero.deck.size(): return false
		if slot == -1: continue
		if hero.hand[index] != hero.deck[slot]: return false
		reserved[slot] += 1
		if hero.spell_uses[slot] >= 0 and reserved[slot] > hero.spell_uses[slot]: return false
	return true
