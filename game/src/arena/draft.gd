class_name ELArenaDraft
extends RefCounted
## Sixteen real choices, shared by player and bots. A seed fixes offers;
## chosen cards may affect legality and simple, public role safeguards.

var profile: ELProfile
var faction := ""
var rules_version := ELArenaRules.OPEN_RULES
var seed_value := 0
var cards: Array[String] = []
var history: Array[Dictionary] = []
var offer: Array[String] = []
var error := ""
var _pool: Array[String] = []
var _signature := ""

func create(source: ELProfile, colour: String, seed: int, rules := ELArenaRules.OPEN_RULES) -> bool:
	error = ""
	if source == null or source.id != "el2" or colour not in ELArenaRules.FACTIONS: return _fail("Choose an Etherlords II Arena faction.")
	if seed < 0 or seed > 0x7fffffff: return _fail("Arena seeds must be between 0 and 2147483647.")
	if not _integer(rules, ELArenaRules.LEGACY_RULES, ELArenaRules.FACTION_RULES): return _fail("Unsupported Arena draft rules.")
	var available := ELArenaRules.pool(source, colour, rules)
	if available.size() < 6: return _fail("This installation has too few eligible Arena spells.")
	profile = source
	faction = colour
	rules_version = rules
	seed_value = seed
	_pool = available
	_signature = ELArenaRules.pool_signature(source, colour, rules_version)
	cards.clear()
	history.clear()
	offer = _next_offer()
	return offer.size() == 3 or _fail("The Arena could not offer three distinct legal spells.")

func finished() -> bool:
	return profile != null and cards.size() == ELArenaRules.DECK_SIZE

func choose(index: int) -> bool:
	error = ""
	if profile == null or finished() or index < 0 or index >= offer.size() or offer.size() != 3: return _fail("Choose one of the three offered spells.")
	if ELArenaRules.pool_signature(profile, faction, rules_version) != _signature: return _fail("The installed Arena card pool changed during this draft.")
	# Guard the transaction even if a caller changed a public display array.
	if offer != _next_offer(): return _fail("The displayed draft offer no longer matches this draft.")
	var card := offer[index]
	history.append({"offer": offer.duplicate(), "choice": index, "card": card})
	cards.append(card)
	var next := _next_offer()
	if not finished() and next.size() != 3:
		cards.pop_back()
		history.pop_back()
		return _fail("The next Arena offer is unavailable; this pick was not applied.")
	offer = next
	return true

## Every offer contains a creature when one is available. While the book has
## fewer than four early threats, that slot offers an early threat. From pick
## four onward a missing interaction tool gets an opportunity; from pick
## seven removal and from pick nine an enchantment answer do. After three
## expensive picks the creature slot prefers an affordable body. These opportunities do
## not force anyone to take a card or repair a completed bot deck.
func _next_offer() -> Array[String]:
	var result: Array[String] = []
	if finished(): return result
	var available: Array[String] = []
	for code: String in _pool:
		if cards.count(code) < ELArenaRules.COPY_LIMIT: available.append(code)
	if available.size() < 3: return result
	var random := RandomNumberGenerator.new()
	random.seed = int((seed_value * 1664525 + (cards.size() + 1) * 1013904223 + rules_version * 104729) & 0x7fffffff)
	var stats := ELArenaRules.summary(profile, cards)
	for slot in 3:
		var candidates: Array[String] = []
		if slot == 0:
			if int(stats.early) < 4: candidates = _role(available, "early")
			if candidates.is_empty(): candidates = _role(available, "creature")
			if int(stats.expensive) >= 3:
				var affordable: Array[String] = []
				for code: String in candidates:
					if int(ELArenaRules.features(profile, code).cost) <= 5: affordable.append(code)
				if not affordable.is_empty(): candidates = affordable
		elif slot == 1:
			if cards.size() >= 8 and int(stats.dispel) < 1: candidates = _role(available, "dispel")
			if candidates.is_empty() and cards.size() >= 6 and int(stats.removal) < 1: candidates = _role(available, "removal")
			if candidates.is_empty() and cards.size() >= 3 and int(stats.interaction) < 3: candidates = _role(available, "interaction")
		if candidates.is_empty(): candidates = available
		var selected := _weighted_pick(candidates, random)
		result.append(selected)
		available.erase(selected)
	# Positions carry no extra meaning; the complete offer stays reproducible.
	for i in range(result.size() - 1, 0, -1):
		var other := random.randi_range(0, i)
		var held := result[i]
		result[i] = result[other]
		result[other] = held
	return result

func _role(available: Array[String], key: String) -> Array[String]:
	var result: Array[String] = []
	for code: String in available:
		if bool(ELArenaRules.features(profile, code).get(key, false)): result.append(code)
	return result

func _weighted_pick(available: Array[String], random: RandomNumberGenerator) -> String:
	var weights: Array[int] = []
	var total := 0
	for code: String in available:
		var f := ELArenaRules.features(profile, code)
		var rarity_weight := int({"Cantrip": 10, "Common": 10, "Rare": 7, "Unique": 5}.get(f.rarity, 7))
		var weight := rarity_weight * (3 if rules_version == ELArenaRules.LEGACY_RULES and f.faction == faction else 1)
		weights.append(weight)
		total += weight
	var roll := random.randi_range(0, total - 1)
	for i in available.size():
		roll -= weights[i]
		if roll < 0: return available[i]
	return available.back()

func snapshot() -> Dictionary:
	return {"format": "demiurges-arena-draft", "version": rules_version, "faction": faction, "seed": seed_value,
		"pool_signature": _signature, "cards": cards.duplicate(), "history": history.duplicate(true), "offer": offer.duplicate()}

## Replay every recorded choice through the real generator. Neither a forged
## finished list, changed choice, missing pick, nor a rerolled current offer
## is accepted. The receiving draft is unchanged after a failed restore.
func restore(source: ELProfile, value: Variant) -> bool:
	error = ""
	if value is not Dictionary: return _fail("Invalid Arena draft checkpoint.")
	var data: Dictionary = value
	if data.get("format") != "demiurges-arena-draft" or not _integer(data.get("version"), ELArenaRules.LEGACY_RULES, ELArenaRules.FACTION_RULES): return _fail("Unsupported Arena draft version.")
	if data.get("faction") is not String or not _integer(data.get("seed"), 0, 0x7fffffff): return _fail("Invalid Arena draft identity.")
	if data.get("cards") is not Array or data.get("history") is not Array or data.get("offer") is not Array: return _fail("Invalid Arena draft transcript.")
	if data.cards.size() > ELArenaRules.DECK_SIZE or data.history.size() != data.cards.size(): return _fail("The Arena draft transcript has the wrong number of picks.")
	var replay := ELArenaDraft.new()
	if not replay.create(source, data.faction, int(data.seed), int(data.version)): return _fail(replay.error)
	if data.get("pool_signature") != replay._signature: return _fail("The installed Arena card pool changed. This draft cannot be resumed safely.")
	for i in data.history.size():
		var entry: Variant = data.history[i]
		if entry is not Dictionary or entry.get("offer") is not Array or not _integer(entry.get("choice"), 0, 2) or entry.get("card") is not String: return _fail("Invalid pick in the Arena draft transcript.")
		if entry.offer != replay.offer or entry.card != replay.offer[int(entry.choice)] or data.cards[i] != entry.card: return _fail("An Arena draft pick does not match its recorded offer.")
		if not replay.choose(int(entry.choice)): return _fail(replay.error)
	if data.offer != replay.offer: return _fail("The saved Arena offer does not match its seed and choices.")
	profile = replay.profile
	faction = replay.faction
	rules_version = replay.rules_version
	seed_value = replay.seed_value
	cards = replay.cards
	history = replay.history
	offer = replay.offer
	_pool = replay._pool
	_signature = replay._signature
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func _fail(message: String) -> bool:
	error = message
	return false
