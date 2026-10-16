class_name ELDiplomacy
extends RefCounted
## First-game diplomacy between players.
##
## A relation byte per pair of players holds four 2-bit aspects: 0
## non-aggression in the ether, 1 non-aggression on land, 2 shared field of
## view, 3 shared shops. In each aspect the low bit is the agreement in force
## and the high bit allows it to be changed. Shipped maps use 0, 85, 170 and
## 255: 85 is a fixed alliance, 255 an alliance that may be broken, 170 a war
## that may be negotiated and 0 a fixed war.
##
## Two tables exist. The rules (hostility, fog, global spell targets,
## victory) read the relations in force, kept in each player's `relations`.
## The Diplomacy screen shows and edits the next day's table: breaking an
## alliance clears the agreed aspects there at once, and an accepted peace
## offer is written there when the next day begins, after which the whole
## table comes into force. Only one peace offer exists per pair; a new one
## replaces the other side's. Computer players never send, accept or decline
## offers, so an offer to them waits until its sender withdraws it.
##
## Trade offers are kept apart from peace offers, again one per pair. Each
## side lists the seven resources that player gives, whether it adds an
## artifact or a global spell, and whether the other side demands any
## artifact or global spell. Only the resources change hands: an accepted
## trade moves them at once, both ways. The artifact and global spell marks
## travel with the offer but never move an item. Computer players never
## answer a trade either, so it waits until its sender withdraws it.
##
## The state lives in each player's `diplomacy` record: the next-day relation
## to each higher-numbered player, the peace and trade offers this player has
## sent, the peace offers it has accepted, and the players it has chosen not
## to hear (Bane).
const VERSION := 1
const ASPECTS := 4
## Aspect indices.
const ETHER := 0
const LAND := 1
const VISION := 2
const SHOPS := 3
## Bit masks of the agreement in force for each aspect.
const ETHER_BIT := 0x01
const LAND_BIT := 0x04
const VISION_BIT := 0x10
const SHOPS_BIT := 0x40
## Resources a trade can carry, in the original resource order.
const TRADE_RESOURCES := 7
const TRADE_FLAGS := ["artifact", "need_artifact", "spell", "need_spell"]

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile != null and state.map.profile.id == "el1"

## Relation in force between two players (255 for a player and itself).
static func relation(state: ELAdventureSession, first: int, second: int) -> int:
	if first == second: return 0xff
	var lower: Dictionary = state.players.get(mini(first, second), {}).get("relations", {})
	var upper: Dictionary = state.players.get(maxi(first, second), {}).get("relations", {})
	return int(lower.get(maxi(first, second), upper.get(mini(first, second), 0))) & 0xff

## The next day's relation, as the Diplomacy screen shows it.
static func next_relation(state: ELAdventureSession, first: int, second: int) -> int:
	if first == second: return 0xff
	var pending: Dictionary = _record(state, mini(first, second)).get("next", {})
	return int(pending[maxi(first, second)]) if pending.has(maxi(first, second)) else relation(state, first, second)

static func agreed(value: int, aspect: int) -> bool:
	return value & (1 << (aspect * 2)) != 0

static func changeable(value: int, aspect: int) -> bool:
	return value & (1 << (aspect * 2 + 1)) != 0

## The agreed aspects of a relation as a four-bit mask (offer layout).
static func mask(value: int) -> int:
	var result := 0
	for aspect in ASPECTS:
		if agreed(value, aspect): result |= 1 << aspect
	return result

## A relation with its agreed bits replaced by `aspects` (four-bit mask).
static func with_mask(value: int, aspects: int) -> int:
	for aspect in ASPECTS:
		var bit := 1 << (aspect * 2)
		value = value | bit if aspects & (1 << aspect) else value & ~bit
	return value & 0xff

## Rule readers: each aspect in force between two players.
static func allied_in(state: ELAdventureSession, first: int, second: int, aspect: int) -> bool:
	return agreed(relation(state, first, second), aspect)

## Other players of the map in index order, the neutral player excluded.
static func others(state: ELAdventureSession, player: int) -> Array[int]:
	var result: Array[int] = []
	var ids: Array = state.players.keys()
	ids.sort()
	for id: int in ids:
		if id >= 1 and id != player: result.append(id)
	return result

## The peace offer between two players, if any: {from, to, before, mask}.
static func offer_between(state: ELAdventureSession, first: int, second: int) -> Dictionary:
	for pair: Array in [[first, second], [second, first]]:
		var sent: Dictionary = _record(state, pair[0]).get("offers", {})
		if sent.has(pair[1]): return {"from": pair[0], "to": pair[1], "before": int(sent[pair[1]].before), "mask": int(sent[pair[1]].mask)}
	return {}

## The offer `player` has sent to `other` (OutBox) or received from it (InBox).
static func sent(state: ELAdventureSession, player: int, other: int) -> Dictionary:
	var found := offer_between(state, player, other)
	return found if not found.is_empty() and found.from == player else {}

static func received(state: ELAdventureSession, player: int, other: int) -> Dictionary:
	var found := offer_between(state, player, other)
	return found if not found.is_empty() and found.from == other else {}

## A new offer as the screen opens it: the next-day aspects, unchanged.
static func draft(state: ELAdventureSession, from: int, to: int) -> Dictionary:
	var before := mask(next_relation(state, from, to))
	return {"from": from, "to": to, "before": before, "mask": before}

static func changed(offer: Dictionary) -> bool:
	return int(offer.get("before", 0)) != int(offer.get("mask", 0))

## Sends (or replaces) a peace offer; any offer the other side had sent to
## this player is dropped.
static func send(state: ELAdventureSession, offer: Dictionary) -> bool:
	var from := int(offer.get("from", -1))
	var to := int(offer.get("to", -1))
	if not applies(state) or from == to or not state.players.has(from) or not state.players.has(to) or from < 1 or to < 1: return false
	_clear_offers(state, from, to)
	_record(state, from, true).offers[to] = {"before": int(offer.before) & 0xf, "mask": int(offer.mask) & 0xf}
	state.event.emit({"kind": "diplomacy_changed"})
	return true

## Withdraws or declines the offer between two players.
static func withdraw(state: ELAdventureSession, first: int, second: int) -> void:
	_clear_offers(state, first, second)
	state.event.emit({"kind": "diplomacy_changed"})

## Accepts the offer `from` sent to `to`; it is written when the next day begins.
static func accept(state: ELAdventureSession, from: int, to: int) -> bool:
	var offer := received(state, to, from)
	if offer.is_empty(): return false
	_clear_offers(state, from, to)
	var accepted: Array = _record(state, from, true).accepted
	accepted.append({"to": to, "mask": int(offer.mask)})
	state.event.emit({"kind": "diplomacy_changed"})
	return true

## Breaks the alliance: every changeable agreed aspect of the next-day
## relation is cleared at once.
static func break_alliance(state: ELAdventureSession, player: int, other: int) -> void:
	if player == other or not state.players.has(player) or not state.players.has(other): return
	var value := next_relation(state, player, other)
	for aspect in ASPECTS:
		if changeable(value, aspect): value &= ~(1 << (aspect * 2))
	_set_next(state, player, other, value)
	state.event.emit({"kind": "diplomacy_changed"})

static func bane(state: ELAdventureSession, player: int, other: int) -> bool:
	return _record(state, player).get("bane", []).has(other)

## The Bane check box only records the choice; no single-player rule reads it.
static func set_bane(state: ELAdventureSession, player: int, other: int, value: bool) -> void:
	var list: Array = _record(state, player, true).bane
	if value and not list.has(other): list.append(other)
	elif not value: list.erase(other)

## Start of a day: accepted offers enter the next-day table, which then comes
## into force as a whole.
static func new_day(state: ELAdventureSession) -> void:
	if not applies(state): return
	var ids: Array = state.players.keys()
	ids.sort()
	for from: int in ids:
		var record := _record(state, from)
		for entry: Dictionary in record.get("accepted", []):
			var to := int(entry.to)
			if state.players.has(to): _set_next(state, from, to, with_mask(next_relation(state, from, to), int(entry.mask)))
		if record.has("accepted"): record.accepted.clear()
	var changed_any := false
	for first: int in ids:
		var pending: Dictionary = _record(state, first).get("next", {})
		for second: int in pending.keys():
			if not state.players.has(second): continue
			var value := int(pending[second]) & 0xff
			if value != relation(state, first, second): changed_any = true
			state.players[first].relations[second] = value
			state.players[second].relations[first] = value
		pending.clear()
	if changed_any: state.event.emit({"kind": "diplomacy_changed"})

## An empty side of a trade: what one player gives.
static func trade_side() -> Dictionary:
	var resources: Array = []
	resources.resize(TRADE_RESOURCES)
	resources.fill(0)
	return {"resources": resources, "artifact": false, "need_artifact": false, "spell": false, "need_spell": false}

## The trade offer between two players, if any:
## {from, to, give (the sender's side), take (the receiver's side)}.
static func trade_between(state: ELAdventureSession, first: int, second: int) -> Dictionary:
	for pair: Array in [[first, second], [second, first]]:
		var sent_trades: Dictionary = _record(state, pair[0]).get("trades", {})
		if sent_trades.has(pair[1]):
			var entry: Dictionary = sent_trades[pair[1]]
			return {"from": pair[0], "to": pair[1], "give": entry.give.duplicate(true), "take": entry.take.duplicate(true)}
	return {}

## The trade `player` has sent to `other` (OutBox) or received from it
## (InBox). Both carry `before`, the resources changes are measured from: a
## received offer arrives with its earlier amounts equal to the proposal.
static func trade_sent(state: ELAdventureSession, player: int, other: int) -> Dictionary:
	var found := trade_between(state, player, other)
	return _with_before(found) if not found.is_empty() and found.from == player else {}

static func trade_received(state: ELAdventureSession, player: int, other: int) -> Dictionary:
	var found := trade_between(state, player, other)
	return _with_before(found) if not found.is_empty() and found.from == other else {}

## A new trade as OfferTrade opens it: both sides empty.
static func trade_draft(state: ELAdventureSession, from: int, to: int) -> Dictionary:
	if not state.players.has(from) or not state.players.has(to): return {}
	return _with_before({"from": from, "to": to, "give": trade_side(), "take": trade_side()})

static func _with_before(offer: Dictionary) -> Dictionary:
	offer.before = {"give": offer.give.resources.duplicate(), "take": offer.take.resources.duplicate()}
	return offer

## The side `player` gives in an offer.
static func trade_side_of(offer: Dictionary, player: int) -> Dictionary:
	return offer.give if int(offer.get("from", -1)) == player else offer.take

## Only the resource amounts count as a change (artifact and spell marks do not).
static func trade_changed(offer: Dictionary) -> bool:
	var before: Dictionary = offer.get("before", {})
	return before.get("give", []) != offer.give.resources or before.get("take", []) != offer.take.resources

## One more or one less of a resource on a side; never below zero.
static func trade_step(side: Dictionary, resource: int, delta: int) -> void:
	if resource < 0 or resource >= TRADE_RESOURCES: return
	side.resources[resource] = maxi(0, int(side.resources[resource]) + delta)

## Whether `player` may add one more of a resource to the side it gives: only
## while it holds more than the side already carries.
static func trade_can_raise(state: ELAdventureSession, player: int, side: Dictionary, resource: int) -> bool:
	var held := int(state.players.get(player, {}).get("resources", {}).get(ELResources.ORIGINAL[resource], 0))
	return held > 0 and held > int(side.resources[resource])

## Sends (or replaces) a trade offer; any trade the other side had sent to
## this player is dropped.
static func send_trade(state: ELAdventureSession, offer: Dictionary) -> bool:
	var from := int(offer.get("from", -1))
	var to := int(offer.get("to", -1))
	if not applies(state) or from == to or from < 1 or to < 1 or not state.players.has(from) or not state.players.has(to): return false
	if not _valid_side(offer.get("give")) or not _valid_side(offer.get("take")): return false
	_clear_trades(state, from, to)
	_record(state, from, true)
	if not state.players[from].diplomacy.has("trades"): state.players[from].diplomacy.trades = {}
	state.players[from].diplomacy.trades[to] = {"give": _clean_side(offer.give), "take": _clean_side(offer.take)}
	state.event.emit({"kind": "diplomacy_changed"})
	return true

## Withdraws or declines the trade between two players.
static func withdraw_trade(state: ELAdventureSession, first: int, second: int) -> void:
	_clear_trades(state, first, second)
	state.event.emit({"kind": "diplomacy_changed"})

## Accepts the trade `from` sent to `to`: the resources change hands at once.
static func accept_trade(state: ELAdventureSession, from: int, to: int) -> bool:
	var offer := trade_received(state, to, from)
	if offer.is_empty(): return false
	_clear_trades(state, from, to)
	for index in TRADE_RESOURCES:
		var kind: String = ELResources.ORIGINAL[index]
		var gives := int(offer.give.resources[index])
		var takes := int(offer.take.resources[index])
		for pair: Array in [[from, takes - gives], [to, gives - takes]]:
			var wallet: Dictionary = state.players[pair[0]].resources
			wallet[kind] = clampi(int(wallet.get(kind, 0)) + int(pair[1]), 0, ELResources.MAX_AMOUNT)
	state.event.emit({"kind": "resources_changed", "player": from})
	state.event.emit({"kind": "resources_changed", "player": to})
	state.event.emit({"kind": "diplomacy_changed"})
	return true

static func _valid_side(side: Variant) -> bool:
	if not side is Dictionary or not side.get("resources") is Array or side.resources.size() != TRADE_RESOURCES: return false
	for amount: Variant in side.resources:
		if not ELLuaSave._integer(amount, 0, ELResources.MAX_AMOUNT): return false
	for flag: String in TRADE_FLAGS:
		if not side.get(flag, false) is bool: return false
	return true

static func _clean_side(side: Dictionary) -> Dictionary:
	var clean := trade_side()
	for index in TRADE_RESOURCES: clean.resources[index] = int(side.resources[index])
	for flag: String in TRADE_FLAGS: clean[flag] = bool(side.get(flag, false))
	return clean

static func _clear_trades(state: ELAdventureSession, first: int, second: int) -> void:
	_record(state, first).get("trades", {}).erase(second)
	_record(state, second).get("trades", {}).erase(first)

## Validates and normalises the saved records (older saves carry none).
static func restore(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("diplomacy")
		if raw == null: continue
		if not raw is Dictionary or raw.get("version") != VERSION: return "Invalid saved diplomacy."
		var clean := {"version": VERSION, "next": {}, "offers": {}, "trades": {}, "accepted": [], "bane": []}
		var pending: Variant = raw.get("next", {})
		var offers: Variant = raw.get("offers", {})
		var accepted: Variant = raw.get("accepted", [])
		var bane_list: Variant = raw.get("bane", [])
		var trades: Variant = raw.get("trades", {})
		if not pending is Dictionary or not offers is Dictionary or not trades is Dictionary or not accepted is Array or not bane_list is Array: return "Invalid saved diplomacy."
		for key: Variant in pending:
			var other := _player_key(state, key)
			if other <= player or not ELLuaSave._integer(pending[key], 0, 255): return "Invalid saved relation."
			clean.next[other] = int(pending[key])
		for key: Variant in offers:
			var other := _player_key(state, key)
			var offer: Variant = offers[key]
			if other < 1 or other == player or not offer is Dictionary or not ELLuaSave._integer(offer.get("before"), 0, 15) or not ELLuaSave._integer(offer.get("mask"), 0, 15): return "Invalid saved peace offer."
			clean.offers[other] = {"before": int(offer.before), "mask": int(offer.mask)}
		for key: Variant in trades:
			var other := _player_key(state, key)
			var trade: Variant = trades[key]
			if other < 1 or other == player or not trade is Dictionary or not _valid_side(trade.get("give")) or not _valid_side(trade.get("take")): return "Invalid saved trade offer."
			clean.trades[other] = {"give": _clean_side(trade.give), "take": _clean_side(trade.take)}
		for entry: Variant in accepted:
			if not entry is Dictionary or _player_key(state, entry.get("to")) < 1 or not ELLuaSave._integer(entry.get("mask"), 0, 15) or accepted.size() > 64: return "Invalid saved peace offer."
			clean.accepted.append({"to": _player_key(state, entry.to), "mask": int(entry.mask)})
		for entry: Variant in bane_list:
			if _player_key(state, entry) < 1 or bane_list.size() > 64: return "Invalid saved diplomacy."
			clean.bane.append(_player_key(state, entry))
		state.players[player].diplomacy = clean
	return ""

static func _player_key(state: ELAdventureSession, key: Variant) -> int:
	if key is String and key.is_valid_int(): key = int(key)
	if not ELLuaSave._integer(key, 0, 32) or not state.players.has(int(key)): return -1
	return int(key)

static func _record(state: ELAdventureSession, player: int, create := false) -> Dictionary:
	if not state.players.has(player): return {}
	var record: Variant = state.players[player].get("diplomacy")
	if record is Dictionary: return record
	if not create: return {}
	state.players[player].diplomacy = {"version": VERSION, "next": {}, "offers": {}, "trades": {}, "accepted": [], "bane": []}
	return state.players[player].diplomacy

static func _set_next(state: ELAdventureSession, first: int, second: int, value: int) -> void:
	_record(state, mini(first, second), true).next[maxi(first, second)] = value & 0xff

static func _clear_offers(state: ELAdventureSession, first: int, second: int) -> void:
	_record(state, first).get("offers", {}).erase(second)
	_record(state, second).get("offers", {}).erase(first)
