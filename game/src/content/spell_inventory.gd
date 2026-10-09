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
	return not row.is_empty() and str(row.get("IsArtifact", "False")) == "False"

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

static func equip(profile: ELProfile, hero: Dictionary, card: String, reserve_index := 0) -> String:
	if hero.cards.size() >= book_size(profile): return "The spellbook already contains %d spells." % book_size(profile)
	if not allows(profile, hero, card): return "This hero cannot use that spell's magic color."
	if int(hero.spell_stock.get(card, 0)) <= 0: return "There is no copy of that spell in reserve."
	if reserve_index < 0 or reserve_index >= int(hero.spell_stock[card]): return "That reserve copy is unavailable."
	var uses := 0
	if profile.id == "el1":
		if not ELRunes.restore(profile, hero): return "Invalid rune inventory."
		uses = hero.rune_stock[card][reserve_index]
	remove(hero, card, 1, reserve_index)
	hero.cards.append(card)
	if profile.id == "el1": hero.rune_uses.append(uses)
	return ""

static func unequip(profile: ELProfile, hero: Dictionary, index: int) -> String:
	if index < 0 or index >= hero.cards.size(): return "That spellbook slot is empty."
	if profile.id == "el1" and not ELRunes.restore(profile, hero): return "Invalid rune inventory."
	if not add(profile, hero, str(hero.cards[index])): return "That spell cannot be moved to reserve."
	if profile.id == "el1":
		hero.rune_stock[hero.cards[index]][-1] = hero.rune_uses[index]
		hero.rune_uses.remove_at(index)
	hero.cards.remove_at(index)
	return ""
