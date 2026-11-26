class_name ELArenaRules
extends RefCounted
## One public ruleset for human and computer drafts. Combat remains ordinary
## Etherlords II: sixteen book slots, two Providence charges per slot.

# Existing checkpoints retain their exact offers. New runs choose one of
# the two current pools and keep it for every opponent.
const LEGACY_RULES := 1
const OPEN_RULES := 2
const FACTION_RULES := 3
const DECK_SIZE := 16
const COPY_LIMIT := 4
const WIN_LIMIT := 12
const LOSS_LIMIT := 3
const DEFAULT_LEVEL := 5
const DEFAULT_LEVELS := Vector2i(DEFAULT_LEVEL, DEFAULT_LEVEL)
const SKILLS := {"PRVD": 0}
const FACTIONS: Array[String] = ["Red", "Green", "Blue", "Black"]

## Narrow packages that routinely need a constructed shell or a particular
## opposing deck. Ordinary tribal creatures, sacrifice, ramp and resurrection
## remain available; the drafter values their actual support.
const EXCLUDED := {
	"STSI": "Stasis needs a prepared ether-lock deck.",
	"SMOK": "Smoke can lock the drafter's own creatures without a recovery package.",
	"FLOD": "Flood needs a deliberately built flying or recovery deck.",
	"BLKD": "Defense stops your own attackers and needs another win condition.",
	"CHNL": "Ether Trade needs a planned life-to-ether combination.",
	"TRLB": "Data Attraction needs a tuned noncreature and life-management engine.",
	"COPL": "Life Channel needs reliable repeatable regeneration.",
	"GIFT": "Gift is a campaign spell with a specialized disturbance plan.",
	"PRWT": "Paleness needs a dedicated aspect deck.",
	"PLSL": "Seal needs a reliable Pale-aspect matchup.",
	"PLWP": "Pale Warp depends on Pale creatures staying in play.",
	"PRBN": "Lock Aspect depends on Pale creatures and aspect changes.",
	"PRWR": "Aspect Ward depends on the opposing aspect engine.",
	"ALNS": "Mark of Pale depends on the opponent's Pale army.",
	"OCRP": "Pale Cripple needs a Pale creature in the required aspect.",
	"BNSH": "Banish needs a Pale target.",
	"ORFT": "Pale Revival needs a creature in the required aspect.",
	"OFLX": "Pale Flux needs a prepared aspect board.",
	"OMSW": "Pale Theft depends on the opponent's Pale creatures.",
	"OMWP": "Pale Calamity depends on a dedicated Pale board.",
	"OEXC": "Transfer Aspects needs two creatures in the required aspects.",
	"GBNS": "Vaporize depends on the opponent's Pale creatures.",
	"OST2": "Pale Revenant needs suitable sorcery triggers.",
	"OST3": "Pale Redeemer depends on the opponent casting variable sorceries.",
	"LCWR": "Creature wardings tax both sides and need a constructed cost advantage.",
	"GCWR": "Creature wardings tax both sides and need a constructed cost advantage.",
	"LSWR": "Sorcery wardings need a deliberately asymmetric spell mix.",
	"GSWR": "Sorcery wardings need a deliberately asymmetric spell mix.",
	"LEWR": "Enchantment wardings need a deliberately asymmetric spell mix.",
	"GEWR": "Enchantment wardings need a deliberately asymmetric spell mix.",
}

const REMOVAL := ["destroy", "exile", "annihilate", "fury_of_nature", "swap", "polymorph", "pale_cleave"]
const INTERACTION := ["damage", "wave", "unsummon", "bounce_all", "rest_enemies", "random_discard", "discard_all", "discard_creatures", "mind_blast", "ban", "drain_life"]
const UTILITY_ABILITIES := ["shoot", "sting", "slay", "gaze", "hunt", "wall_break", "breath", "orc_rite", "dispel", "draw", "necromancy", "recall_rat", "recall_lamia", "recall_spirit"]
const SPELL_QUALITY := {
	"FRBL": 5.4, "RNST": 4.8, "MOTI": 5.8, "MOBE": 5.8,
	"CHCM": 6.2, "IMMB": 4.5, "FAIL": 3.0, "DISM": 3.7, "WEAK": 5.2, "DWND": 5.4,
	"STWO": 4.4, "ENWO": 3.5, "DOMN": 5.0, "JYHD": 3.4, "ASLT": 4.2,
	"ANFR": 4.6, "DNFR": 2.3, "SPWB": 2.0, "BASO": 3.7,
	"MNST": 3.2, "MNBR": 3.0, "MNTX": 2.8, "MNVR": 1.7,
	"RBRT": 3.8, "SCBR": 3.5, "RPST": 3.6, "BROT": 3.4, "SACR": 2.7,
	"SPLK": 3.4, "STSK": 3.2, "RIOT": 2.4, "ERBN": 3.1,
	"SFGS": 3.5, "DRGS": 2.8, "FTDS": 2.5, "MNTH": 2.1, "MNBN": 2.2,
	"SPTR": 2.0, "LSDS": 2.0, "PRGD": 2.8, "ENBR": 2.7, "LFGR": 2.3,
	"OST1": 3.7, "REDR": 2.4, "PALN": 2.3, "ETCH": 2.7,
}

static var _cached_profile := 0
static var _cached_generation := -1
static var _features: Dictionary = {}
static var _pools: Dictionary = {}
static var _signatures: Dictionary = {}

static func _cache(source: ELProfile) -> void:
	var token := source.get_instance_id()
	if token == _cached_profile and source.generation == _cached_generation: return
	_cached_profile = token
	_cached_generation = source.generation
	_features.clear()
	_pools.clear()
	_signatures.clear()

static func excluded_reason(source: ELProfile, code: String) -> String:
	if source == null or source.id != "el2": return "Draft Arena requires Etherlords II."
	var row: Dictionary = source.table("CombatSpells").get(code, {})
	if row.is_empty(): return "This spell is not installed."
	if str(row.get("Use", "+")) != "+": return "This spell is disabled in the installed card set."
	if str(row.get("Support", "False")).to_lower() == "true": return "This is an internal or scripted spell."
	if ELDuelCosts.artifact(source, code) or ELCatalog.adventure_only_card(source, code): return "Artifacts and adventure-only spells are outside the draft."
	if String(row.get("Color", "")) not in FACTIONS and row.get("Color") != "White": return "This spell has no playable Arena faction."
	if ELCatalog.rule(source, code).is_empty(): return "This spell's combat behavior is unavailable."
	return String(EXCLUDED.get(code, ""))

static func resource_level(rules_version: int) -> int:
	return ELDuelCosts.EL2_SANDBOX_LEVEL if rules_version == OPEN_RULES else ELDuelCosts.EL2_UNLIMITED_LEVEL

static func _pool_key(faction: String, rules_version: int) -> String:
	match rules_version:
		OPEN_RULES: return "all"
		FACTION_RULES: return "only:" + faction
		_: return faction

static func pool(source: ELProfile, faction: String, rules_version := OPEN_RULES) -> Array[String]:
	var result: Array[String] = []
	if source == null or source.id != "el2" or faction not in FACTIONS: return result
	_cache(source)
	var key := _pool_key(faction, rules_version)
	if _pools.has(key):
		result.assign(_pools[key])
		return result
	var level := resource_level(rules_version)
	var spells := source.table("CombatSpells")
	for code: String in spells:
		if rules_version == FACTION_RULES and spells[code].get("Color") != faction: continue
		if excluded_reason(source, code).is_empty() and ELDuelCosts.spell_allowed(source, code, faction, level): result.append(code)
	result.sort()
	_pools[key] = result.duplicate()
	return result

## Includes printed rules used by the draft, not just the card IDs. A changed
## pool cannot silently reinterpret a checkpoint's already presented offers.
static func pool_signature(source: ELProfile, faction: String, rules_version := OPEN_RULES) -> String:
	var available := pool(source, faction, rules_version)
	if available.is_empty(): return ""
	var key := _pool_key(faction, rules_version)
	if _signatures.has(key): return String(_signatures[key])
	var rows: Array = []
	for code: String in available:
		rows.append([code, source.table("CombatSpells")[code], source.table("CombatCreatures").get(code, {}), features(source, code)])
	var value := JSON.stringify([rules_version, key, DEFAULT_LEVEL, SKILLS, COPY_LIMIT, rows]).sha256_text()
	_signatures[key] = value
	return value

## Read-only derived metadata. The evaluator also counts concrete tribes and
## generators; rarity and shop prices are deliberately not a strength score.
static func features(source: ELProfile, code: String) -> Dictionary:
	_cache(source)
	if _features.has(code): return _features[code]
	var row: Dictionary = source.table("CombatSpells").get(code, {})
	var body: Dictionary = source.table("CombatCreatures").get(code, {})
	var rule := ELCatalog.rule(source, code)
	var ability := ELCatalog.first_ability(source, code)
	if ability.is_empty() and source.id == "el2": ability = ELCatalog.PALE_ABILITIES.get(code, {})
	var aura := ELCatalog.creature_aura(source, code)
	var flags := ELCatalog.flags(body)
	var creature: bool = row.get("Class") == "Creature"
	var effect := String(rule.get("effect", ""))
	var cost := maxi(0, int(row.get("Cost", 0)))
	var channels := int(rule.get("channels_el2", 0))
	var power := int(body.get("Power", 0))
	var toughness := int(body.get("Toughness", 0))
	var tribe := String(body.get("Race", ""))
	var generator: bool = ability.get("key") in ["brood", "necromancy", "recall_rat", "recall_lamia", "recall_spirit"]
	var active_damage: bool = ability.get("key") in ["shoot", "sting", "slay", "gaze", "hunt", "breath", "pale_devour"]
	var dispel: bool = effect in ["dispel", "cleanse", "trade"] or bool(rule.get("dispel", false)) or ability.get("key") in ["dispel", "orc_rite", "absorb"] or flags.has("Disenchant")
	var removal: bool = effect in REMOVAL or bool(rule.get("lethal", false)) or code == "CHCM" or ability.get("key") in ["slay", "pale_devour"]
	var interaction: bool = removal or dispel or effect in INTERACTION or active_damage or int(rule.get("power", 0)) < 0 or code in ["IMMB", "ERBN", "RIOT", "OBLS"]
	var aura_power := int(aura.get("power", 0)) if String(aura.get("race", tribe)) == tribe else 0
	var threat: bool = creature and (power + aura_power > 0 and not flags.has("NoAttack") or generator or active_damage)
	var conditional: bool = bool(rule.get("own", false)) or rule.get("target") == "grave" or rule.has("pale") or rule.has("plane") or not aura.is_empty() or effect in ["trade", "swap", "devour", "sacrifice_heal", "channel"]
	var needs_body: bool = effect in ["trade", "swap", "devour", "sacrifice_heal", "clone"] or rule.get("target") == "creature" and not interaction
	var draw: bool = effect in ["draw", "redraw"] or ability.get("key") == "draw" or code in ["BASO", "SACR"]
	var ramp: bool = effect in ["mana", "channels"] and rule.get("scope", "") not in ["enemy", "steal"] or code in ["MNST", "MNBR", "MNTX", "MNVR", "ORSH"]
	var score := 1.5 - 0.17 * cost
	if creature:
		score = 3.0 + 0.62 * (power + aura_power) + 0.38 * toughness - 0.34 * cost
		if flags.has("Fly"): score += 1.0
		if flags.has("FS"): score += 0.65
		if flags.has("Destroy"): score += 1.8
		if flags.has("UB") or code in ELCatalog.WALL_BLOCKED: score += 1.15
		if flags.has("NSS"): score += 0.55
		if flags.has("Restless"): score += 0.65
		if flags.has("Lifetap"): score += 0.9
		if flags.has("Trample"): score += 0.35
		if flags.has("NoAttack"): score -= 1.2
		if flags.has("NoUntap"): score -= 1.6
		for flag: String in flags:
			if flag.begins_with("Regen("): score += 0.7
			if flag.begins_with("Discard("): score += 0.65
		if generator: score += 2.2
		if active_damage: score += 1.5
		if dispel: score += 1.3
		if ability.get("key") in UTILITY_ABILITIES: score += 0.5
		if code in ELCatalog.PARASITES: score -= 1.4
		if code in ELCatalog.FATALISTS: score -= 0.8
	else:
		if removal: score = 5.5 - 0.18 * cost
		elif effect == "damage": score = 3.0 + 0.6 * int(rule.get("amount", 2)) - 0.2 * cost
		elif effect == "wave": score = 4.7 - 0.18 * cost
		elif effect in ["unsummon", "bounce_all", "rest_enemies"]: score = 3.6 - 0.12 * cost
		elif dispel: score = 3.2 - 0.12 * cost
		elif draw: score = 3.2 + 0.2 * int(rule.get("amount", 0)) - 0.18 * cost
		elif ramp: score = 2.6 + 0.3 * int(rule.get("amount_el2", rule.get("amount", 0))) - 0.15 * cost
		elif effect in ["random_discard", "discard_all", "discard_creatures", "mind_blast", "ban"]: score = 3.4 - 0.16 * cost
		elif effect in ["reanimate", "revive", "repair"]: score = 3.2 - 0.12 * cost
		elif effect == "enchant": score += 0.4 * maxf(0.0, float(rule.get("power", 0)) + float(rule.get("toughness", 0)))
		if code == "OBLS": score = 2.7 # Creature-only dispel; damage requires a Pale target.
		if code == "OCLV": score = 3.6 # Ordinary creatures are bounced, not destroyed.
		if SPELL_QUALITY.has(code): score = float(SPELL_QUALITY[code])
		if channels > 0: score -= 0.8 * channels
	var roles: Array[String] = []
	if creature: roles.append("Creature")
	if threat: roles.append("Threat")
	if generator: roles.append("Generates creatures")
	if removal: roles.append("Removal")
	if dispel: roles.append("Enchantment answer")
	if interaction and not removal and not dispel: roles.append("Interaction")
	if draw: roles.append("Card draw")
	if ramp: roles.append("Ether")
	if not aura.is_empty(): roles.append("Tribal support")
	if roles.is_empty(): roles.append("Support")
	roles.make_read_only()
	flags.make_read_only()
	var result := {"cost": cost, "channels": channels, "creature": creature, "early": creature and threat and cost <= 3,
		"interaction": interaction, "removal": removal, "dispel": dispel, "threat": threat, "generator": generator,
		"tribe": tribe, "tribal_payoff": String(aura.get("race", "")), "summon": String(ability.get("summon", "")),
		"conditional": conditional, "needs_body": needs_body, "draw": draw, "ramp": ramp,
		"power": power, "toughness": toughness, "flags": flags, "effect": effect, "score": score,
		"roles": roles, "faction": String(row.get("Color", "")), "rarity": String(row.get("Rarity", "Common")),
		"persistent": not creature and row.get("Class") == "Enchantment"}
	result.make_read_only()
	_features[code] = result
	return result

static func summary(source: ELProfile, cards: Array) -> Dictionary:
	var result := {"creatures": 0, "early": 0, "threats": 0, "interaction": 0, "removal": 0, "dispel": 0, "generators": 0,
		"draw": 0, "ramp": 0, "expensive": 0, "conditional": 0, "cost": 0, "tribes": {}, "counts": {}}
	for code: String in cards:
		var f := features(source, code)
		result.counts[code] = int(result.counts.get(code, 0)) + 1
		for pair: Array in [["creatures", "creature"], ["early", "early"], ["threats", "threat"], ["interaction", "interaction"], ["removal", "removal"], ["dispel", "dispel"], ["generators", "generator"], ["draw", "draw"], ["ramp", "ramp"], ["conditional", "conditional"]]:
			if f[pair[1]]: result[pair[0]] += 1
		if int(f.cost) >= 6: result.expensive += 1
		result.cost += int(f.cost)
		if not String(f.tribe).is_empty(): result.tribes[f.tribe] = int(result.tribes.get(f.tribe, 0)) + 1
		if not String(f.summon).is_empty():
			var tribe := String(source.table("CombatCreatures").get(f.summon, {}).get("Race", ""))
			if not tribe.is_empty(): result.tribes[tribe] = int(result.tribes.get(tribe, 0)) + 2
	return result

static func validate_deck(source: ELProfile, faction: String, cards: Array, rules_version := OPEN_RULES) -> Array[String]:
	var errors: Array[String] = []
	if source == null or source.id != "el2": errors.append("Arena requires Etherlords II.")
	if faction not in FACTIONS: errors.append("Unknown Arena faction.")
	if cards.size() != DECK_SIZE: errors.append("An Arena spellbook must contain exactly sixteen picks.")
	if not errors.is_empty(): return errors
	var eligible := pool(source, faction, rules_version)
	var counts := {}
	for card: Variant in cards:
		if card is not String or card not in eligible:
			errors.append("A spell is outside this Arena pool: %s." % str(card))
			continue
		counts[card] = int(counts.get(card, 0)) + 1
		if int(counts[card]) > COPY_LIMIT: errors.append("Too many copies of %s." % card)
	return errors

static func hero_preset(source: ELProfile, faction: String, cards: Array, rules_version := OPEN_RULES, level := DEFAULT_LEVEL, loadout: Dictionary = NO_LOADOUT) -> Dictionary:
	if not validate_deck(source, faction, cards, rules_version).is_empty(): return {}
	var preset := ELDuelPresets.blank(faction, resource_level(rules_version))
	preset.level = level
	preset.skills = SKILLS.duplicate()
	preset.cards = cards.duplicate()
	preset.name = "Arena " + ELCatalog.faction_name(faction)
	preset.specialization = String(loadout.get("specialization", "NONE"))
	preset.artifacts = Array(loadout.get("artifacts", [])).duplicate()
	return preset

# --- Heroes ---------------------------------------------------------------------

## Runs saved before heroes were varied: the heroes.def figure, no
## specialization and no artifact.
const NO_LOADOUT := {"template": "", "specialization": "NONE", "artifacts": []}

## The race's duel portraits (non-quest templates of its colour), one per
## figure, in name order: every entry is a different-looking hero.
static func hero_templates(source: ELProfile, faction: String) -> Array[String]:
	var rows := source.table("HeroTemplates")
	var names: Array = rows.keys()
	names.sort()
	var models := {}
	var result: Array[String] = []
	for key: String in names:
		var row: Dictionary = rows[key]
		if String(row.get("Color", "")) != faction or String(row.get("Quest", "")) == "Yes": continue
		var model := String(row.get("Model", ""))
		if model.is_empty() or models.has(model): continue
		models[model] = true
		result.append(key)
	return result

## Specializations the race may hold, by code.
static func specializations(source: ELProfile, faction: String) -> Array[String]:
	var result: Array[String] = []
	for code: String in source.table("HeroesSpecs"):
		if code != "NONE" and ELDuelCosts.spec_allowed(source, code, faction) and ELSpecs.valid(source, code): result.append(code)
	result.sort()
	return result

## Up to `count` distinct entries of `choices`, fixed by `seed`, in list order.
static func offer(choices: Array[String], seed: int, count: int) -> Array[String]:
	var shuffled := choices.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = ELDuelMatch._mix(seed ^ 0x7a19c35b)
	for i in range(shuffled.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var held: String = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = held
	shuffled.resize(mini(count, shuffled.size()))
	var result: Array[String] = []
	for code: String in choices:
		if code in shuffled: result.append(code)
	return result

## A hero for one Arena seat: a figure of the race (not `avoid`'s), one of its
## specializations and one duel artifact, all fixed by `seed`.
static func loadout(source: ELProfile, faction: String, seed: int, avoid := "") -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = ELDuelMatch._mix(seed ^ 0x3e5a71c9)
	var templates := hero_templates(source, faction)
	templates.erase(avoid)
	var specs := specializations(source, faction)
	var artifacts := ELDuelCosts.duel_artifacts(source)
	var template := templates[random.randi_range(0, templates.size() - 1)] if not templates.is_empty() else ""
	var spec := specs[random.randi_range(0, specs.size() - 1)] if not specs.is_empty() else "NONE"
	var items: Array = []
	if not artifacts.is_empty(): items.append(artifacts[random.randi_range(0, artifacts.size() - 1)])
	return {"template": template, "specialization": spec, "artifacts": items}
