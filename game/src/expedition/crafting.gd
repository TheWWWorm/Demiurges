class_name ELExpeditionCrafting
extends RefCounted
## Expedition recipes only exchange existing printed pages. They never change
## spell rules, rarity, charges, or stats. All returned arrays are fresh.
## `owned` includes the active book and reserve; the active book alone supplies
## pages consumed by a recipe. Callers apply the chosen recipe transactionally.

const CEILINGS := [3, 5, 8]
const BASIC_RARITIES := ["Cantrip", "Common"]
const CRAFTED_RARITIES := ["Rare", "Unique"]

static func recipes(profile: ELProfile, faction: String, deck: Array[String], owned: Array[String], act: int, room_seed: int, study_path: String, consume_count := 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_context(profile, faction, act) or consume_count not in [1, 2]: return result
	var spells := profile.table("CombatSpells")
	var pool: Array[String] = []
	var sources: Array[String] = []
	for code: String in spells:
		if not _supported(profile, faction, code): continue
		var rarity: String = str(spells[code].get("Rarity", ""))
		if rarity in BASIC_RARITIES and code in deck and deck.count(code) >= consume_count:
			sources.append(code)
		elif rarity in CRAFTED_RARITIES and ELEncyclopaedia.cost(profile, code) <= CEILINGS[act - 1]:
			# The max also protects a caller that accidentally omitted active
			# pages from `owned`; a known active copy cannot become invisible.
			if maxi(owned.count(code), deck.count(code)) < ELDuelCosts.EL2_COPIES: pool.append(code)
	pool.sort()
	sources.sort()
	var focus := _focus(profile, faction, study_path, pool, act)
	for source: String in sources:
		var kind: String = str(spells[source].get("Class", ""))
		var candidates: Array[String] = []
		for code: String in pool:
			if spells[code].get("Class", "") == kind: candidates.append(code)
		if candidates.is_empty(): continue
		var preferred: Array[String] = []
		for code: String in candidates:
			if code in focus: preferred.append(code)
		var random := RandomNumberGenerator.new()
		random.seed = _source_seed(room_seed, source)
		var incoming: Array[String] = []
		var first_pool := preferred if not preferred.is_empty() else candidates
		var first: String = first_pool[random.randi_range(0, first_pool.size() - 1)]
		incoming.append(first)
		candidates.erase(first)
		if not candidates.is_empty():
			var broad: Array[String] = []
			for code: String in candidates:
				if code not in focus: broad.append(code)
			var second_pool := broad if not broad.is_empty() else candidates
			incoming.append(second_pool[random.randi_range(0, second_pool.size() - 1)])
		result.append({"source": source, "incoming": incoming, "consume": consume_count})
	return result

static func library_offers(profile: ELProfile, faction: String, owned: Array[String], act: int, room_seed: int, study_path: String) -> Array[String]:
	var result: Array[String] = []
	if not _valid_context(profile, faction, act): return result
	var spells := profile.table("CombatSpells")
	var pool: Array[String] = []
	for code: String in spells:
		if not _supported(profile, faction, code) or owned.count(code) >= ELDuelCosts.EL2_COPIES: continue
		if spells[code].get("Rarity", "") in BASIC_RARITIES and ELEncyclopaedia.cost(profile, code) <= CEILINGS[act - 1]: pool.append(code)
	pool.sort()
	var focus := _focus(profile, faction, study_path, pool, act)
	var random := RandomNumberGenerator.new()
	random.seed = _source_seed(room_seed, "library")
	for index in mini(3, pool.size()):
		var preferred: Array[String] = []
		for code: String in pool:
			if (index == 0 and spells[code].get("Class", "") == "Creature") or (index == 1 and spells[code].get("Class", "") != "Creature") or (index == 2 and code in focus):
				preferred.append(code)
		var candidates := preferred if not preferred.is_empty() else pool
		var chosen: String = candidates[random.randi_range(0, candidates.size() - 1)]
		result.append(chosen)
		pool.erase(chosen)
	return result

static func _valid_context(profile: ELProfile, faction: String, act: int) -> bool:
	return profile != null and profile.id == "el2" and faction in ELDuelPresets.RACES and act >= 1 and act <= CEILINGS.size()

static func _supported(profile: ELProfile, faction: String, code: String) -> bool:
	var row: Variant = profile.table("CombatSpells").get(code)
	if row is not Dictionary or str(row.get("Class", "")).is_empty() or row.get("Use", "+") != "+": return false
	if str(row.get("IsArtifact", "False")).to_lower() == "true" or str(row.get("Support", "False")).to_lower() == "true": return false
	return ELDuelCosts.spell_allowed(profile, code, faction) and not ELCatalog.rule(profile, code).is_empty()

static func _focus(profile: ELProfile, faction: String, study_path: String, pool: Array[String], act: int) -> Array[String]:
	var result: Array[String] = []
	var path := ELExpeditionPaths.find(profile, study_path)
	if path.is_empty() or path.faction != faction: return result
	return ELExpeditionPaths.candidates(profile, study_path, pool, act)

static func _source_seed(room_seed: int, source: String) -> int:
	# Use an explicit stable 32-bit mix, not dictionary order or a shared RNG.
	# Adding or removing another source never rerolls this source's recipes.
	var value: int = (room_seed ^ 0x4d63a9b7) & 0xffffffff
	for byte: int in source.to_utf8_buffer(): value = ((value ^ byte) * 16777619) & 0xffffffff
	return value
