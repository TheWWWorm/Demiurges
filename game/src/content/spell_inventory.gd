class_name ELSpellInventory
extends RefCounted
## The equipped book and reserve own separate copies of spells.
const BOOK_SIZE := 16
const MAX_COPIES := 100000
const MAGIC_COLORS := ["Red", "Green", "Blue", "Black", "White"]

static func book_size(profile: ELProfile) -> int:
	return 15 if profile.id == "el1" else BOOK_SIZE

static func is_spell(profile: ELProfile, card: String) -> bool:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	if row.is_empty(): return false
	return str(row.get("IsArtifact", "False")) == "False" or (profile.id == "el2" and ELCatalog.ARTIFACT_EFFECTS.has(card))

static func add(profile: ELProfile, hero: Dictionary, card: String, count := 1) -> bool:
	if not is_spell(profile, card) or count <= 0 or int(hero.spell_stock.get(card, 0)) + count > MAX_COPIES: return false
	if profile.id == "el1":
		if not ELRunes.restore(profile, hero): return false
		if not hero.rune_stock.has(card): hero.rune_stock[card] = []
		for index in count: hero.rune_stock[card].append(-1 if ELRunes.unlimited(profile, hero, card) else 0)
	hero.spell_stock[card] = int(hero.spell_stock.get(card, 0)) + count
	return true

static func remove(hero: Dictionary, card: String, count := 1, index := 0) -> void:
	if count <= 0: return
	if hero.has("rune_stock") and hero.rune_stock.has(card):
		for copy in mini(count, hero.rune_stock[card].size() - index): hero.rune_stock[card].remove_at(index)
		if hero.rune_stock[card].is_empty(): hero.rune_stock.erase(card)
	var remaining := int(hero.spell_stock.get(card, 0)) - count
	if remaining > 0: hero.spell_stock[card] = remaining
	else: hero.spell_stock.erase(card)

static func allows(profile: ELProfile, hero: Dictionary, card: String) -> bool:
	if not is_spell(profile, card): return false
	var row: Dictionary = profile.table("Shapes").get(hero.get("shape", ""), {}) if not str(hero.get("shape", "")).is_empty() else profile.table("HeroTemplates").get(hero.get("name", ""), {})
	var color := str(profile.table("CombatSpells")[card].get("Color", ""))
	if not color_enabled(hero, color): return false
	return color == row.get("Color", "") or row.get("Color") == "White" or hero.get("allowed_colors", {}).get(color, false)

static func color_enabled(hero: Dictionary, color: String) -> bool:
	# Scenario color bans are independent of the hero's natural magic color.
	return color in MAGIC_COLORS and hero.get("allowed_colors", {}).get(color, true)

static func swap_slots(entries: Array, from: int, to: int) -> bool:
	if from == to or mini(from, to) < 0 or maxi(from, to) >= entries.size(): return false
	var held: Variant = entries[from]
	entries[from] = entries[to]
	entries[to] = held
	return true

## Runes and the cantrip underneath belong to the spell being moved.
static func reorder_book(profile: ELProfile, hero: Dictionary, from: int, to: int) -> bool:
	if profile.id == "el1" and not ELRunes.restore(profile, hero): return false
	if not swap_slots(hero.cards, from, to): return false
	if profile.id == "el1":
		swap_slots(hero.rune_uses, from, to)
		if hero.has("rune_under"): swap_slots(hero.rune_under, from, to)
	return true

static func valid_slot_order(order: Array, size: int) -> bool:
	if order.is_empty(): return true
	if order.size() != size: return false
	var seen := {}
	for value: Variant in order:
		if not ELLuaSave._integer(value, 0, size - 1) or seen.has(int(value)): return false
		seen[int(value)] = true
	return true

static func in_slot_order(entries: Array, order: Array) -> Array:
	var result := entries.duplicate()
	for i in order.size(): result[i] = entries[int(order[i])]
	return result

static func apply_slot_order(hero: Dictionary, order: Array) -> void:
	if order.is_empty(): return
	hero.cards.assign(in_slot_order(hero.cards, order))
	hero.rune_uses.assign(in_slot_order(hero.rune_uses, order))
	if hero.has("rune_under"): hero.rune_under = in_slot_order(hero.rune_under, order)

## Moves reserve copy `reserve_index` of `card` into the book: onto the end,
## or with `slot` onto that occupied slot, as a laboratory purchase does (a
## cantrip there stays under the spell and takes the slot back when it is
## stored again; another spell goes to the reserve with its runes). A full
## book of cantrips can therefore still take a spell from the reserve.
static func equip(profile: ELProfile, hero: Dictionary, card: String, reserve_index := 0, slot := -1) -> String:
	if slot >= hero.cards.size(): slot = -1
	if slot < 0 and hero.cards.size() >= book_size(profile): return "The spellbook already contains %d spells." % book_size(profile)
	if not allows(profile, hero, card): return "This hero cannot use that spell's magic color."
	if int(hero.spell_stock.get(card, 0)) <= 0: return "There is no copy of that spell in reserve."
	if reserve_index < 0 or reserve_index >= int(hero.spell_stock[card]): return "That reserve copy is unavailable."
	var uses := 0
	if profile.id == "el1":
		if not ELRunes.restore(profile, hero): return "Invalid rune inventory."
		uses = hero.rune_stock[card][reserve_index]
	if slot >= 0: return _equip_over(profile, hero, card, reserve_index, slot, uses)
	remove(hero, card, 1, reserve_index)
	hero.cards.append(card)
	if profile.id == "el1":
		hero.rune_uses.append(uses)
		if hero.has("rune_under"): hero.rune_under.append("")
	return ""

static func _equip_over(profile: ELProfile, hero: Dictionary, card: String, reserve_index: int, slot: int, uses: int) -> String:
	var first := profile.id == "el1"
	var old := str(hero.cards[slot])
	var old_cantrip := first and ELRunes.unlimited(profile, hero, old)
	var codes: Array[String] = ELRunes.under(hero) if first else ([] as Array[String])
	# A cantrip neither goes to the reserve nor waits under another cantrip.
	if first and ELRunes.unlimited(profile, hero, card) and (old_cantrip or not codes[slot].is_empty()): return "Cantrips cannot be moved to reserve."
	if not old_cantrip:
		if not add(profile, hero, old): return "That spell cannot be moved to reserve."
		if first: hero.rune_stock[old][-1] = hero.rune_uses[slot]
	remove(hero, card, 1, reserve_index)
	hero.cards[slot] = card
	if first:
		hero.rune_uses[slot] = uses
		if old_cantrip: codes[slot] = old
		ELRunes.set_under(hero, codes)
	return ""

static func unequip(profile: ELProfile, hero: Dictionary, index: int) -> String:
	if index < 0 or index >= hero.cards.size(): return "That spellbook slot is empty."
	# First game: a cantrip stays in the book, as in the original.
	if profile.id == "el1" and ELRunes.unlimited(profile, hero, str(hero.cards[index])): return "Cantrips cannot be moved to reserve."
	if profile.id == "el1" and not ELRunes.restore(profile, hero): return "Invalid rune inventory."
	if not add(profile, hero, str(hero.cards[index])): return "That spell cannot be moved to reserve."
	if profile.id == "el1":
		hero.rune_stock[hero.cards[index]][-1] = hero.rune_uses[index]
		var codes := ELRunes.under(hero)
		# A cantrip waiting under the spell takes the slot back.
		if not codes[index].is_empty():
			hero.cards[index] = codes[index]
			hero.rune_uses[index] = -1
			codes[index] = ""
			ELRunes.set_under(hero, codes)
			return ""
		hero.rune_uses.remove_at(index)
		codes.remove_at(index)
		if hero.has("rune_under"): ELRunes.set_under(hero, codes)
	hero.cards.remove_at(index)
	return ""
