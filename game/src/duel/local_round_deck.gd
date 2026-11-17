class_name ELLocalRoundDeck
extends RefCounted
## Second game, a local Duel mode match between rounds: one player's deck
## change (an active spell exchanged with one of the preset's reserve spells),
## kept in the match's preset for the next round. ELNetworkDeck shows it as it
## shows an online round draft (player report #77: hot seat).

var profile: ELProfile
var duel: ELDuel
var duel_match: ELDuelMatch
var side := 0
## Shown in the panel's title (a hot-seat player's name).
var player := ""

func _init(source: ELProfile, current: ELDuel, owner: ELDuelMatch, player_side: int, name := "") -> void:
	profile = source
	duel = current
	duel_match = owner
	side = player_side
	player = name

func round_preset() -> Dictionary:
	return Dictionary(duel_match.presets[side]).duplicate(true)

func swap_round_spell(slot: int, code: String) -> bool:
	if profile.id != "el2" or duel_match.finished(): return false
	var draft := round_preset()
	if slot < 0 or slot >= draft.cards.size() or int(draft.reserve.get(code, 0)) <= 0: return false
	draft.cards[slot] = code
	return _stage(draft.cards)

func reorder_round_spells(from: int, to: int) -> bool:
	if profile.id != "el2" or duel_match.finished(): return false
	var draft := round_preset()
	return ELSpellInventory.swap_slots(draft.cards, from, to) and _stage(draft.cards)

func _stage(cards: Array) -> bool:
	var validated := ELDuelPresets.with_reserve_deck(duel_match.presets[side], cards)
	if validated.is_empty(): return false
	duel_match.presets[side] = validated
	return true

## No clock between local rounds.
func deck_time_remaining() -> int:
	return -1

## Whether the preset has a reserve spell to exchange.
static func available(owner: ELDuelMatch, player_side: int) -> bool:
	var preset: Dictionary = owner.presets[player_side]
	return Dictionary(preset.get("reserve", {})).values().any(func(count: Variant): return int(count) > 0)
