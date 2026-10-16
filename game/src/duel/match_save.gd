class_name ELMatchSave
extends RefCounted
## Validate once at the save-file boundary; restore never partially changes a match.

static func decode(profile: ELProfile, raw: Dictionary) -> Dictionary:
	var s: Dictionary = _integers(raw)
	if s.has("charge_version") and s.charge_version != 2: return _bad("Unsupported spell charge version.")
	if s.has("payment_version") and s.payment_version != 1: return _bad("Unsupported ether payment version.")
	for key in ["round", "phase", "attacker", "winner", "rng", "next_id", "next_enchantment", "turn_serial"]:
		if s.get(key) is not int: return _bad("Missing duel counter: " + key)
	if s.phase not in [0, 1, 2] or s.attacker not in [0, 1] or s.winner not in [-1, 0, 1] or s.round < 1:
		return _bad("Invalid duel phase.")
	if s.phase != 2 and s.winner >= 0: return _bad("Inconsistent duel outcome.")
	if s.get("heroes") is not Array or s.heroes.size() != 2 or s.get("creatures") is not Dictionary:
		return _bad("Missing combatants.")
	if s.get("attacks") is not Array or s.get("blocks") is not Dictionary or s.get("setup") is not Dictionary:
		return _bad("Missing duel orders.")
	if not profile.table("CombatSceneDB").has(s.setup.get("arena", "Green.001")):
		return _bad("Missing battlefield in save.")
	if s.setup.has("first_side") and s.setup.first_side not in [0, 1]: return _bad("Invalid first side in save.")
	if s.has("scripts") and not ELBattleScripts.valid(profile, s.scripts): return _bad("Invalid battle script state.")
	var enchantment_ids: Array[int] = []
	for side in 2:
		var h: Variant = s.heroes[side]
		if h is not Dictionary: return _bad("Invalid hero.")
		for key in ["id", "health", "maximum", "mana", "channels", "level", "turns"]:
			if h.get(key) is not int or h[key] < 0: return _bad("Invalid hero value: " + key)
		if h.id != side or h.maximum < 1 or h.health > 0x7fffffff: return _bad("Invalid hero health.")
		if not profile.table("HeroTemplates").has(h.get("template", "")) or not ELCatalog.faction_known(profile, str(h.get("faction", ""))):
			return _bad("Missing hero definition.")
		if not String(h.get("shape", "")).is_empty() and not profile.table("Shapes").has(h.shape): return _bad("Missing campaign hero appearance.")
		if h.has("monster_name") != h.has("monster_difficulty"): return _bad("Incomplete neutral creature appearance.")
		if h.has("monster_name"):
			if not h.monster_name is String or not ELLuaSave._integer(h.get("monster_difficulty"), 0, 4) or h.get("kind") != "monster" or ELFirstMonsters.appearance(profile, h.monster_name, int(h.monster_difficulty)).is_empty(): return _bad("Missing neutral creature appearance.")
		if not profile.table("CombatManaIncome").get("1", {}).has("Level%d" % h.level): return _bad("Invalid hero level.")
		if not h.has("skills"): h.skills = {}
		# Saves from before specialisations carry none.
		if not h.has("spec"): ELSpecs.prepare(h, {})
		if not ELSpecs.valid(profile, h.spec) or h.get("spec_level") is not int or h.spec_level < 1 or h.spec_level > 20: return _bad("Invalid hero specialization.")
		for key in ["luck", "suppression"]:
			if h.get(key) is not int or h[key] < 0 or h[key] > 3: return _bad("Invalid hero specialization.")
		if not ELHeroSkills.valid_ranks(profile, h.skills): return _bad("Invalid hero skills.")
		for field in ["hand", "deck", "grave"]:
			if h.get(field) is not Array: return _bad("Invalid spell list.")
			for card: Variant in h[field]:
				if card is not String or ELCatalog.rule(profile, card).is_empty(): return _bad("Unavailable spell in save.")
		if (h.deck.is_empty() and not (profile.id == "el2" and s.setup.get("adventure", false) == true)) or h.get("drawn") is not Array: return _bad("Invalid spellbook.")
		if h.has("spell_uses") != h.has("hand_slots"): return _bad("Incomplete spell charge state.")
		if not h.has("spell_uses") or (profile.id == "el1" and not s.has("charge_version")): ELSpellCharges.migrate(profile, h, s.setup, side)
		if not ELSpellCharges.valid(profile, h): return _bad("Invalid spell charge state.")
		# Rail order keys (ELDuel._give_card); one out of step with the hand is
		# ignored at runtime, so the hand shows in array order.
		if h.has("hand_view"):
			if h.hand_view is not Array: return _bad("Invalid hand order.")
			var keys: Array = []
			for key: Variant in h.hand_view:
				if (key is not int and key is not float) or float(key) != floorf(float(key)) or absf(float(key)) > 1e9: return _bad("Invalid hand order.")
				keys.append(int(key))
			h.hand_view = keys
		if h.get("kind", "hero") not in ["hero", "monster"]: return _bad("Invalid combatant kind.")
		var drawn: Array[int] = []
		for slot: Variant in h.drawn:
			if slot is not int or slot < 0 or slot >= h.deck.size() or drawn.has(slot): return _bad("Invalid draw sequence.")
			drawn.append(slot)
		if not _enchantments(profile, h.get("enchantments"), enchantment_ids): return _bad("Invalid hero enchantment.")
		if h.has("temporary"):
			# Wizard spirit flight: every warrior spirit flies until the keeper's next turn ends.
			if h.temporary is not Array or h.temporary.size() > 64: return _bad("Invalid temporary hero effect.")
			for effect: Variant in h.temporary:
				if effect is not Dictionary or effect.get("kind") != "spirit_flight" or effect.get("card") != "WRSP" or effect.get("flags") != ["Fly"] or effect.get("keeper") not in [0, 1] or effect.get("id") is not int or effect.id < 1 or enchantment_ids.has(effect.id): return _bad("Invalid temporary hero effect.")
				enchantment_ids.append(effect.id)
		# Saves from before battle artifacts carry none.
		if not h.has("artifacts"): h.artifacts = []
		if not h.has("artifact_uses"): h.artifact_uses = 0
		if h.artifacts is not Array or h.artifact_uses is not int or h.artifact_uses < 0: return _bad("Invalid battle artifacts.")
		var artifacts: Array = []
		for item: Variant in h.artifacts:
			var entry := ELDuel.artifact_entry(profile, item)
			if entry.is_empty() or entry.spell != item.get("spell"): return _bad("Invalid battle artifacts.")
			artifacts.append(entry)
		h.artifacts = artifacts
	if s.phase == 2 and s.winner < 0 and (s.heroes[0].health != 0 or s.heroes[1].health != 0): return _bad("A drawn duel requires both heroes to have fallen.")
	var creatures := {}
	var counts := [0, 0]
	for key: Variant in s.creatures:
		if not str(key).is_valid_int(): return _bad("Invalid creature ID.")
		var id := int(str(key))
		var c: Variant = s.creatures[key]
		if c is not Dictionary or c.get("id") != id or id < 2 or id >= s.next_id or creatures.has(id): return _bad("Invalid creature.")
		for field in ["id", "owner", "power", "toughness", "damage"]:
			if c.get(field) is not int: return _bad("Invalid creature value.")
		if c.owner not in [0, 1] or c.toughness < 1 or c.damage < 0 or c.damage >= c.toughness: return _bad("Invalid creature health.")
		for field in ["resting", "sick", "flying", "regenerated"]:
			if c.get(field) is not bool: return _bad("Invalid creature status.")
		if c.get("flags") is not Array or c.get("card") is not String or (ELCatalog.rule(profile, c.card).get("effect") != "summon" and ELCatalog.ARTIFACT_EFFECTS.get(c.card, {}).get("effect") != "summon"):
			return _bad("Missing creature definition.")
		for flag: Variant in c.flags:
			if flag is not String: return _bad("Invalid creature flag.")
		if c.has("ability_used"):
			if c.ability_used is not Dictionary: return _bad("Invalid creature ability state.")
			for ability: Variant in c.ability_used:
				var pale_rest: bool = profile.id == "el2" and c.card in ELCatalog.PALE_SUMMONS and (ability == "dissipate" or ELCatalog.PALE_ABILITIES.get(c.card, {}).get("key") == ability)
				if not ({"illusion": "WLIL", "rouse": "SHSP", "phantasm": "PHWL"}.get(ability) == c.card or pale_rest) or c.ability_used[ability] is not bool: return _bad("Invalid creature ability state.")
		if c.has("origin") and (c.origin not in [0, 1] or c.origin == c.owner): return _bad("Invalid creature control.")
		if c.has("hit") and (c.hit is not bool): return _bad("Invalid creature combat mark.")
		# Colourless Plane aspect and trap-made spell-jammer base stats (second game).
		if c.has("plane") and (c.plane is not bool or profile.id != "el2"): return _bad("Invalid creature aspect.")
		# Second-game battle scripts may rewrite a new creature's base vector.
		if c.has("script_base") and (c.script_base is not bool or profile.id != "el2" or not c.has("base")): return _bad("Invalid creature base stats.")
		if c.has("base") and ((c.card not in ["OSJ2", "OSJ3"] and not c.get("script_base", false)) or c.base is not Array or c.base.size() != 2 or c.base.any(func(v: Variant) -> bool: return v is not int)): return _bad("Invalid creature base stats.")
		if c.has("decay") and (c.decay is not int or c.decay < 1): return _bad("Invalid creature decay.")
		if c.has("granted") and (c.granted is not Array or c.granted.any(func(f: Variant) -> bool: return f is not String)): return _bad("Invalid creature flag.")
		if c.has("temporary"):
			if c.temporary is not Array or c.temporary.size() > 64: return _bad("Invalid temporary creature effect.")
			for effect: Variant in c.temporary:
				if effect is not Dictionary: return _bad("Invalid temporary creature effect.")
				var illusion: bool = effect.get("kind") == "illusion" and c.card == "WLIL" and effect.get("toughness") is int
				# Mother bee death: bees are aggressive until their source owner's turn ends.
				var frenzy: bool = effect.get("kind") == "frenzy" and effect.get("flags") == ["Berserk"] and effect.get("until_turn_of") in [0, 1]
				# Wall boosts: phantasmal +2 power, lava +X power, hellfire +X health.
				var boost: bool = ({"phantasm": "PHWL", "lava_power": "WLLV", "hellfire_health": "WLIF"}.get(effect.get("kind")) == c.card) and (effect.get("power", 0) is int and effect.get("toughness", 0) is int) and int(effect.get("power", 0)) + int(effect.get("toughness", 0)) >= 1
				# Scroll of blessing: +4/+4 until the end of the user's turn.
				var bless: bool = effect.get("kind") == "bless" and effect.get("power") == 4 and effect.get("toughness") == 4 and effect.get("until_turn_of") in [0, 1]
				if not illusion and not frenzy and not boost and not bless: return _bad("Invalid temporary creature effect.")
				# Earlier saves lacked temporary-effect order. Give them stable IDs
				# after the recorded enchantments; future saves retain exact order.
				if not effect.has("id"):
					effect.id = s.next_enchantment
					s.next_enchantment += 1
				if effect.id is not int or effect.id < 1 or enchantment_ids.has(effect.id): return _bad("Invalid temporary effect sequence.")
				enchantment_ids.append(effect.id)
		if not _enchantments(profile, c.get("enchantments"), enchantment_ids): return _bad("Invalid creature enchantment.")
		counts[c.owner] += 1
		if counts[c.owner] > 10: return _bad("Too many creatures.")
		creatures[id] = c
	var attacks: Array[int] = []
	for id: Variant in s.attacks:
		if id is not int or not creatures.has(id) or creatures[id].owner != s.attacker or attacks.has(id): return _bad("Invalid attacker.")
		attacks.append(id)
	var blocks := {}
	for key: Variant in s.blocks:
		if not str(key).is_valid_int(): return _bad("Invalid blocker ID.")
		var id := int(str(key))
		var target: Variant = s.blocks[key]
		if not creatures.has(id) or creatures[id].owner == s.attacker or target is not int or not attacks.has(target): return _bad("Invalid block order.")
		blocks[id] = target
	if s.phase == 0 and not blocks.is_empty(): return _bad("Block orders outside defence.")
	for id: int in enchantment_ids:
		if id >= s.next_enchantment: return _bad("Invalid enchantment sequence.")
	for combatant: Dictionary in s.heroes + creatures.values():
		for e: Dictionary in combatant.enchantments:
			if e.born < 0 or e.born > s.turn_serial: return _bad("Invalid enchantment age.")
	if not s.has("payment_version") and s.phase == 0:
		# Previous saves reserved attack tax on the attacking hero instead of paying
		# at assignment. Settle exactly that recorded reservation once on migration.
		var copies := 0
		for e: Dictionary in s.heroes[s.attacker].enchantments:
			if e.card == "LSDS": copies += 1
		var price := copies * attacks.size()
		if price > s.heroes[s.attacker].mana: return _bad("Unfunded attack reservation in older save.")
		s.heroes[s.attacker].mana -= price
	s.creatures = creatures
	s.attacks = attacks
	s.blocks = blocks
	return s

static func session(raw: Variant) -> Dictionary:
	# Older duel saves contain only the rules. Optional presentation settings
	# have safe defaults and cannot inject invalid camera transforms.
	var result := {"mode": 0, "camera": []}
	if raw is not Dictionary: return result
	# "mode" is kept for older saves but always resumes against the computer;
	# a HotSeat duel restores from its duel record instead.
	var camera: Variant = raw.get("camera")
	if camera is not Array or camera.size() != 3: return result
	for value: Variant in camera:
		if (value is not float and value is not int) or not is_finite(float(value)): return result
	result.camera = [wrapf(float(camera[0]), -PI, PI), clampf(float(camera[1]), 0.3, 1.05), clampf(float(camera[2]), 15, 40)]
	return result

static func _enchantments(profile: ELProfile, value: Variant, ids: Array[int]) -> bool:
	if value is not Array: return false
	for e: Variant in value:
		if e is not Dictionary or e.get("card") is not String: return false
		# Twister leaves a fixed fatal-disease mark on a creature it could not kill.
		var mark: bool = (ELCatalog.FIRST_MARKS.has(e.card) or e.card == "TWST") and ELCatalog.shared(profile, e.card)
		# Second game: devourer growth marks and the outer ripple's army bonus.
		if profile.id == "el2" and e.card in ["OUD1", "OUD2", "ORPL"]: mark = true
		# Storm mastery's +3/+3 blessing.
		if e.card in ["RLSS", "BWIT"]: mark = true
		var rule := ELCatalog.rule(profile, e.card)
		if rule.get("effect") != "enchant" and not rule.get("enchantment", false) and not ELCatalog.ARTIFACT_EFFECTS.has(e.card) and not mark: return false
		if e.has("fixed") and e.fixed is not bool: return false
		if e.has("lethal") and (e.lethal is not bool or e.card not in ["LASN", "DWND", "ELKS"]): return false
		if e.has("price") and (e.price is not int or e.price < 0): return false
		if e.has("exempt") and (e.card != "WRBN" or e.exempt is not Array or e.exempt.any(func(x: Variant) -> bool: return x is not int)): return false
		for key in ["id", "owner", "born", "power", "toughness"]:
			if e.get(key) is not int: return false
		if e.id < 1 or ids.has(e.id) or e.owner not in [0, 1]: return false
		if e.has("used") and not e.used is bool: return false
		ids.append(e.id)
	return true

static func _integers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _integers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_integers(item))
		return result
	return value

static func _bad(message: String) -> Dictionary:
	return {"error": message}
