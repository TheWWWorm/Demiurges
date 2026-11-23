class_name ELSecondBalance
extends RefCounted
## The remake's "Etherlords II card balance" option for the first game
## (setting "second_balance"). Every first-game card the second game also
## has (all of them do, by the same code) is played as the second game plays
## it, update 1.03 included, so both games share one balance:
##
## - its table values come from the installed second game: the cost and its
##   class (CombatSpells), a creature's power, toughness and flags
##   (CombatCreatures), and its description when both games are in the same
##   language;
## - its rules follow the second game wherever the two differ for that card
##   (ELCatalog.second_rules, ELDuel.second_rules): Ether Breeze and Ether
##   Storm feed their caster from a creature, Healing raises health to half,
##   Firestorm and Supernova cost channels, and so on.
##
## The battle rules outside the cards follow the second game as well
## (ELDuel.second_battle), as both games' duels are one game apart from their
## balance: the second hero's extra ether on its first turn, the ether
## disturbance's growth, the order of a hit's discards, lifeguards and
## disenchanting strikes, a regenerated creature leaving its fight, the ten
## creature armies and so on. What belongs to the first game itself stays as
## it is: its heroes and their specialisations, its spellbook with runes and
## cantrips, its artifacts, global spells and combat events, and its maps.
## Puzzles keep the first game's own balance and rules, which they were made
## for.
##
## Applied to the mounted first-game profile in place and undone the same
## way, so the profile stays one object; a battle records which balance it
## was started with (ELDuel setup "second_balance").

## The CombatSpells and CombatCreatures values taken from the second game.
const SPELL_KEYS := ["Cost", "OriginalCost", "Class"]
const CREATURE_KEYS := ["Power", "Toughness", "Flags"]
## Description keys added to the first game's texts.
const TEXT_PREFIX := "ELSecondBalance:"

## Whether `first` (a first-game profile) plays the second game's balance.
static func active(first: ELProfile) -> bool:
	return first != null and not first.second_cards.is_empty()

## Turns the balance on or off for `first`, from `second` (the second game's
## profile; null turns it off). Returns whether it is on afterwards.
static func apply(first: ELProfile, second: ELProfile, enabled: bool) -> bool:
	if first == null or first.id != "el1": return false
	if not enabled or second == null or second.id != "el2":
		_restore(first)
		return false
	if active(first): return true
	var spells: Dictionary = first.table("CombatSpells")
	var creatures: Dictionary = first.table("CombatCreatures")
	var second_spells: Dictionary = second.table("CombatSpells")
	var second_creatures: Dictionary = second.table("CombatCreatures")
	var same_language := ELRemakeText.language(first) == ELRemakeText.language(second)
	var saved := {}
	var cards := {}
	for card: String in spells:
		var other: Dictionary = second_spells.get(card, {})
		# Only cards both games can play: artifact spells and internal records
		# differ between the games under the same code.
		if other.is_empty() or ELCatalog.rule(first, card).is_empty() or ELCatalog.rule(second, card).is_empty(): continue
		if str(other.get("Color", "")) != str(spells[card].get("Color", "")): continue
		var row: Dictionary = spells[card]
		var creature: Dictionary = creatures.get(card, {})
		var other_creature: Dictionary = second_creatures.get(card, {})
		if creature.is_empty() != other_creature.is_empty(): continue
		saved[card] = [row.duplicate(true), creature.duplicate(true)]
		for key: String in SPELL_KEYS:
			if other.has(key): row[key] = other[key]
		for key: String in CREATURE_KEYS:
			if other_creature.has(key): creature[key] = other_creature[key].duplicate() if other_creature[key] is Array else other_creature[key]
			elif key == "Flags": creature.erase(key)
		if same_language:
			var description: String = second.card_description(card)
			if not description.is_empty() and description != str(other.get("ToolTip", card)):
				first.texts[TEXT_PREFIX + card] = description
				row.ToolTip = TEXT_PREFIX + card
		cards[card] = true
	first.second_cards = cards
	first.second_restore = saved
	# A card the first game's rules cannot play with the second game's values
	# keeps its own.
	for card: String in cards.keys():
		if ELCatalog.rule(first, card).is_empty(): _restore_card(first, card)
	return active(first)

## Puts the first game's own values back.
static func _restore(first: ELProfile) -> void:
	if not active(first) and first.second_restore.is_empty(): return
	for card: String in first.second_restore.keys(): _restore_card(first, card)
	first.second_cards = {}
	first.second_restore = {}

static func _restore_card(first: ELProfile, card: String) -> void:
	var saved: Array = first.second_restore.get(card, [])
	first.second_cards.erase(card)
	first.second_restore.erase(card)
	first.texts.erase(TEXT_PREFIX + card)
	if saved.is_empty(): return
	_replace(first.table("CombatSpells").get(card, {}), saved[0])
	_replace(first.table("CombatCreatures").get(card, {}), saved[1])

## Replaces `row`'s contents in place (other holders keep the same dictionary).
static func _replace(row: Dictionary, values: Dictionary) -> void:
	if row.is_empty() and values.is_empty(): return
	row.clear()
	row.merge(values.duplicate(true))
