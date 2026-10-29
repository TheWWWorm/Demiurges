class_name ELDuel
extends RefCounted
signal changed
signal event(data: Dictionary)

enum Phase { ATTACK, DEFENCE, FINISHED }
var profile: ELProfile
var hero_template: Dictionary = {}
var heroes: Array[Dictionary] = []
var creatures: Dictionary = {}
var attacks: Array[int] = []
var blocks: Dictionary = {}
var history: Array[Dictionary] = []
var phase := Phase.ATTACK
var attacker := 0
var round_number := 1
var winner := -1
var next_id := 2
var next_enchantment := 1
var turn_serial := 0
var rng_state := 212
var error := ""
var load_note := ""
var setup: Dictionary = {}
## Second-game spell-jammer traps: hidden hero enchantments that no dispel removes.
const TRAPS := ["OST1", "OST2", "OST3"]
## Pale revival's second target: graveyard side * GRAVE_SIDE + index.
const GRAVE_SIDE := 1000
## EL1 player variables 2 (positive) and 3 (negative): each listed
## enchantment's attach raises its caster's counter and its detach lowers it
## through (census of every call; e.g. Flood). The
## turn entry shows PosRune/NegRune at the acting hero while either is set.
const EL1_POS_RUNE_SOURCES := ["ANFR", "BASO", "BLKD", "BROT", "CMBN", "COPL", "CRBL", "DMRD", "DNFR", "DOMN", "DRFR",
	"ENLH", "ENRG", "ENWO", "FRBL", "FRGS", "FTDS", "HAST", "HOAM", "IMML", "JYHD", "LMWD", "LSHE", "MNTX", "RBRT", "RNST",
	"RPST", "SACR", "SCBR", "SMGS", "SPLK", "SPWB", "STWO", "TRLB", "VTLY", "WRBN"]
const EL1_NEG_RUNE_SOURCES := ["CNAR", "DPGS", "DRGS", "ENVM", "FLOD", "LSDS", "MNBN", "MNTH", "SFGS", "SMOK", "SPTR",
	"STSI", "STTX", "SWSN", "TRSN", "WETX"]
## EL2 hero variables 2 (positive) and 3 (negative), raised by each listed
## enchantment's attach and lowered by its detach through, on the
## caster's record. The turn transition shows PosRune/NegRune
## the acting hero while either is non-zero (sites).
const EL2_POS_RUNE_SOURCES := ["ANFR", "BASO", "BLKD", "BROT", "CMBN", "COPL", "CRBL", "DMRD", "DNFR", "DOMN", "DRFR",
	"ENBR", "ENRG", "ENWO", "FRBL", "FRGS", "FTDS", "HAST", "HOAM", "IMML", "JYHD", "LFGR", "LMWD", "LSHE", "MNTX", "OEXC",
	"OST1", "OST2", "OST3", "PLSL", "RBRT", "RNST", "RPST", "SACR", "SCBR", "SMGS", "SPLK", "SPWB", "STSK", "STWO", "TRLB",
	"VTLY", "WRBN"]
## Creature variable 0 / 1 writers (attach +1, detach -1), from the setter
## census. EL1: 22 / 11 classes plus the Wall
## Illusion spec mark. EL2 adds its own cards and has no
## spec-mark writer. Alien Lace is never instantiated.
const EL1_CREATURE_POS_RUNE_SOURCES := ["AILK", "CLFR", "DELS", "ETAM", "LSST", "MGHT", "PSBR", "REDR", "SCSK", "SGHT",
	"SHCL", "SHFR", "SHSK", "SLRP", "SPBA", "SPWR", "STAT", "STRG", "TGSK", "THIF", "UPGD", "WTLK"]
const EL1_CREATURE_NEG_RUNE_SOURCES := ["BWIT", "DISM", "DWND", "FAIL", "IMMB", "IRRT", "MDNS", "PALN", "RDIS", "TWEN",
	"WEAK", "WNPZ"]
const EL2_CREATURE_POS_RUNE_SOURCES := ["AILK", "ALNS", "CLFR", "DELS", "ENBR", "ETAM", "LFGR", "LSST", "MGHT", "PRBN",
	"PRGD", "PSBR", "REDR", "SCSK", "SGHT", "SHCL", "SHFR", "SHSK", "SLRP", "SPBA", "SPWR", "STAT", "STRG", "STSK",
	"TGSK", "THIF", "UPGD", "WTLK"]
const EL2_CREATURE_NEG_RUNE_SOURCES := ["DISM", "DWND", "ENFL", "FAIL", "IMMB", "IRRT", "MDNS", "OCRP", "PALN", "RDIS",
	"TWEN", "WEAK", "WNPZ"]
const EL2_NEG_RUNE_SOURCES := ["ASST", "CNAR", "DPGS", "DRGS", "ENVM", "FLOD", "GCWR", "GEWR", "GSWR", "LCWR", "LEWR",
	"LSDS", "LSWR", "MNBN", "MNTH", "PLWP", "PRWR", "PRWT", "SFGS", "SMOK", "SPTR", "STSI", "STTX", "SWSN", "TRSN", "ESWS", "ETRS", "WETX",
	"WTX2"]
## EL1 - checks four concrete creature identifiers,
## not a general Race=Dragon attribute, during graveyard recovery.
const EL1_IMMORTAL_DRAGONS := ["BUDG", "BLDG", "GRDG", "RDDG"]
## Set while cleaving: a Pale creature then dies instead of dissipating.
var _plane_guard := false
## Ether-disturbance and backlash damage skip the hero's protective specialisations.
var _raw_hero_damage := false
## Second-game battle scripts (ELBattleScripts), or null.
var scripts: ELBattleScripts
## The caster of a script cast while its legality and effect resolve, or -1.
var _acting := -1
## Script hero damage kind: 1 skips redirection and feedback, 2 is raw.
var _hero_damage_kind := 0
var _session: WeakRef
## A replay controller (ELCombatTutorial) that vets every action before it runs:
## gate_check(duel, action) may refuse it or redirect a cast to another hand
## index; gate_done(duel, action, ok) follows each vetted action.
var gate: Object = null
## Serial of the next card put into a hand (the original's per-battle card id),
## tracked in each hero's `hand_ids` when the start options ask for card ids.
var next_card := 0

## Campaign battles share the mission variables and difficulty with their
## adventure session (held weakly; the session owns the encounter).
func attach_session(session: RefCounted) -> void:
	_session = weakref(session) if session != null else null

func adventure_session() -> Variant:
	return _session.get_ref() if _session != null else null

func start(data: ELProfile, seed_value := 212, options: Dictionary = {}) -> bool:
	profile = data
	error = ""
	load_note = ""
	if not profile.table("CombatSceneDB").has(options.get("arena", "Green.001")):
		return _fail("Missing battlefield.")
	var prepared: Array[Dictionary] = []
	for side in 2:
		var choice: Dictionary = options.get("players", [{}, {}])[side]
		var faction := String(choice.get("faction", "Red"))
		if not ELCatalog.faction_known(profile, faction): return _fail("Unknown faction: " + faction)
		var name := String(choice.get("hero", ELCatalog.default_hero(data, faction)))
		var template: Dictionary = profile.table("HeroTemplates").get(name, {})
		if template.is_empty(): return _fail("Missing hero template: " + name)
		var cards: Array = choice.get("cards", ELCatalog.deck(profile, String(choice.get("deck", ELCatalog.STARTERS.get(faction, ""))))).duplicate()
		# Second-game adventure battles copy each side's book as it stands and
		# never refuse an empty one; that hero simply draws nothing. Duel mode
		# books are full (the deck editor keeps 16).
		if cards.is_empty() and not (options.get("adventure", false) and profile.id == "el2"): return _fail("A spellbook cannot be empty.")
		for card: String in cards:
			if ELCatalog.rule(profile, card).is_empty(): return _fail("Spell is not available yet: " + card)
			if not options.get("adventure", false) and not _book_colour(String(profile.table("CombatSpells")[card].get("Color", "")), faction): return _fail("Spell belongs to another faction: " + card)
		var level := int(choice.get("level", template.get("Level", 1)))
		if not profile.table("CombatManaIncome").get("1", {}).has("Level%d" % level): return _fail("Unsupported hero level.")
		var skill_values: Variant = choice.get("skills", ELHeroSkills.from_template(profile, template))
		if not ELHeroSkills.valid_ranks(profile, skill_values): return _fail("Invalid hero skills.")
		var skills := {}
		for code: String in skill_values: skills[code] = int(skill_values[code])
		var health := int(template.BaseHealth) + int(template.HealthIncrease) * level
		if options.get("adventure", false):
			health = maxi(1, int(choice.get("health", health)))
		elif skills.has("HEAL"):
			health = int(health * [1.1, 1.2, 1.3][skills.HEAL] + 0.5)
		prepared.append({"id": side, "health": health, "maximum": health, "mana": 0,
			"channels": 0, "level": level, "hand": [], "hand_slots": [], "deck": cards, "drawn": [], "grave": [], "turns": 0,
			"faction": faction, "template": name, "skills": skills, "kind": "hero", "enchantments": []})
		if options.get("adventure", false):
			var shape := String(choice.get("shape", ""))
			if not shape.is_empty() and not profile.table("Shapes").has(shape): return _fail("Missing hero shape: " + shape)
			prepared[-1].shape = shape
			prepared[-1].kind = choice.get("kind", "hero")
			prepared[-1].title = choice.get("title", name)
			if choice.has("monster_name"):
				if choice.monster_name is not String or not ELLuaSave._integer(choice.get("monster_difficulty"), 0, 4) or choice.get("kind") != "monster" or ELFirstMonsters.appearance(profile, choice.monster_name, int(choice.monster_difficulty)).is_empty(): return _fail("Missing neutral creature appearance.")
				prepared[-1].monster_name = choice.monster_name
				prepared[-1].monster_difficulty = int(choice.monster_difficulty)
		if not ELSpecs.valid(profile, choice.get("specialization", "NONE")): return _fail("Unknown hero specialization.")
		ELSpecs.prepare(prepared[-1], choice)
		prepared[-1].spell_uses = ELSpellCharges.initial(profile, prepared[-1], bool(options.get("adventure", false)), choice)
		if not ELSpellCharges.valid(profile, prepared[-1]): return _fail("Invalid starting spell charges.")
		prepared[-1].artifacts = []
		prepared[-1].artifact_uses = 0
		for item: Variant in choice.get("artifacts", []):
			var entry := artifact_entry(profile, item)
			if entry.is_empty(): return _fail("Artifact is not available yet: " + str(item.get("name", "") if item is Dictionary else item))
			prepared[-1].artifacts.append(entry)
	var script_list: Variant = options.get("scripts", [])
	if script_list is not Array: return _fail("Invalid battle scripts.")
	for entry: Variant in script_list:
		if entry is not Dictionary or entry.get("name") is not String or entry.get("side") not in [0, 1]: return _fail("Invalid battle scripts.")
	if not script_list.is_empty() and profile.id != "el2": return _fail("Battle scripts belong to the second game.")
	# The side taking the first attack phase (decided by the caller: Duel-mode
	# coin flip or the adventure home-terrain rule).
	if options.get("first_side", 0) is not int or int(options.get("first_side", 0)) not in [0, 1]: return _fail("Invalid first side.")
	if options.get("script_variables", {}) is not Dictionary or options.get("script_difficulty", 1) not in [0, 1, 2]: return _fail("Invalid battle script settings.")
	if options.get("opening_interleave", -1) not in [-1, 0, 1]: return _fail("Invalid opening order.")
	# A selected EL1 combat event can be supplied by a prepared battle, like the
	# original's preset event. The shipped random picker never picks
	# one (returns 0), and only ARUE/ARUL/CRDS have code behind them:
	# the cost events are read, which no battle reaches; ADMN, CRRG,
	# ENDS, GAPI and GAPR exist only as descriptions.
	var opening_event: Variant = options.get("combat_event", "")
	if opening_event is not String or (not String(opening_event).is_empty() and (profile.id != "el1" or (not EL1_ARTIFACT_ROUND_EVENTS.has(opening_event) and not EL1_TURN_EVENTS.has(opening_event)))):
		return _fail("Unsupported opening combat event.")
	if options.get("card_ids", false):
		for hero: Dictionary in prepared: hero.hand_ids = []
	heroes = prepared
	hero_template = profile.table("HeroTemplates")[heroes[0].template]
	setup = options.duplicate(true)
	rng_state = seed_value & 0xffffffff
	creatures.clear()
	attacks.clear()
	blocks.clear()
	history.clear()
	phase = Phase.ATTACK
	attacker = first_side()
	round_number = 1
	winner = -1
	next_id = 2
	next_enchantment = 1
	turn_serial = 0
	next_card = 0
	if scripts != null: scripts.close()
	scripts = null
	if not script_list.is_empty():
		# Script states load and initialise before the opening hands.
		scripts = ELBattleScripts.new(self)
		scripts.local_variables = options.get("script_variables", {}).duplicate()
		scripts.difficulty = int(options.get("script_difficulty", 1))
		scripts.load_all(script_list)
	# Both sides open with five cards; the second side's sixth arrives with the
	# normal draw at the start of its first turn (EL1, EL2).
	# Both originals alternate the sides card by card, side 0 first (EL1
	# EL2); `opening_interleave` names the side drawing
	# first when a replay maps the original sides differently, and -1 deals
	# side by side.
	var first_draw := int(options.get("opening_interleave", 0))
	if first_draw >= 0:
		for i in 5:
			for side in [first_draw, 1 - first_draw]: _draw(side)
	else:
		for side in 2:
			for i in 5: _draw(side)
	# EL1 then rolls the battle's combat event once when none was
	# preset. The shipped picker always answers "no event", so only
	# the generator step remains.
	if profile.id == "el1" and String(opening_event).is_empty(): random_index(1)
	if EL1_ARTIFACT_ROUND_EVENTS.has(opening_event):
		_artifact_event_opening(String(opening_event))
	elif EL1_TURN_EVENTS.has(opening_event):
		_emit({"kind": "combat_event", "code": opening_event})
	# First-game player global spells take effect as the battle starts.
	for side in 2:
		var effects: Variant = options.get("players", [{}, {}])[side].get("global_effects", [])
		if not effects is Array: return _fail("Invalid global spell effects.")
		for code: Variant in effects:
			if profile.id != "el1" or not code in GLOBAL_BATTLE_EFFECTS: return _fail("Invalid global spell effects.")
			_global_start(side, str(code))
	_begin_attack(false)
	return true

const GLOBAL_BATTLE_EFFECTS := ["LGWR", "RLWP", "FRGF", "HSTL"]
const EL1_ARTIFACT_ROUND_EVENTS := {"ARUE": 1, "ARUL": -1}
const EL1_TURN_EVENTS := ["CRDS"]

## EL1 applies the battle-opening event to each side's artifact
## usable-from round, clamped at zero. The binary's ARUE/ARUL signs
## contradict the event descriptions; preserve the inspected executable
## behavior rather than silently exchanging their labels.
func _artifact_event_opening(code: String) -> void:
	var shift: int = EL1_ARTIFACT_ROUND_EVENTS[code]
	for hero: Dictionary in heroes:
		for item: Dictionary in hero.artifacts:
			item.ready_round = maxi(0, int(item.ready_round) + shift)
	_emit({"kind": "combat_event", "code": code})

## Lightning Wrath: 3 damage to the opponent hero (through its protections);
## Channel Warp: the opponent starts one ether channel down; Gifts of the Forest:
## a Tree Snake for the owner; Hypnotism: Hostile Environment for the owner.
func _global_start(side: int, code: String) -> void:
	_emit({"kind": "global_spell", "side": side, "spell": code})
	match code:
		"LGWR": _hurt_hero(1 - side, 3)
		"RLWP": heroes[1 - side].channels -= 1
		"FRGF": _summon(side, "TRSN")
		"HSTL": _enchant("HOAM", side, side, {})

## A validated battle artifact: catalog name, effect code, charges and the first
## artifact round in which it may be used again.
static func artifact_entry(data: ELProfile, item: Variant) -> Dictionary:
	if item is not Dictionary or item.get("name") is not String: return {}
	if data.id == "el2": return _second_artifact_entry(data, item)
	if data.id != "el1": return {}
	var row: Dictionary = data.table("Artefacts").get(item.name, {})
	var spell := String(row.get("SpellType", ""))
	if row.is_empty() or not ELCatalog.ARTIFACT_EFFECTS.has(spell) or not data.table("CombatSpells").has(spell): return {}
	var charges: Variant = item.get("charges", int(row.get("MaxCharges", 0)))
	var ready_round: Variant = item.get("ready_round", int(row.get("FirstUsage", 0)))
	if charges is float and charges == floor(charges): charges = int(charges)
	if ready_round is float and ready_round == floor(ready_round): ready_round = int(ready_round)
	if charges is not int or ready_round is not int or charges < 0 or ready_round < 0: return {}
	return {"name": item.name, "spell": spell, "charges": charges, "ready_round": ready_round}

## Second game: the table's current charges, a
## generated artifact's own definition (its spell is cast free), and the Blank,
## listed with no charges and never usable.
static func _second_artifact_entry(data: ELProfile, item: Dictionary) -> Dictionary:
	var definition := {}
	var spell := ""
	var first := 0
	if item.has("custom"):
		definition = ELSecondArtifacts.custom_definition(data, item.custom)
		if definition.is_empty(): return {}
		spell = definition.spell
		first = int(definition.first)
		var rule := ELCatalog.rule(data, spell)
		if rule.is_empty() or rule.get("variable", false): return {}
	else:
		var row: Dictionary = data.table("Artefacts").get(item.name, {})
		spell = String(row.get("SpellType", ""))
		first = int(row.get("FirstUsage", 0))
		if row.is_empty() or not data.table("CombatSpells").has(spell) or not (ELCatalog.ARTIFACT_EFFECTS.has(spell) or spell == ELSecondArtifacts.BLANK_SPELL): return {}
	var charges: Variant = item.get("charges", int(definition.get("max", 0)) if item.has("custom") else ELSecondArtifacts.max_charges(data, item))
	var ready_round: Variant = item.get("ready_round", first)
	if charges is float and charges == floor(charges): charges = int(charges)
	if ready_round is float and ready_round == floor(ready_round): ready_round = int(ready_round)
	if charges is not int or ready_round is not int or charges < 0 or ready_round < 0: return {}
	if spell == ELSecondArtifacts.BLANK_SPELL: charges = 0
	var result := {"name": item.name, "spell": spell, "charges": charges, "ready_round": ready_round}
	if not definition.is_empty(): result.custom = definition
	return result

## The use rule of a battle artifact: the edition's artifact effect (Rod of
## Colossus also hits the rest of the target's side for 1, in both games), a generated
## artifact's spell rule, or nothing for the Blank.
func artifact_rule(item: Dictionary) -> Dictionary:
	if item.has("custom"):
		var spell_rule := ELCatalog.rule(profile, item.spell)
		var target := "none" if spell_rule.get("self", false) or spell_rule.get("opponent", false) else String(spell_rule.get("target", "none"))
		return {"effect": "spell", "target": target}
	if not ELCatalog.ARTIFACT_EFFECTS.has(item.spell): return {"effect": "none", "target": "none"}
	var rule: Dictionary = ELCatalog.ARTIFACT_EFFECTS[item.spell]
	if item.spell == "RDCL":
		rule = rule.duplicate()
		rule.splash_side = 1
	return rule

## The artifact's shown name: the first game names it by its spell.
func artifact_title(item: Dictionary) -> String:
	if profile.id != "el2": return card_name(item.spell)
	return ELSecondArtifacts.title(profile, item)

## Rounds until the next use: the template's UsageGap or a generated artifact's own.
func _artifact_gap(item: Dictionary) -> int:
	if item.has("custom"): return int(item.custom.get("gap", 0))
	return int(profile.table("Artefacts")[item.name].get("UsageGap", 0))

## Artifact cadence counts full rounds shared by both heroes: each turn start
## advances the battle's turn counter, and both first turns are round one.
func artifact_round() -> int:
	return turn_serial / 2 + 1

## Uses of all artifacts are limited per battle: one, or 2/4/8 with Artificer.
func artifact_limit(side: int) -> int:
	var skills: Dictionary = heroes[side].get("skills", {})
	return [2, 4, 8][clampi(int(skills.ARTF), 0, 2)] if skills.has("ARTF") else 1

func artifact_error(side: int, index: int) -> String:
	if phase == Phase.FINISHED or side not in [0, 1] or side != active_side(): return "Artifacts can be used only by the acting hero."
	var list: Array = heroes[side].get("artifacts", [])
	if index < 0 or index >= list.size(): return "Select an artifact."
	var item: Dictionary = list[index]
	if item.spell == ELSecondArtifacts.BLANK_SPELL: return "A blank artifact cannot be used in combat."
	if int(item.charges) <= 0: return "This artifact has no charges left."
	if int(heroes[side].get("artifact_uses", 0)) >= artifact_limit(side): return "No more artifacts can be used in this battle."
	if int(item.ready_round) > artifact_round(): return "This artifact is recharging until round %d." % int(item.ready_round)
	var rule := artifact_rule(item)
	var use_in := String(profile.table("CombatSpells")[item.spell].get("UseIn", "Both"))
	if rule.get("phase") == "defence" and phase != Phase.DEFENCE: return "This artifact can be used only during defence."
	if (use_in == "Attack" and phase != Phase.ATTACK) or (use_in in ["Defence", "Defense"] and phase != Phase.DEFENCE): return "This artifact cannot be used in the current phase."
	if rule.get("phase", "attack") == "attack" and phase != Phase.ATTACK: return "This artifact can be used only while attacking."
	return ""

## Why `target` (and `choice`: enchantment ID or graveyard index) cannot receive this artifact.
func artifact_target_error(side: int, spell: String, target: int, choice := -1) -> String:
	if not ELCatalog.ARTIFACT_EFFECTS.has(spell): return "This artifact cannot be used in combat."
	var rule: Dictionary = ELCatalog.ARTIFACT_EFFECTS[spell]
	match rule.target:
		"creature":
			if not creatures.has(target) or not targetable(target): return "Select a creature."
		"any":
			if entity(target).is_empty() or not targetable(target): return "Select a creature or hero."
		"enchantment":
			var holder := find_enchantment(choice)
			if holder < 0 or holder != target or not dispellable(holder, _enchantment_by_id(holder, choice)): return "Choose an enchantment that can be removed."
		"grave":
			if target != side or choice < 0 or choice >= heroes[side].grave.size() or not profile.table("CombatCreatures").has(heroes[side].grave[choice]): return "Choose a creature in your graveyard."
	if rule.get("attacking", false) and not attacks.has(target): return "Select an attacking creature."
	if rule.get("control", false):
		if creatures[target].owner == side: return "Select an enemy creature."
		if attacks.has(target) or blocks.has(target): return "This creature is in combat."
	if (rule.effect == "summon" or rule.effect == "reanimate" or rule.get("control", false)) and army(side).size() >= 10: return "A hero can control at most ten creatures."
	return ""

func use_artifact(side: int, index: int, target := -1, choice := -1) -> bool:
	if gate == null: return _use_artifact_now(side, index, target, choice)
	var action := {"kind": "artifact", "side": side, "index": index, "target": target, "choice": choice}
	if not gate.gate_check(self, action): return _refused()
	var ok := _use_artifact_now(side, index, target, choice)
	gate.gate_done(self, action, ok)
	return ok

func _use_artifact_now(side: int, index: int, target := -1, choice := -1) -> bool:
	error = ""
	var invalid := artifact_error(side, index)
	if not invalid.is_empty(): return _fail(invalid)
	var item: Dictionary = heroes[side].artifacts[index]
	if item.has("custom"): return _use_custom_artifact(side, item, target, choice)
	var rule := artifact_rule(item)
	if rule.get("self", false): target = side
	invalid = artifact_target_error(side, item.spell, target, choice)
	if not invalid.is_empty(): return _fail(invalid)
	item.charges = int(item.charges) - 1
	item.ready_round = artifact_round() + _artifact_gap(item)
	heroes[side].artifact_uses = int(heroes[side].get("artifact_uses", 0)) + 1
	var shown := {"kind": "artifact", "side": side, "artifact": item.name, "card": item.spell, "target": target, "charges": item.charges}
	if profile.id == "el2": shown.title = artifact_title(item)
	_emit(shown)
	match rule.effect:
		"enchant": _enchant(item.spell, side, target, rule)
		"damage":
			# Splash victims are fixed before the main hit: the rest of the target's side.
			var splashed: Array[int] = []
			if rule.get("splash_side", 0) > 0 and not entity(target).is_empty():
				var victim_side := target if target < 2 else int(creatures[target].owner)
				if victim_side != target: splashed.append(victim_side)
				for c: Dictionary in army(victim_side):
					if int(c.id) != target: splashed.append(int(c.id))
			_damage(target, int(rule.amount))
			for id: int in splashed:
				if phase != Phase.FINISHED and not entity(id).is_empty(): _damage(id, int(rule.splash_side))
		"destroy": _destroy(target, rule.get("no_regeneration", false))
		"dispel": _dispel(target, choice)
		"summon": _summon(side, item.spell)
		"heal":
			heroes[side].health += int(rule.amount)
			_emit({"kind": "heal", "target": side, "amount": int(rule.amount)})
		"reanimate":
			var revived: String = heroes[side].grave[choice]
			heroes[side].grave.remove_at(choice)
			_summon(side, revived)
		"bless":
			# In both games, the blessing ends with the first turn
			# its holder's controller does not play; the user's own creature
			# keeps it through the opponent's turn, an enemy creature loses it
			# when the user's turn ends.
			var blessed: Dictionary = creatures[target]
			if not blessed.has("temporary"): blessed.temporary = []
			blessed.temporary.append({"id": next_enchantment, "kind": "bless", "power": int(rule.power), "toughness": int(rule.toughness)})
			next_enchantment += 1
			_refresh_stats(blessed)
	_finish_action()
	return true

## A generated (constructor) artifact casts its spell like a script cast, with
## no ether, hand card or caster specialisations, but with the artifact's
## presentation. Its target follows the spell's own rule.
func _use_custom_artifact(side: int, item: Dictionary, target: int, choice: int) -> bool:
	var rule := ELCatalog.rule(profile, item.spell)
	if rule.get("self", false): target = side
	if rule.get("opponent", false): target = 1 - side
	_acting = side
	var invalid := _cast_error(side, item.spell, rule, target, choice)
	if invalid.is_empty(): invalid = channel_error(item.spell, side)
	if not invalid.is_empty():
		_acting = -1
		return _fail(invalid)
	var traps := _sorcery_traps()
	item.charges = int(item.charges) - 1
	item.ready_round = artifact_round() + _artifact_gap(item)
	heroes[side].artifact_uses = int(heroes[side].get("artifact_uses", 0)) + 1
	_emit({"kind": "artifact", "side": side, "artifact": item.name, "card": item.spell, "target": target, "charges": item.charges, "title": artifact_title(item)})
	_resolve_spell(side, item.spell, rule, target, choice, 0, traps, false)
	_acting = -1
	_finish_action()
	return true

func active_side() -> int:
	return attacker if phase == Phase.ATTACK else 1 - attacker

## The side whose spell is being validated or resolved: a script caster, else the acting hero.
func _me() -> int:
	return _acting if _acting >= 0 else active_side()

func cost(card: String) -> int:
	var base := int(profile.table("CombatSpells").get(card, {}).get("Cost", 999))
	if profile.id == "el2":
		# Wardings: lesser +2 per copy, greater + the printed cost per copy.
		var printed := base
		var kind := str(profile.table("CombatSpells").get(card, {}).get("Class", ""))
		for ward: String in ELCatalog.WARDINGS:
			if ELCatalog.WARDINGS[ward][0] == kind: base += global_enchantment_count(ward) * (printed if ELCatalog.WARDINGS[ward][1] else 2)
	if str(profile.table("CombatCreatures").get(card, {}).get("Race", "")) == "Lamia":
		# Each Lamia summoner in play lowers every Lamia's cost by two, to at least one.
		var summoners := 0
		for c: Dictionary in creatures.values():
			if c.card == "LMWD": summoners += 1
		if summoners > 0: base = maxi(1, base - 2 * summoners)
	return base

func variable_power(card: String) -> bool:
	return bool(ELCatalog.rule(profile, card).get("variable", false))

func channel_cost(card: String) -> int:
	return int(ELCatalog.rule(profile, card).get("channels_el2", 0)) if profile.id == "el2" else 0

func maximum_power(card: String) -> int:
	if not variable_power(card): return 0
	# Channel offers every value up to the caster's current health, which kills it.
	if ELCatalog.rule(profile, card).get("x_source") == "health": return maxi(0, int(heroes[active_side()].health))
	return maxi(0, available_mana(active_side()) - cost(card))

## The ether a variable spell's X adds to its price.
func power_price(card: String, power: int) -> int:
	return 0 if ELCatalog.rule(profile, card).get("x_source") == "health" else power

func effect_amount(rule: Dictionary) -> int:
	return int(rule.get("amount_el2", rule.get("amount", 0))) if profile.id == "el2" else int(rule.get("amount", 0))

func channel_error(card: String, side: int) -> String:
	var rule := ELCatalog.rule(profile, card)
	if rule.get("effect") != "channels": return ""
	if rule.get("scope") == "behind" and heroes[side].channels >= heroes[1 - side].channels:
		return "Your opponent must have more ether channels."
	if rule.get("scope") in ["enemy", "steal"] and heroes[1 - side].channels < effect_amount(rule):
		return "Your opponent has no ether channel to remove."
	return ""

func _change_ether(side: int, mana_delta := 0, channel_delta := 0) -> void:
	# In EL2 Stasis also blocks channel-only edits, including channel losses.
	if profile.id == "el2" and mana_delta >= 0 and global_enchantment_count("STSI") > 0: return
	heroes[side].mana += mana_delta
	heroes[side].channels += channel_delta
	if mana_delta != 0: _emit({"kind": "ether", "side": side, "amount": mana_delta})
	if channel_delta != 0: _emit({"kind": "channels", "side": side, "amount": channel_delta})

func _spend_ether(side: int, amount: int) -> void:
	if amount <= 0: return
	heroes[side].mana -= amount
	# Resolve the whole command before deciding victory, even if payment is lethal.
	var copies := global_enchantment_count("MNTH")
	# Thorn mastery: each spent ether may be spared, once for all copies.
	var thorns := amount - (ELSpecs.roll(self, side, "GMTM", amount) if copies > 0 else 0)
	if thorns > 0:
		for copy in copies:
			_trigger_damage("MNTH", side, thorns)
			_camera_cue("MNTH", side)

## Enfeeblement holds creature `id` resting until broken (an enchantment in
## the second game, a creature status in the first).
func enfeebled(id: int) -> bool:
	return creatures.has(id) and (bool(creatures[id].get("enfeebled", false)) or _enchantment_count(id, "ENFL") > 0)

## Water links naming creature `id` (hero-held; older saves may still hold one on the creature
## itself).
func water_links(id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments:
			if e.card == "WTLK" and int(e.get("link", -1)) == id: result.append(e)
	if creatures.has(id):
		for e: Dictionary in creatures[id].enchantments:
			if e.card == "WTLK": result.append(e)
	# Creation order: per-copy cues and the first eligible return follow it.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result

func global_enchantment_count(card: String) -> int:
	return _enchantment_count(0, card) + _enchantment_count(1, card)

func recovery_blocked(side: int) -> bool:
	if profile.id == "el2": return global_enchantment_count("FTDS") > 0
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments:
			if e.card == "FTDS" and e.owner != side: return true
	return false

func stasis_upkeep(enchantment: Dictionary, serial := -1) -> int:
	if profile.id == "el1": return 2
	return int(((turn_serial if serial < 0 else serial) - int(enchantment.born)) / 2) * 2

func damage_targets(card: String, side: int, target := -1) -> Array[int]:
	var rule := ELCatalog.rule(profile, card)
	if rule.get("effect") == "damage": return [target] if not entity(target).is_empty() else []
	var result: Array[int] = []
	if rule.get("effect") != "wave": return result
	var scope: String = rule.get("scope", "enemy")
	if scope == "heroes": return [0, 1]
	for creature: Dictionary in army(0) + army(1):
		if scope == "enemy" and creature.owner == side: continue
		if scope == "ground" and has_flag(creature.id, "Fly"): continue
		if scope == "flying" and not has_flag(creature.id, "Fly"): continue
		result.append(creature.id)
	return result

## Duel books hold the hero's colour; second-game books may also take neutral
## White spells (shipped duel presets G3, U3 and B3 do).
func _book_colour(colour: String, faction: String) -> bool:
	return colour == faction or (profile.id == "el2" and colour == "White")

func card_name(card: String) -> String:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	var key := String(row.get("Name", card))
	var text := profile.text(key)
	# Pale ability pseudo-cards (AOUP, AOUF) ship no name text; their ability
	# text opens with the name.
	if text == key and not str(row.get("AbilityText", "")).is_empty():
		var ability := profile.text(str(row.AbilityText))
		if ability != str(row.AbilityText) and not ability.is_empty(): return ability.get_slice(". ", 0).trim_suffix(".")
	return text

func target_kind(card: String) -> String:
	return String(ELCatalog.rule(profile, card).get("target", "none"))

func is_summon(card: String) -> bool:
	return ELCatalog.rule(profile, card).get("effect") == "summon"

func entity(id: int) -> Dictionary:
	return heroes[id] if id in [0, 1] else creatures.get(id, {})

## Control can change hands; graveyards and some expiries follow the original owner.
func origin(id: int) -> int:
	return int(creatures[id].get("origin", creatures[id].owner)) if creatures.has(id) else -1

## A creature's power and toughness without its own enchantments and temporary
## bonuses; army and global modifiers still count.
func _bare_stats(id: int) -> Vector2i:
	var bare: Dictionary = creatures[id].duplicate()
	bare.enchantments = []
	bare.temporary = []
	return creature_stats(bare)

## The army enchantments covering `c`. They join an army when cast and a creature when it is
## summoned; changing sides neither gains nor loses one. A creature that has never changed sides is
## covered by everything its controller holds; once moved it carries an `auras` list.
func army_auras(c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Unaffected creatures never receive army auras. A creature in the Colourless
	# Plane receives them only after it manifests.
	if c.get("flags", []).has("NoAffect") or in_plane(int(c.id)): return out
	if not c.has("auras"):
		for e: Dictionary in heroes[c.owner].enchantments:
			if ELCatalog.ARMY_AURAS.has(e.card): out.append(e)
		return out
	var ids := {}
	for id: Variant in c.auras: ids[int(id)] = true
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments:
			if ids.has(int(e.id)) and ELCatalog.ARMY_AURAS.has(e.card): out.append(e)
	return out

func _move_army(c: Dictionary, side: int) -> void:
	if not c.has("auras"): c.auras = army_auras(c).map(func(e: Dictionary) -> int: return int(e.id))
	c.owner = side

func targetable(id: int) -> bool:
	return id < 2 or not (has_flag(id, "NoTarget") or in_plane(id))

## The Colourless Plane (second game): a creature in pale aspect.
func in_plane(id: int) -> bool:
	return creatures.has(id) and creatures[id].get("plane", false)

func pale(id: int) -> bool:
	return has_flag(id, "Outerplanar")

## Whether a change of aspect would succeed now: a seal blocks every change,
## Lock Aspect (or `guard`, cleaving) blocks an entry, and an Aspect Ward must
## be affordable.
func can_change_aspect(id: int, enter: bool, guard := false) -> bool:
	if not creatures.has(id): return false
	if bool(creatures[id].get("plane", false)) == enter: return true
	if global_enchantment_count("PLSL") > 0: return false
	if enter and (guard or _enchantment_count(id, "PRBN") > 0): return false
	return available_mana(int(creatures[id].owner)) >= _enchantment_count(int(creatures[id].owner), "PRWR")

## Moves a creature between aspects (see `can_change_aspect`). Aspect Ward
## charges the controller 1 ether and 1 damage per copy, in either direction.
## Leaving with a beacon brings the same race along.
func plane_change(id: int, enter: bool, guard := false) -> bool:
	if not creatures.has(id): return false
	var c: Dictionary = creatures[id]
	if bool(c.get("plane", false)) == enter: return true
	if not can_change_aspect(id, enter, guard): return false
	var warded := _enchantment_count(int(c.owner), "PRWR")
	if warded > 0:
		var payer := int(c.owner)
		heroes[payer].mana -= warded
		_emit({"kind": "ether", "side": payer, "amount": -warded})
		for i in warded: _trigger_damage("PRWR", payer, 1)
		if not creatures.has(id): return false
	if enter:
		c.plane = true
		_unassign(id)
	else: c.erase("plane")
	_emit({"kind": "plane", "target": id, "enter": enter})
	# Army auras cover creatures outside the Colourless Plane only.
	_refresh_stats(c)
	if global_enchantment_count("WRBN") > 0:
		for other: Dictionary in creatures.values(): _refresh_stats(other)
	if not enter and _enchantment_count(id, "PRGD") > 0:
		for other: Dictionary in army(int(c.owner)):
			if other.id != id and in_plane(other.id) and race(other.id) == race(id): plane_change(other.id, false)
	return true

## A combat ability's kill (Destroy, mechos, snake venom) is lethal damage: NoAffect ignores it,
## regeneration saves it, and a second-game Pale creature dissipates. No pain link.
func _ability_lethal(id: int) -> void:
	if creatures.has(id): _damage(id, maxi(1, int(creatures[id].toughness) - int(creatures[id].damage)), false, false, false, false, true)

## State check death: a bright Pale creature dissipates instead of dying.
func _lethal(id: int) -> void:
	if not creatures.has(id): return
	if profile.id == "el2" and pale(id) and not in_plane(id) and creatures[id].toughness > 0 and plane_change(id, true):
		creatures[id].damage = 0
		_emit({"kind": "dissipate", "target": id})
	else: _kill(id)

func find_enchantment(enchantment_id: int) -> int:
	for id: int in [0, 1] + creatures.keys():
		for e: Dictionary in entity(id).enchantments:
			if int(e.id) == enchantment_id: return id
	return -1

## Card-cast enchantments (and snake venom) can be removed; creature-made ones cannot. A stolen
## creature stays while its original owner's army is full. `untargeted`: a spell that names no
## target (Cleanse, Decontamination) also clears a creature screened by a magic screen.
func dispellable(holder: int, e: Dictionary, untargeted := false) -> bool:
	if e.get("fixed", false) or e.card in TRAPS: return false
	if not targetable(holder) and not (untargeted and not in_plane(holder)): return false
	if e.card in ELCatalog.CONTROL and holder >= 2 and army(origin(holder)).size() >= 10: return false
	return true

## Second-game extra prices: cleansing pays 1 per removable enchantment in
## play; annihilation pays 1 per creature it can affect.
func second_surcharge(card: String) -> int:
	if profile.id != "el2": return 0
	var count := 0
	if card == "CLSN":
		for id: int in [0, 1] + creatures.keys():
			for e: Dictionary in entity(id).enchantments:
				if not e.get("fixed", false): count += 1
	elif card == "DECN":
		for id: int in [0, 1] + creatures.keys():
			for e: Dictionary in entity(id).enchantments:
				if not e.get("fixed", false): count += 1
	elif card in ["ANHL", "GRUN"]:
		# Greater unsummoning pays 1 per creature it returns; neither counts a creature in the Colourless
		# Plane.
		for c: Dictionary in creatures.values():
			if not has_flag(c.id, "NoAffect") and not in_plane(int(c.id)): count += 1
	return count

## The price of removing an enchantment (Flicker, Reinforced Pteros): its card's printed cost;
## wardings raise casting costs only.
func enchantment_price(e: Dictionary) -> int:
	return int(e.get("price", int(profile.table("CombatSpells").get(e.card, {}).get("Cost", 999))))

## Enchantments a dispelling spell may choose; `target` is the holder (Purify) or
## the creature sacrificed first (Ether Trade), whose own enchantments are excluded.
func valid_enchantment_targets(card: String, target := -1) -> Array[int]:
	var result: Array[int] = []
	var rule := ELCatalog.rule(profile, card)
	for id: int in [0, 1] + creatures.keys():
		if (rule.get("effect") == "dispel" and target >= 0 and id != target) or (rule.get("effect") == "trade" and id == target): continue
		for e: Dictionary in entity(id).enchantments:
			if dispellable(id, e): result.append(int(e.id))
	return result

func valid_targets(card: String) -> Array[int]:
	var result: Array[int] = []
	for id: int in [0, 1] + creatures.keys():
		if _target_error(card, id).is_empty(): result.append(id)
	return result

func _target_error(card: String, target: int) -> String:
	var rule := ELCatalog.rule(profile, card)
	match rule.get("target"):
		"any":
			if entity(target).is_empty(): return "Select a creature or hero."
		"hero":
			if target not in [0, 1]: return "Select a hero."
		"creature":
			if not creatures.has(target): return "Select a creature."
		"grave":
			if target not in [0, 1]: return "Select a graveyard."
			return ""
		"enchantment":
			if entity(target).is_empty(): return "Select a character with an enchantment."
			if valid_enchantment_targets(card, target).is_empty(): return "This character has no enchantment that can be removed."
			return ""
		"none": return ""
		_: return "Spell is not available yet."
	if in_plane(target) and not (card in ELCatalog.OUTER_SPELLS and not has_flag(target, "NoTarget")): return "This creature is in the Colourless Plane."
	if not targetable(target) and not in_plane(target): return "This creature is protected by a magic screen."
	if rule.get("own", false) and creatures[target].owner != _me(): return "Select one of your creatures."
	if rule.get("pale", false) and not pale(target): return "Select a Pale creature."
	if rule.get("plane") == "in" and not in_plane(target): return "Select a creature in the Colourless Plane."
	if rule.effect == "gift" and army(1 - _me()).size() >= 10: return "Your opponent already controls ten creatures."
	if rule.has("race") and race(target) != rule.race: return "Select a creature of the right kind."
	if rule.get("flying", false) and not has_flag(target, "Fly"): return "Select a flying creature."
	if card == "CHCM":
		if creatures[target].owner == _me(): return "Select an enemy creature."
		if attacks.has(target) or blocks.has(target): return "This creature is in combat."
		if army(_me()).size() >= 10: return "A hero can control at most ten creatures."
	if rule.effect == "trade":
		if creatures[target].owner != _me(): return "Select one of your creatures to sacrifice."
		if valid_enchantment_targets(card, target).is_empty(): return "There is no other enchantment to remove."
	if rule.effect == "unsummon" and cost(creatures[target].card) > int(rule.maximum):
		return "This creature costs too much ether to unsummon."
	if rule.effect == "exchange" and creatures[target].owner != _me():
		return "Select one of your creatures to sacrifice."
	return ""

## Creatures Trade may destroy after sacrificing `sacrifice`.
func swap_targets(card: String, sacrifice: int) -> Array[int]:
	var result: Array[int] = []
	if ELCatalog.rule(profile, card).get("effect") != "swap" or not _target_error(card, sacrifice).is_empty(): return result
	# The original's target check accepts the sacrifice again.
	for id: int in creatures:
		if targetable(id): result.append(id)
	return result

func valid_grave_targets(card: String, side := -1) -> Array[int]:
	var result: Array[int] = []
	if ELCatalog.rule(profile, card).get("effect") == "pale_revival":
		# Either graveyard; entries are encoded as side * GRAVE_SIDE + index.
		for grave_side: int in ([side] if side in [0, 1] else [0, 1]):
			for i in heroes[grave_side].grave.size():
				if profile.table("CombatCreatures").has(heroes[grave_side].grave[i]): result.append(grave_side * GRAVE_SIDE + i)
		return result
	if ELCatalog.rule(profile, card).get("effect") in ["reanimate", "repair"]:
		# Quick fix: a creature card in either hero's graveyard; repair: the caster's own.
		if side in [0, 1] and (side == _me() or ELCatalog.rule(profile, card).effect == "reanimate"):
			for i in heroes[side].grave.size():
				if profile.table("CombatCreatures").has(heroes[side].grave[i]): result.append(i)
		return result
	if ELCatalog.rule(profile, card).get("effect") == "exchange":
		var grave: Array = heroes[_me()].grave
		for i in grave.size():
			if is_summon(grave[i]): result.append(i)
	return result

func cast(hand_index: int, target := -1, grave_index := -1, extra_ether := 0) -> bool:
	if gate == null: return _cast_now(hand_index, target, grave_index, extra_ether)
	var hero: Dictionary = heroes[active_side()]
	var action := {"kind": "cast", "side": active_side(), "hand_index": hand_index, "target": target, "grave": grave_index, "power": extra_ether,
		"card": hero.hand[hand_index] if hand_index >= 0 and hand_index < hero.hand.size() else ""}
	if not gate.gate_check(self, action): return _refused()
	var ok := _cast_now(int(action.hand_index), target, grave_index, extra_ether)
	gate.gate_done(self, action, ok)
	return ok

func _cast_now(hand_index: int, target := -1, grave_index := -1, extra_ether := 0) -> bool:
	error = ""
	if phase == Phase.FINISHED: return _fail("This duel has ended.")
	var side := active_side()
	var hero: Dictionary = heroes[side]
	if hand_index < 0 or hand_index >= hero.hand.size(): return _fail("Select a spell in the active hand.")
	var card: String = hero.hand[hand_index]
	var rule := ELCatalog.rule(profile, card)
	if rule.is_empty(): return _fail("Spell is not available yet: " + card)
	if rule.get("self", false): target = side
	if rule.get("opponent", false): target = 1 - side
	if available_mana(side) < cost(card): return _fail("Not enough ether.")
	if extra_ether < 0 or (extra_ether != 0 and not variable_power(card)): return _fail("Invalid extra ether amount.")
	if extra_ether > maximum_power(card): return _fail("Not enough ether for the chosen spell power.")
	if hero.channels < channel_cost(card): return _fail("This spell requires %d ether channels." % channel_cost(card))
	var channel_invalid := channel_error(card, side)
	if not channel_invalid.is_empty(): return _fail(channel_invalid)
	var use_in := String(profile.table("CombatSpells")[card].get("UseIn", "Both"))
	if (use_in == "Attack" and phase != Phase.ATTACK) or (use_in in ["Defence", "Defense"] and phase != Phase.DEFENCE):
		return _fail("This spell cannot be cast in the current phase.")
	var invalid := _cast_error(side, card, rule, target, grave_index)
	if not invalid.is_empty(): return _fail(invalid)
	var surcharge := 0
	if rule.get("priced", false):
		surcharge = enchantment_price(_enchantment_by_id(find_enchantment(grave_index), grave_index))
		if available_mana(side) < cost(card) + surcharge: return _fail("Not enough ether to remove this enchantment.")
	# Disintegration also pays the target creature's printed cost.
	if rule.get("priced_target", false): surcharge += int(profile.table("CombatSpells")[creatures[target].card].Cost)
	surcharge += second_surcharge(card)
	if surcharge > 0 and available_mana(side) < cost(card) + surcharge: return _fail("This spell needs %d more ether." % surcharge)
	if hero.hand_slots.size() != hero.hand.size(): return _fail("Invalid hand charge state.")
	var slot: int = hero.hand_slots[hand_index]
	if slot >= 0 and hero.spell_uses[slot] == 0: return _fail("This spellbook copy has no charges left.")
	var traps := _sorcery_traps()
	# Specialisations, rolled in this order before payment: a spared charge, a
	# card that stays in hand (only while its charges cover the copies in hand),
	# then a free cast (the base cost; extra ether is still paid).
	if not (slot >= 0 and ELSpecs.roll(self, side, "RSFN") > 0):
		if slot >= 0 and hero.spell_uses[slot] > 0: hero.spell_uses[slot] -= 1
	var stays := false
	if hero.get("spec") == "STHN":
		var copies: int = hero.hand_slots.count(slot) if slot >= 0 else 0
		if slot < 0 or hero.spell_uses[slot] < 0 or copies < int(hero.spell_uses[slot]): stays = ELSpecs.roll(self, side, "STHN") > 0
	var free: bool = ELSpecs.roll(self, side, "MNCH") > 0
	_spend_ether(side, (0 if free else cost(card)) + surcharge)
	if not stays: _take_card(side, hand_index)
	var cast_event := {"kind": "cast", "side": side, "card": card, "target": target, "cost": cost(card) + power_price(card, extra_ether), "power": extra_ether}
	# Both originals' Trade has two separately targeted damage effects, then
	# healing at the second creature's controller. Save the second cue target
	# before synchronous destruction; this does not change the combat rules.
	if profile.id in ["el1", "el2"] and card == "TRAD": cast_event.second = grave_index
	# EL2 Carnivorous@ only queues its second GreenDamage on the
	# opposing hero if the sacrificed creature had positive power. Snapshot
	# before synchronous destruction; this is presentation data, not rules.
	if profile.id == "el2" and card == "CANV" and creatures.has(target):
		cast_event.devour_power = maxi(0, int(creatures[target].power))
	# EL2 Enlightenment@ exits before both original FX registrations
	# when no other cards remain after paying/consuming the cast card.
	# Retain that count before the synchronous discard/redraw changes the hand.
	if profile.id == "el2" and card == "ENLH":
		cast_event.enlightenment_count = hero.hand.size()
	# Both original Broken Reality callbacks (EL1@,
	# EL2@) skip LoseMana/BlackDamage when the selected
	# hero has no ether after spell payment.
	# Capture it before burn_mana sets the target to zero.
	if profile.id in ["el1", "el2"] and card == "BRRL":
		cast_event.broken_reality_ether = int(heroes[target].mana)
	_emit(cast_event)
	_resolve_spell(side, card, rule, target, grave_index, extra_ether, traps, true)
	if scripts != null: scripts.dispatch("CHook_OnVisualPostSpellCast", _post_cast_arguments(side, card, null, target, extra_ether))
	_finish_action()
	return true

## A queued script cast (ExCastSpell / ExCastSpellWithEffects). `args` are the
## script's numbers after the code: the target, then a graveyard index or
## enchantment ID; a variable spell without a target takes X first. An illegal
## cast does nothing. A plain script cast is free, silent and skips caster
## specialisations; `presented` first raises the caster's ether by the cost and
## then pays it like a hand cast (no card leaves the hand). A variable spell's X
## is still charged from the caster's ether (VolcanicEruption adds it first).
func cast_free(side: int, card: String, args: Array, presented: bool) -> bool:
	error = ""
	if phase == Phase.FINISHED: return _fail("This duel has ended.")
	var rule := ELCatalog.rule(profile, card)
	if rule.is_empty():
		_emit({"kind": "script_unsupported", "side": side, "card": card})
		return _fail("Unsupported scripted spell: " + card)
	var target := -1
	var grave_index := -1
	var extra_ether := 0
	var values: Array = args.duplicate()
	if variable_power(card) and target_kind(card) == "none":
		extra_ether = int(values.pop_front()) if not values.is_empty() else 0
	else:
		target = int(values.pop_front()) if not values.is_empty() else -1
		if variable_power(card): extra_ether = int(values.pop_front()) if not values.is_empty() else 0
		else: grave_index = int(values.pop_front()) if not values.is_empty() else -1
	if rule.get("self", false): target = side
	if rule.get("opponent", false): target = 1 - side
	_acting = side
	var invalid := channel_error(card, side)
	if invalid.is_empty(): invalid = _cast_error(side, card, rule, target, grave_index)
	if invalid.is_empty() and (extra_ether < 0 or (variable_power(card) and power_price(card, extra_ether) > available_mana(side))): invalid = "Not enough ether for the chosen spell power."
	if not invalid.is_empty():
		_acting = -1
		return _fail(invalid)
	var traps := _sorcery_traps()
	if presented:
		var surcharge := second_surcharge(card)
		if rule.get("priced", false): surcharge += enchantment_price(_enchantment_by_id(find_enchantment(grave_index), grave_index))
		if rule.get("priced_target", false): surcharge += int(profile.table("CombatSpells")[creatures[target].card].Cost)
		heroes[side].mana += cost(card)
		var free: bool = ELSpecs.roll(self, side, "MNCH") > 0
		_spend_ether(side, (0 if free else cost(card)) + surcharge)
		var shown := {"kind": "cast", "side": side, "card": card, "target": target, "cost": cost(card) + power_price(card, extra_ether), "power": extra_ether, "script": true}
		if profile.id == "el2" and card == "CANV" and creatures.has(target):
			shown.devour_power = maxi(0, int(creatures[target].power))
		if profile.id == "el2" and card == "ENLH":
			shown.enlightenment_count = heroes[side].hand.size()
		if profile.id in ["el1", "el2"] and card == "BRRL":
			shown.broken_reality_ether = int(heroes[target].mana)
		_emit(shown)
	else:
		_emit({"kind": "script_cast", "side": side, "card": card, "target": target, "power": extra_ether})
	_resolve_spell(side, card, rule, target, grave_index, extra_ether, traps, presented)
	_acting = -1
	if scripts != null: scripts.dispatch("CHook_OnVisualPostSpellCast", _post_cast_arguments(side, card, null if presented else 1.0, target, extra_ether))
	_finish_action()
	return true

## PostSpellCast arguments: player, code, scripted flag, then the target list
## (the target, or X for a variable spell without one).
func _post_cast_arguments(side: int, card: String, scripted: Variant, target: int, extra_ether: int) -> Array:
	var result: Array = [float(side), card, scripted]
	if target_kind(card) != "none" and target >= 0: result.append(float(target))
	if variable_power(card): result.append(float(extra_ether))
	return result

## Target and effect legality shared by hand casts and script casts (no hand,
## phase or payment checks). `_me()` must be `side` while this runs.
func _cast_error(side: int, card: String, rule: Dictionary, target: int, grave_index: int) -> String:
	if rule.effect == "summon" and army(side).size() >= 10: return "A hero can control at most ten creatures."
	var invalid := _target_error(card, target)
	if not invalid.is_empty(): return invalid
	if rule.effect == "revive" and heroes[side].grave.is_empty(): return "The graveyard is empty."
	if rule.effect == "exchange" and not valid_grave_targets(card).has(grave_index):
		return "Choose a creature from your graveyard to return to play."
	if rule.effect == "reanimate":
		if army(side).size() >= 10: return "A hero can control at most ten creatures."
		if not valid_grave_targets(card, target).has(grave_index): return "Choose a creature in a graveyard."
		if rule.get("grave_owner_cap", false) and army(target).size() >= 10: return "That graveyard's hero already controls ten creatures."
	if rule.effect == "pale_revival" and not valid_grave_targets(card).has(grave_index): return "Choose a creature in a graveyard."
	if rule.effect == "banish" and not can_change_aspect(target, true): return "This creature cannot enter the Colourless Plane now."
	if rule.effect == "repair" and not valid_grave_targets(card, target).has(grave_index): return "Choose a creature in your graveyard."
	# Trade passes the creature to destroy in place of a graveyard index.
	if rule.effect == "swap" and not swap_targets(card, target).has(grave_index): return "Choose another creature to destroy."
	if rule.effect == "clone" and army(side).size() >= 10: return "A hero can control at most ten creatures."
	# Second-game ban needs the opponent to hold more cards than the caster keeps.
	if rule.effect == "ban" and profile.id == "el2" and heroes[1 - side].hand.size() - (heroes[side].hand.size() - 1) <= 0:
		return "Your opponent must hold more spells than you."
	# Dispelling spells pass the chosen enchantment's ID in place of a graveyard index.
	if rule.effect in ["dispel", "trade"] and not valid_enchantment_targets(card, target).has(grave_index):
		return "Choose an enchantment that can be removed."
	return ""

## Second-game spell-jammer traps in play, in creation order, captured before payment.
func _sorcery_traps() -> Array[Dictionary]:
	var traps: Array[Dictionary] = []
	if profile.id == "el2":
		for owner in 2:
			for e: Dictionary in heroes[owner].enchantments:
				if e.card in ["OST1", "OST2", "OST3"]: traps.append({"owner": owner, "effect": e})
		traps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.effect.id < b.effect.id)
	return traps

## The effect of a resolved spell and its reactions. Caster specialisations
## (twin creatures, the elixir draw) roll only when `specs` is set.
func _resolve_spell(side: int, card: String, rule: Dictionary, target: int, grave_index: int, extra_ether: int, traps: Array[Dictionary], specs: bool) -> void:
	var hero: Dictionary = heroes[side]
	# Second game: data attraction copies in play when the spell is cast react even if the spell
	# removes them. The first game counts the copies left after the spell.
	var attractions := _enchantment_count(side, "TRLB") if profile.id == "el2" else -1
	match rule.effect:
		"summon": _summon(side, card)
		"damage", "wave":
			_spend_ether(side, extra_ether)
			var amount := extra_ether if variable_power(card) else int(rule.amount)
			if amount > 0:
				# EL1 Supernova@: the zero-X early exit
				#  skips its sole RedSuperNova registration.
				# Positive X registers one global effect before any damage.
				if profile.id == "el1" and card == "SNOV":
					_emit({"kind": "supernova_global_cue", "side": side})
				for victim: int in damage_targets(card, side, target):
					# Storm mastery: the caster's creatures may gain +3/+3 instead.
					if card == "LGST" and creatures.has(victim) and creatures[victim].owner == side and ELSpecs.roll(self, side, "RLSS") > 0:
						_mark(victim, "RLSS", 3, 3)
						# Both originals queue three positive Target effects
						# at the RLSS recipient (EL1, EL2).
						if profile.id in ["el1", "el2"]:
							_emit({"kind": "lightning_storm_bless_cue", "target": victim})
						continue
					# Both originals register RedLightning for each unrescued
					# figure before damage (EL1, EL2).
					if profile.id in ["el1", "el2"] and card == "LGST":
						_emit({"kind": "lightning_storm_damage_cue", "target": victim})
					# Both originals queue one Target/RedDamage per opposing
					# creature before damage (EL1@; EL2@).
					# Only EL2 has a separate caster channel-loss site below.
					if profile.id in ["el1", "el2"] and card == "FRST":
						_emit({"kind": "firestorm_victim_cue", "target": victim})
					# Both original Fire Wave callbacks queue Target/RedDamage once
					# per opposing creature before synchronous one-point damage:
					# EL1 -, EL2 -.
					if profile.id in ["el1", "el2"] and card == "FRWA":
						_emit({"kind": "fire_wave_victim_cue", "target": victim})
					# EL1 WindsOfFlame@ and EL2@ both
					# skip these sites at X=0. At positive X each eligible
					# flying creature receives a Fireball Start/Finish and
					# FireballExpl Finish before synchronous damage.
					if profile.id in ["el1", "el2"] and card == "WNFL":
						_emit({"kind": "winds_flame_victim_cue", "target": victim})
					_damage(victim, amount)
				if channel_cost(card) > 0:
					_change_ether(side, 0, -channel_cost(card))
					# One caster-bound LoseMana follows the two-channel deduction,
					# even when the opposing army has no creatures.
					if profile.id == "el2" and card == "FRST":
						_emit({"kind": "firestorm_channel_cue", "side": side, "amount": -channel_cost(card)})
					# EL2 Supernova@ likewise queues one Target/LoseMana
					# after its positive-X single-channel payment.
					# X=0 returns before both original effect registrations.
					if profile.id == "el2" and card == "SNOV":
						_emit({"kind": "supernova_channel_cue", "side": side, "amount": -channel_cost(card)})
		"enchant":
			if variable_power(card):
				# Pay-X enchantments add X power (X may be zero).
				_spend_ether(side, extra_ether)
				var powered := rule.duplicate()
				# Shield of force adds X toughness; the others add X power.
				if rule.get("stat") == "toughness": powered.toughness = extra_ether
				else: powered.power = extra_ether
				_enchant(card, side, target, powered)
			else: _enchant(card, side, target, rule)
		"draw":
			_spend_ether(side, extra_ether)
			# Fetch also costs a channel (ether unchanged).
			if channel_cost(card) > 0: _change_ether(side, 0, -channel_cost(card))
			for i in (extra_ether if variable_power(card) else int(rule.amount)): _draw(target)
		"destroy": _destroy(target)
		"exile": _remove_creature(target, "exile")
		"repair":
			# The creature card returns to hand; the enemy hero takes its printed
			# power in the second game and 1 in the first.
			var repaired: String = heroes[target].grave[grave_index]
			heroes[target].grave.remove_at(grave_index)
			_give_card(side, repaired)
			_emit({"kind": "return_card", "side": side, "card": repaired})
			var hurt := int(profile.table("CombatCreatures")[repaired].Power) if profile.id == "el2" else 1
			if hurt > 0: _damage(1 - side, hurt)
		"rally_all":
			# Untap every own resting creature that is not in combat; sickness stays.
			for c: Dictionary in army(side):
				if c.resting and not attacks.has(c.id) and not blocks.has(c.id) and not (profile.id == "el2" and has_flag(c.id, "NoAffect")): c.resting = false
		"discard_all":
			var wiped := 0
			while not heroes[target].hand.is_empty():
				_emit({"kind": "discard", "side": target, "card": _take_card(target, 0)})
				wiped += 1
			# Mind wipe mastery: 3 damage for each discarded card whose roll succeeds.
			var hits := ELSpecs.roll(self, side, "BMWM", wiped)
			if hits > 0: _damage(target, 3 * hits)
		"reanimate":
			var revived: String = heroes[target].grave[grave_index]
			heroes[target].grave.remove_at(grave_index)
			_summon(side, revived)
			var returned := next_id - 1
			if creatures.has(returned) and creatures[returned].card == revived and not rule.get("plain", false):
				_enchant(card, side, returned, {"power": -1, "toughness": -1})
		"drain_life":
			_spend_ether(side, extra_ether)
			var before := int(heroes[1 - side].health)
			if _damage(1 - side, extra_ether) > 0:
				var gained := mini(extra_ether, before)
				heroes[side].health += gained
				_emit({"kind": "heal", "target": side, "amount": gained})
		"devour":
			var eaten: Dictionary = creatures[target]
			var power := maxi(0, int(eaten.power))
			var toughness := int(eaten.toughness)
			_kill(target)
			heroes[side].health += toughness
			_emit({"kind": "heal", "target": side, "amount": toughness})
			if power > 0: _damage(1 - side, power)
			if profile.id == "el2": _draw(side)
		"half_heal":
			# Second-game healing raises health to half the starting health when below it.
			var half := int(heroes[side].maximum) / 2
			if heroes[side].health < half:
				_emit({"kind": "heal", "target": side, "amount": half - int(heroes[side].health)})
				heroes[side].health = half
		"full_heal":
			# Restores the duel's starting health; the first game also lowers a surplus.
			if profile.id == "el1" or heroes[side].health < int(heroes[side].maximum): heroes[side].health = int(heroes[side].maximum)
			_emit({"kind": "heal", "target": side, "amount": 0})
		"heal":
			_spend_ether(side, extra_ether)
			heroes[side].health += extra_ether
			_emit({"kind": "heal", "target": side, "amount": extra_ether})
		"hunger_all":
			for c: Dictionary in army(1 - side):
				if creatures.has(c.id) and c.power > 0:
					# Both originals register Target/Hunger before each hit:
					# EL1 CurseOfHunger@, EL2@.
					if profile.id in ["el1", "el2"]:
						_emit({"kind": "hunger_victim_cue", "target": int(c.id)})
					_damage(c.id, int(c.power))
		"random_discard":
			for i in int(rule.amount):
				var spells: Array[int] = []
				for index: int in hand_display(target):
					if rule.get("any", false) or profile.table("CombatSpells").get(heroes[target].hand[index], {}).get("Class") != "Creature": spells.append(index)
				if spells.is_empty(): break
				var dropped := _take_card(target, spells[random_index(spells.size())])
				_emit({"kind": "discard", "side": target, "card": dropped})
		"annihilate":
			# Each side's power is totalled before anything dies; then that side's creatures are destroyed
			# and the opposing hero takes the total. A creature in the Colourless Plane is neither counted
			# nor destroyed.
			var totals := [0, 0]
			for c: Dictionary in creatures.values():
				if not has_flag(c.id, "NoAffect") and not in_plane(int(c.id)): totals[c.owner] += maxi(0, int(c.power))
			for victim_side in 2:
				for c: Dictionary in army(victim_side):
					if in_plane(int(c.id)): continue
					# EL1 - and EL2 -
					# register Target/RedAnihilation per non-plane creature
					# before destruction, in each combat side's original order.
					if profile.id in ["el1", "el2"] and not in_plane(int(c.id)):
						_emit({"kind": "annihilation_creature_cue", "target": int(c.id)})
					_destroy(c.id)
				# EL1 - and EL2 -
				# queue the opposite hero's effect only on positive total.
				if profile.id in ["el1", "el2"] and totals[victim_side] > 0:
					_emit({"kind": "annihilation_hero_cue", "target": 1 - victim_side})
				_damage(1 - victim_side, totals[victim_side])
		"mana": _change_ether(side, effect_amount(rule))
		"channels":
			var amount := effect_amount(rule)
			match rule.get("scope", "self"):
				"both":
					for recipient in 2: _change_ether(recipient, 0, amount)
				"enemy", "steal":
					_change_ether(1 - side, 0, -amount)
					if rule.scope == "steal": _change_ether(side, 0, amount)
				_: _change_ether(side, 0, amount)
		"drain_mana":
			var amount := mini(effect_amount(rule), int(heroes[1 - side].mana))
			_change_ether(1 - side, -amount)
			_change_ether(side, amount)
		"burn_mana":
			var amount := int(heroes[target].mana)
			_change_ether(target, -amount)
			# Burn resistance: each ether may be spared.
			amount -= ELSpecs.roll(self, target, "RMBD", amount)
			if amount > 0: _damage(target, amount)
		"revive":
			var revived: String = hero.grave.pop_back()
			# The first game puts it at the front of the hand like a draw, the second at the back.
			_give_card(side, revived, -1, profile.id == "el1")
			_emit({"kind": "return_card", "side": side, "card": revived})
			_damage(1 - side, 1)
		"exchange":
			# Choose and remove the original grave entry before the sacrifice is added.
			var revived: String = hero.grave[grave_index]
			hero.grave.remove_at(grave_index)
			_kill(target)
			_summon(side, revived)
		"rest_enemies":
			for c: Dictionary in army(1 - side):
				# Ice storm taps every non-Wall, restless or not.
				var exempt: bool = race(c.id) == "Wall" if rule.get("scope") == "not_walls" else has_flag(c.id, "Restless")
				# The second game also spares unaffected creatures, and Glade one in the Colourless Plane.
				if profile.id == "el2" and (has_flag(c.id, "NoAffect") or (rule.get("scope") != "not_walls" and in_plane(int(c.id)))): exempt = true
				if not c.resting and not exempt:
					c.resting = true
					# Glade withdraws a declared attacker in the second game; Ice Storm and the first game leave it
					# striking.
					if profile.id == "el2" and card == "GLDT": attacks.erase(c.id)
					_emit({"kind": "rest", "target": c.id})
		"hunger":
			# Hunger mastery: the target cannot regenerate from this.
			if creatures[target].power > 0: _damage(target, int(creatures[target].power), false, ELSpecs.roll(self, side, "UHGW") > 0)
		"dispel":
			var holder := find_enchantment(grave_index)
			_dispel(holder, grave_index)
			# Purification mastery: every other removable enchantment on the holder goes too.
			if card == "PRFY" and holder >= 0 and not entity(holder).is_empty() and ELSpecs.roll(self, side, "BPRC") > 0:
				for e: Dictionary in entity(holder).enchantments.duplicate():
					if not entity(holder).is_empty() and dispellable(holder, e): _dispel(holder, int(e.id))
		"trade":
			# The sacrifice dies first (its death effects apply), then the enchantment goes;
			# Whirling Ashes dispels it, so a weakened holder can die.
			_kill(target)
			var holder := find_enchantment(grave_index)
			if holder >= 0 and rule.get("dispel", false): _dispel(holder, grave_index)
			elif holder >= 0: _remove_enchantment(holder, grave_index)
		"channel":
			# Channel: X damage to the caster, then ether + X (+4 in the first game)
			# set directly, and the opponent heals X.
			if extra_ether > 0: _damage(side, extra_ether)
			var gain := extra_ether + (4 if profile.id == "el1" else 0)
			if gain > 0:
				heroes[side].mana += gain
				_emit({"kind": "ether", "side": side, "amount": gain})
			if extra_ether > 0:
				heroes[1 - side].health += extra_ether
				_emit({"kind": "heal", "target": 1 - side, "amount": extra_ether})
		"cleanse":
			var chosen: Array[int] = []
			for id: int in [0, 1] + creatures.keys():
				for e: Dictionary in entity(id).enchantments:
					if dispellable(id, e, true): chosen.append(int(e.id))
			for enchantment_id: int in chosen:
				var holder := find_enchantment(enchantment_id)
				if holder >= 0 and dispellable(holder, _enchantment_by_id(holder, enchantment_id), true): _dispel(holder, enchantment_id)
		"grave_fire":
			for victim in 2:
				if not heroes[victim].grave.is_empty(): _trigger_damage(card, victim, 2 * heroes[victim].grave.size())
		"unsummon":
			# The card returns to its original owner's hand.
			_give_card(origin(target), creatures[target].card)
			_remove_creature(target, "unsummon")
		"symbiosis":
			var gain := 2 * creatures.size()
			heroes[side].health += gain
			_emit({"kind": "heal", "target": side, "amount": gain})
		"sacrifice_heal":
			# Cannibalism: the caster gains the sacrifice's current toughness.
			var gain := int(creatures[target].toughness)
			# Cannibal mastery spares the sacrifice.
			if ELSpecs.roll(self, side, "RPLO") == 0: _kill(target)
			heroes[side].health += gain
			_emit({"kind": "heal", "target": side, "amount": gain})
		"polymorph":
			# The caster's health becomes the target's toughness (second game: power + toughness).
			var victim: Dictionary = creatures[target]
			var value := int(victim.toughness) + (maxi(0, int(victim.power)) if profile.id == "el2" else 0)
			_kill(target)
			_emit({"kind": "heal", "target": side, "amount": value - int(heroes[side].health)})
			heroes[side].health = value
		"twister":
			# Fatal disease first, then lethal damage; the attacking hero takes the power. The power is read
			# without the creature's own enchantments and temporary bonuses; army and global modifiers still
			# count.
			var power := _bare_stats(target).x
			_mark(target, "TWST", 0, 0, {"fixed": true})
			_destroy(target)
			if power > 0: _damage(attacker, power)
		"fury_of_nature":
			var doomed: Array[int] = []
			for c: Dictionary in army(0) + army(1): doomed.append(int(c.id))
			var attempts := 0
			for id: int in doomed:
				if not creatures.has(id): continue
				# Nature's friend: each creature's controller may spare it.
				if ELSpecs.roll(self, int(creatures[id].owner), "GFNS") > 0: continue
				_destroy(id)
				attempts += 1
			if profile.id == "el2":
				# The second game: the caster's opponent draws one spell per creature destroyed.
				var deaths := 0
				for id: int in doomed:
					if not creatures.has(id): deaths += 1
				for i in deaths: _draw(1 - side)
				# Original - creates one Draw Target cue
				# after those draws, only for a positive actual death count.
				# This transient event does not enter the saved game state.
				_emit({"kind": "fury_result", "deaths": deaths, "target": 1 - side})
			else:
				# EL1 FuryOfNature@ queues its second, hero-bound
				# GreenDamage only for a positive number of attempted hits.
				# Count includes regenerated survivors. The visual callback must
				# use the attacking hero, which can differ from the caster.
				_emit({"kind": "fury_result", "attempts": attempts, "attacker": attacker})
				if attempts > 0: _damage(attacker, attempts)
		"clone": _summon(side, creatures[target].card)
		"pale_blast":
			# The latest enchantment goes if it can; a Pale creature then takes 3.
			var latest := {}
			for e: Dictionary in creatures[target].enchantments: latest = e
			if not latest.is_empty() and dispellable(target, latest): _remove_enchantment(target, int(latest.id))
			if creatures.has(target) and pale(target): _damage(target, 3, false, false, true, true)
		"pale_cleave":
			if pale(target):
				# Destroyed without dissipating (regeneration still applies).
				_plane_guard = true
				_damage(target, maxi(1, int(creatures[target].toughness) - int(creatures[target].damage)), false, false, true, true, true)
				_plane_guard = false
			else:
				var returned: String = creatures[target].card
				if returned.begins_with("OSJ"): returned = "OST" + returned.substr(3)
				_give_card(origin(target), returned)
				_remove_creature(target, "unsummon")
		"ripple":
			for c: Dictionary in creatures.values():
				if in_plane(c.id): _damage(c.id, 3, false, false, true, true)
			_enchant("ORPL", side, side, {"fixed": true})
		"pale_theft":
			for victim in 2:
				var races := {}
				for c: Dictionary in army(victim):
					if pale(c.id): races[race(c.id)] = true
				var lost := mini(races.size(), heroes[victim].hand.size())
				_discard_random(victim, lost)
				for i in lost: _draw(1 - victim)
		"flux":
			# N = the caster's non-Pale creatures, in either aspect; every creature
			# in the plane takes N bypass damage (no death save there).
			var n := 0
			for c: Dictionary in army(side):
				if not pale(c.id): n += 1
			if n > 0:
				for id: int in creatures.keys():
					if in_plane(id): _damage(id, n, false, false, true, true)
		"pale_calamity":
			# Each hero discards one random card per own creature in the plane; nobody draws.
			for victim in 2:
				var count := 0
				for c: Dictionary in army(victim):
					if in_plane(c.id): count += 1
				_discard_random(victim, count)
		"banish":
			if plane_change(target, true): _draw(side)
		"vaporize":
			for c: Dictionary in army(0) + army(1):
				if creatures.has(c.id) and pale(c.id) and not in_plane(c.id): plane_change(c.id, true)
		"pale_revival":
			# Destroyed from the plane (regeneration still applies), then a graveyard
			# creature returns under the caster while the army has room.
			var grave_side := grave_index / GRAVE_SIDE
			var grave_slot := grave_index % GRAVE_SIDE
			var revived: String = heroes[grave_side].grave[grave_slot]
			# The original 1e6 bypass hit; the remaining toughness gives the same result
			# without an inflated damage figure.
			_damage(target, maxi(1, int(creatures[target].toughness) - int(creatures[target].damage)), false, false, true, true, true)
			if army(side).size() < 10:
				if grave_slot >= heroes[grave_side].grave.size() or heroes[grave_side].grave[grave_slot] != revived: grave_slot = heroes[grave_side].grave.rfind(revived)
				if grave_slot >= 0:
					heroes[grave_side].grave.remove_at(grave_slot)
					_summon(side, revived)
		"gift":
			# A permanent change of controller and owner; an undispellable mark
			# that speeds the receiver's ether disturbance (see `gift_turns`).
			var gifted: Dictionary = creatures[target]
			_unassign(target)
			_move_army(gifted, 1 - side)
			gifted.erase("origin")
			# The receiver must wait a turn to act with it.
			if not has_flag(target, "NSS"): gifted.sick = true
			_refresh_armies()
			# The receiver's army enchantments do not cover it (see `army_auras`);
			# a creature that dies on changing sides takes no mark.
			if creatures.has(target): _enchant("GIFT", side, target, {"fixed": true})
		"swap":
			# The sacrifice dies first; the destroyed creature's controller then gains its toughness, even if
			# it survives. Naming the sacrifice twice only sacrifices it; its controller still gains its
			# toughness, read without its own enchantments.
			if grave_index == target:
				var gain := _bare_stats(target).y
				var controller := int(creatures[target].owner)
				_kill(target)
				heroes[controller].health += gain
				_emit({"kind": "heal", "target": controller, "amount": gain})
			else:
				_kill(target)
			if grave_index != target and creatures.has(grave_index):
				var gain := int(creatures[grave_index].toughness)
				var controller := int(creatures[grave_index].owner)
				_destroy(grave_index)
				heroes[controller].health += gain
				_emit({"kind": "heal", "target": controller, "amount": gain})
		"bounce_all":
			# Every affected creature returns to its original owner's hand without dying.
			for victim_side in 2:
				for c: Dictionary in army(victim_side):
					if not creatures.has(c.id): continue
					# Unsummoning mastery: the controller may keep each creature in play.
					if ELSpecs.roll(self, victim_side, "UGUS") > 0 or has_flag(c.id, "NoAffect") or in_plane(int(c.id)): continue
					_give_card(origin(c.id), c.card)
					_remove_creature(c.id, "unsummon")
		"amnesia":
			for victim in 2: _discard_random(victim, heroes[victim].hand.size())
			if profile.id == "el2": _draw(side)
		"mind_blast":
			var per_card := 3 if profile.id == "el2" else 2
			for victim in 2:
				var hurt: int = per_card * (heroes[victim].hand.size() - 5)
				# Mind shield: each point may be spared.
				if hurt > 0: hurt -= ELSpecs.roll(self, victim, "UMBD", hurt)
				if hurt > 0:
					# Original EL1 - and EL2 -:
					# after Mind Shield, queue a BlueMindBlast Target at each
					# positively damaged hero before that hero's damage.
					# A silent script cast does not present the original FX.
					if profile.id in ["el1", "el2"] and specs:
						_emit({"kind": "mind_blast_cue", "target": victim})
					_damage(victim, hurt)
		"hunger_both":
			for victim_side in 2:
				for c: Dictionary in army(victim_side):
					if creatures.has(c.id) and c.power > 0:
						# EL1 RavagingHunger@ and EL2@
						# register a Target cue before each eligible figure's
						# damage, in side then creature order.
						if profile.id in ["el1", "el2"]:
							_emit({"kind": "hunger_victim_cue", "target": int(c.id)})
						_damage(c.id, int(c.power))
		"redraw":
			for victim: int in ([0, 1] if rule.get("scope") == "both" else [side]):
				var count: int = heroes[victim].hand.size()
				_discard_random(victim, count)
				if not rule.get("retry", true):
					for i in count: _draw(victim)
					continue
				# Rejected classes do not count; 31 failed draws in a row give up.
				var failures := 0
				while heroes[victim].hand.size() < count and failures < 31:
					if _draw(victim, String(rule.get("reject", ""))): failures = 0
					else: failures += 1
		"ban":
			if profile.id == "el2": _discard_random(1 - side, heroes[1 - side].hand.size() - heroes[side].hand.size())
			else:
				for victim in 2: _discard_random(victim, 2)
		"discard_creatures":
			# From the front of the hand.
			var chosen: Array[int] = []
			for i: int in hand_display(target):
				if profile.table("CombatCreatures").has(heroes[target].hand[i]) and chosen.size() < int(rule.amount): chosen.append(i)
			var discarded: Array = chosen.map(func(i: int) -> String: return heroes[target].hand[i])
			chosen.sort()
			chosen.reverse()
			for i: int in chosen: _take_card(target, i)
			for gone: String in discarded: _emit({"kind": "discard", "side": target, "card": gone})
	if rule.effect == "summon":
		# A successful creature spell triggers each copy, regardless of its caster.
		# Grave returns and exchanges summon creatures without casting their spells.
		for recipient in 2:
			for e: Dictionary in heroes[recipient].enchantments:
				if e.card == "MNTX":
					_change_ether(recipient, 2)
					# EL1 Mana Vortex registers GainMana
					# its enchanted hero for every successful creature spell.
					if profile.id == "el1": _emit({"kind": "mana_vortex_cue", "side": recipient})
	elif profile.table("CombatSpells")[card].get("Class") != "Creature":
		# Data attraction: each earlier copy draws a spell, then hurts its holder.
		if attractions < 0: attractions = _enchantment_count(side, "TRLB") - (1 if card == "TRLB" else 0)
		for copy in attractions:
			_draw(side)
			_trigger_damage("TRLB", side, 3)
		if profile.table("CombatSpells")[card].get("Class") == "Sorcery" and not traps.is_empty(): _spell_traps(side, card, extra_ether, traps)
	_settle_illusion_health()
	if not specs: return
	# Velos and halo specialisations summon a second creature; elixir draws a card.
	if rule.effect == "summon":
		var kind := str(profile.table("CombatCreatures").get(card, {}).get("Race", ""))
		if (kind == "Velos" and ELSpecs.roll(self, side, "BVLD") > 0) or (kind == "Halo" and ELSpecs.roll(self, side, "GHLD") > 0):
			if army(side).size() < 10: _summon(side, card)
	if ELSpecs.roll(self, side, "CEXC") > 0: _draw(side)

func army(side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for creature: Dictionary in creatures.values():
		if creature.owner == side: result.append(creature)
	return result

func ready(id: int) -> bool:
	return creatures.has(id) and not creatures[id].resting and not creatures[id].sick

func has_flag(id: int, flag: String) -> bool:
	return creatures.has(id) and (creatures[id].flags.has(flag) or creatures[id].get("granted", []).has(flag))

## The hornet mastery's roll; other creatures and heroes draw nothing.
func _hornet(id: int) -> bool:
	return race(id) == "Hornet" and ELSpecs.roll(self, int(creatures[id].owner), "GHRI") > 0

func race(id: int) -> String:
	return str(profile.table("CombatCreatures").get(creatures[id].card, {}).get("Race", "")) if creatures.has(id) else ""

## Same-race attack partner for a guard: any declared attacker of that race.
func _team_partner(id: int, guards_count := true) -> bool:
	for other: int in attacks:
		if other != id and creatures.has(other) and race(other) == race(id) and (guards_count or not has_flag(other, "TeamAttack")): return true
	return false

func attack_cost(id: int) -> int:
	return global_enchantment_count("LSDS") if creatures.has(id) else 0

## Rest alone does not withdraw a declared attacker. Effects that cancel an
## attack remove its assignment explicitly.
func can_attack(id: int, declared := false) -> bool:
	return phase == Phase.ATTACK and (ready(id) or (declared and creatures.has(id) and not creatures[id].sick)) and creatures[id].owner == attacker and not has_flag(id, "NoAttack") and not in_plane(id) \
		and global_enchantment_count("FOGG") + global_enchantment_count("WLDT") + global_enchantment_count("EWLD") == 0 and not _forest_holds(id, 1 - attacker)

## Dense, Dark and Ancient Forest: the highest power an opposing creature
## may have and still be kept from attacking.
func forest_limit(card: String) -> int:
	match card:
		"DNFR": return 1
		"DRFR": return 3 if profile.id == "el2" else 2
		"ANFR": return 5 if profile.id == "el2" else 3
	return -1

## True while a forest on hero `side` keeps creature `id` from attacking.
func _forest_holds(id: int, side: int) -> bool:
	if creatures[id].owner == side: return false
	for card: String in ["DNFR", "DRFR", "ANFR"]:
		if creatures[id].power <= forest_limit(card) and _enchantment_count(side, card) > 0: return true
	return false

func toggle_attack(id: int) -> bool:
	if gate == null: return _toggle_attack_now(id)
	var action := {"kind": "retreat" if attacks.has(id) else "attack", "side": attacker, "id": id}
	if not gate.gate_check(self, action): return _refused()
	var ok := _toggle_attack_now(id)
	gate.gate_done(self, action, ok)
	return ok

func _toggle_attack_now(id: int) -> bool:
	error = ""
	if not can_attack(id): return _fail("This creature cannot attack now.")
	if attacks.has(id):
		if has_flag(id, "Berserk"): return _fail("An aggressive creature must attack when able.")
		attacks.erase(id)
		for guard: int in attacks:
			if has_flag(guard, "TeamAttack") and not _team_partner(guard, false):
				attacks.append(id)
				return _fail("Recall the guard first; it needs an attacking creature of its race.")
	else:
		if has_flag(id, "TeamAttack") and not _team_partner(id): return _fail("A guard can attack only together with a creature of its race.")
		var tax := attack_cost(id)
		if tax > heroes[attacker].mana: return _fail("Not enough ether to send this creature into attack.")
		_spend_ether(attacker, tax)
		# A positive attack-assignment tax queues LoseMana at the declared
		# attacker after the ether is spent (EL1 -, Target =
		# the creature's figure; EL2 -).
		if profile.id in ["el1", "el2"] and tax > 0:
			_emit({"kind": "attack_tax_effect", "side": attacker, "target": id, "amount": tax})
		attacks.append(id)
	_check_winner()
	changed.emit()
	return true

func available_mana(side: int) -> int:
	return maxi(0, int(heroes[side].mana))

func assign_block(blocker: int, target: int) -> bool:
	if gate == null: return _assign_block_now(blocker, target)
	var action := {"kind": "block", "side": 1 - attacker, "id": blocker, "target": target}
	if not gate.gate_check(self, action): return _refused()
	var ok := _assign_block_now(blocker, target)
	gate.gate_done(self, action, ok)
	return ok

## Why `blocker` cannot block `target` now, or "" when it can.
func block_problem(blocker: int, target: int) -> String:
	if phase != Phase.DEFENCE or not creatures.has(blocker) or not ready(blocker) or creatures[blocker].owner != 1 - attacker or in_plane(blocker):
		return "Select a ready defending creature."
	if not attacks.has(target) or not creatures.has(target): return "Select an attacking creature to block."
	if has_flag(target, "Fly") and not has_flag(blocker, "Fly"): return "A ground creature cannot block a flying creature."
	if has_flag(target, "UB"): return "This creature cannot be blocked."
	if (creatures[target].card in ELCatalog.WALL_BLOCKED or has_flag(target, "Elusive")) and race(blocker) != "Wall": return "Only bodyguards can block this creature."
	if race(target) == "Beholder" and race(blocker) == "Wall" and creatures.values().any(func(c: Dictionary) -> bool: return c.card == "BHMO"):
		return "Walls cannot block beholders while a beholder mother is in play."
	return ""

func _assign_block_now(blocker: int, target: int) -> bool:
	error = ""
	var problem := block_problem(blocker, target)
	if not problem.is_empty(): return _fail(problem)
	if blocks.get(blocker, -1) == target:
		blocks.erase(blocker)
	else:
		# Reinsertion records the player's chosen blocker order.
		blocks.erase(blocker)
		blocks[blocker] = target
	changed.emit()
	return true

func abilities(id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if id in [0, 1]:
		for e: Dictionary in heroes[id].enchantments:
			if not ELCatalog.HERO_ABILITIES.has(e.card): continue
			var ability: Dictionary = ELCatalog.HERO_ABILITIES[e.card].duplicate()
			if profile.id == "el2": ability.merge(ELCatalog.SECOND_HERO_ABILITIES.get(e.card, {}), true)
			ability.effect = ability.key
			ability.key += ":" + str(e.id)
			ability.name = card_name(e.card)
			ability.enchantment = e.id
			ability.used = e.get("used", false)
			result.append(ability)
		for index in heroes[id].get("artifacts", []).size():
			var item: Dictionary = heroes[id].artifacts[index]
			var rule := artifact_rule(item)
			result.append({"key": "artifact:%d" % index, "effect": "artifact", "artifact": index, "card": item.spell,
				"name": artifact_title(item), "target": rule.target, "cost": 0, "charges": int(item.charges)})
		return result
	if not creatures.has(id): return result
	if not ELCatalog.first_ability(profile, creatures[id].card).is_empty():
		var ability: Dictionary = ELCatalog.first_ability(profile, creatures[id].card)
		ability.name = ability_name(creatures[id].card)
		if ability.key == "tap_walls": ability.cost = _resting_walls(1 - int(creatures[id].owner)).size()
		if ability.key in ["rouse", "phantasm"]: ability.used = creatures[id].get("ability_used", {}).get(ability.key, false)
		result.append(ability)
	if profile.id == "el2" and pale(id): result.append_array(_pale_abilities(id))
	# Spores need neither a ready nor a settled fingus.
	if creatures[id].card == "SPFG": result.append({"key": "spores", "name": "Burning spores", "target": "any", "cost": 0, "ready": false})
	if creatures[id].card == "CAFG": result.append({"key": "spores", "name": "Stinging spores", "target": "any", "cost": 0, "ready": false})
	if creatures[id].card == "RFPT": result.append({"key": "disenchant", "name": "Piercing gaze", "target": "enchantment", "cost": -1})
	if creatures[id].card == "WLIL": result.append({"key": "illusion", "name": "Shadows of the dead", "target": "none", "cost": 1, "ready": false, "used": creatures[id].get("ability_used", {}).get("illusion", false)})
	if enfeebled(id): result.append({"key": "wake", "name": "Break enfeeblement", "target": "none", "cost": 3, "ready": false})
	if _enchantment_count(id, "WNPZ") > 0:
		result.append({"key": "unparalyze", "name": "Break paralysis", "target": "none", "cost": 4, "health_cost": 4, "ready": false, "resting": true})
	if _enchantment_count(id, "IMMB") > 0:
		var price := 2 if profile.id == "el1" else 3
		result.append({"key": "awaken", "name": "Awaken", "target": "none", "cost": price, "health_cost": price, "ready": false, "resting": true})
	return result

## Pale abilities: dissipation, the race's manifestation and the card's own
## rest ability. Rest abilities need a ready creature, unused this turn, and tap it.
func _pale_abilities(id: int) -> Array[Dictionary]:
	var c: Dictionary = creatures[id]
	var used: Dictionary = c.get("ability_used", {})
	var result: Array[Dictionary] = [{"key": "dissipate", "name": card_name("AOUP"), "target": "none", "cost": 0, "pale": true, "rest": true, "ready": false, "used": used.get("dissipate", false)}]
	var manifest: Dictionary = ELCatalog.PALE_RACE_ABILITIES.get(race(id), {})
	if not manifest.is_empty():
		result.append({"key": manifest.key, "name": card_name(manifest.text), "target": manifest.target, "cost": 0, "pale": true, "ready": false})
	if race(id) == "OutSpellJammer":
		result.append({"key": "courtesy", "name": card_name("AOLS"), "target": "none", "cost": 1, "pale": true, "ready": false})
	if ELCatalog.PALE_ABILITIES.has(c.card):
		var own: Dictionary = ELCatalog.PALE_ABILITIES[c.card].duplicate()
		own.merge({"name": ability_name(c.card), "pale": true, "rest": true, "ready": false, "used": used.get(own.key, false)}, true)
		result.append(own)
	return result

func _pale_error(id: int, d: Dictionary) -> String:
	var c: Dictionary = creatures[id]
	var side := int(c.owner)
	var sealed := global_enchantment_count("PLSL") > 0
	var busy: bool = c.resting or c.sick or attacks.has(id) or blocks.has(id)
	if d.get("rest", false) and (busy or d.get("used", false)): return "This creature must be ready and unused this turn."
	if available_mana(side) < int(d.cost): return "Not enough ether."
	match d.key:
		"dissipate":
			if in_plane(id): return "This creature is already in the Colourless Plane."
			if sealed: return "A planar seal blocks every change of aspect."
			if _enchantment_count(id, "PRBN") > 0: return "Lock Aspect keeps this creature in the Ether."
		"sinister", "fiendish", "cryptic", "mystic":
			# Manifesting leaves the plane.
			if not in_plane(id): return "This creature is not in the Colourless Plane."
			if d.key == "fiendish" and heroes[side].channels < 1: return "This needs an ether channel."
			if d.key == "fiendish" and sealed: return "A planar seal blocks every change of aspect."
			if d.key == "cryptic" and heroes[side].hand.is_empty(): return "This needs a card in hand."
		"cruel":
			if in_plane(id) and sealed: return "A planar seal blocks every change of aspect."
		"courtesy":
			if busy: return "This creature must be ready."
		"channel_ether":
			if heroes[side].channels < 1: return "This needs an ether channel."
		"ether_plea":
			if int(heroes[1 - side].mana) <= 0: return "Your opponent has no ether."
	return ""

func _pale_ability(id: int, d: Dictionary, target: int, choice: int) -> bool:
	var invalid := _pale_error(id, d)
	if not invalid.is_empty(): return _fail(invalid)
	var c: Dictionary = creatures[id]
	var side := int(c.owner)
	var price := int(d.cost)
	var chosen := {}
	match d.key:
		"sinister":
			if target not in [0, 1] or choice < 0 or choice >= heroes[target].grave.size(): return _fail("Choose a card in a graveyard.")
		"cruel":
			if not creatures.has(target) or target == id or creatures[target].owner != side or has_flag(target, "NoTarget"): return _fail("Select another of your creatures.")
		"mystic", "absorb", "weave", "transpose":
			chosen = _enchantment_by_id(target, choice)
			if chosen.is_empty(): return _fail("Select an enchantment.")
			if d.key == "mystic" and int(chosen.owner) != side: return _fail("Choose an enchantment cast by your hero.")
			var printed := int(profile.table("CombatSpells").get(chosen.card, {}).get("Cost", 0))
			if d.key == "weave":
				# Weaving copies without dispelling, so it also reaches pale holders.
				if chosen.get("fixed", false): return _fail("This enchantment has no caster to copy.")
				price = printed + 2
			elif not dispellable(target, chosen): return _fail("This enchantment cannot be removed.")
			if d.key == "transpose": price = printed + 1
			if available_mana(side) < price: return _fail("Not enough ether.")
		"ether_plea":
			if entity(target).is_empty() or not targetable(target): return _fail("Select a creature or hero.")
		"pale_devour":
			if not creatures.has(target) or target == id or not targetable(target): return _fail("Select a creature in the Ether.")
			var prey: Dictionary = creatures[target]
			var weaker: bool = prey.power < c.power if d.measure == "power" else (prey.toughness < c.toughness if d.measure == "toughness" else prey.power < c.power and prey.toughness < c.toughness)
			if not weaker: return _fail("This creature is too strong to devour.")
	if d.get("rest", false):
		if not c.has("ability_used"): c.ability_used = {}
		c.ability_used[d.key] = true
		c.resting = true
	_spend_ether(side, price)
	_emit({"kind": "ability", "source": id, "side": side, "ability": d.key, "name": d.name, "target": target})
	match d.key:
		"dissipate":
			plane_change(id, true)
			if creatures.has(id) and c.damage >= c.toughness: _kill(id)
		"sinister":
			# The graveyard card is consumed even when a seal keeps the samurai pale.
			plane_change(id, false)
			heroes[target].grave.remove_at(choice)
		"cruel":
			_kill(target)
			plane_change(id, false)
		"fiendish":
			plane_change(id, false)
			_change_ether(side, 0, -1)
		"mystic":
			_remove_enchantment(target, choice)
			plane_change(id, false)
		"cryptic":
			plane_change(id, false)
			_discard_random(side, 1)
		"courtesy":
			_kill(id)
			_draw(side)
		"channel_ether": _change_ether(side, 3, -1)
		"ether_plea":
			var drained := int(heroes[1 - side].mana)
			_change_ether(1 - side, -drained)
			_damage(target, drained)
		"pale_heal":
			var gain := army(side).size()
			heroes[side].health += gain
			_emit({"kind": "heal", "target": side, "amount": gain})
		"absorb":
			_remove_enchantment(target, choice)
			_change_ether(side, int(profile.table("CombatSpells")[chosen.card].Cost))
		"weave": _give_card(side, chosen.card)
		"transpose":
			_remove_enchantment(target, choice)
			_give_card(side, chosen.card)
		"pale_devour":
			var prey: Dictionary = creatures[target]
			var remaining := int(prey.toughness) - int(prey.damage)
			var prey_power := int(prey.power)
			_damage(target, maxi(1, remaining), false, false, true, true, true)
			if not creatures.has(target) and creatures.has(id):
				match c.card:
					"OUD1", "OUD2":
						_mark(id, c.card, 1, 1, {"fixed": true})
						# EL2: attaching the growth plays
						# PosAttack, PosDefence and PosRune at the Devourer.
						_emit({"kind": "devour_growth", "target": id})
						var gain := maxi(0, remaining) if c.card == "OUD1" else maxi(0, prey_power)
						if gain > 0:
							heroes[side].health += gain
							_emit({"kind": "heal", "target": side, "amount": gain})
					"OUD3": _change_ether(side, 0, 1)
	_finish_action()
	return true

## First-game abilities that tap their creature require it to be out of combat.
func _in_combat(id: int) -> bool:
	return not ELCatalog.first_ability(profile, creatures[id].card).is_empty() and (attacks.has(id) or blocks.has(id))

func ability_name(card: String) -> String:
	var text := profile.text(str(profile.table("CombatSpells").get(card, {}).get("AbilityText", "")))
	return text.get_slice(". ", 0).trim_suffix(".") if not text.is_empty() else card_name(card)

## Opponent's untapped Wall-race creatures, the targets and price of the swarm's gaze.
func _resting_walls(side: int) -> Array[int]:
	var result: Array[int] = []
	for c: Dictionary in army(side):
		if not c.resting and race(c.id) == "Wall": result.append(c.id)
	return result

## Graveyard entries an ability may choose on `side`'s graveyard.
func grave_ability_targets(id: int, key: String, side: int) -> Array[int]:
	var result: Array[int] = []
	if id in [0, 1] and side == id and (key.get_slice(":", 0) in ["rebirth", "second_birth", "repair"] or (key.begins_with("artifact:") and heroes[id].artifacts[int(key.get_slice(":", 1))].spell == "RDRS")):
		# Hero graveyard abilities choose any creature card in the own graveyard.
		for index in heroes[side].grave.size():
			if profile.table("CombatCreatures").has(heroes[side].grave[index]): result.append(index)
		return result
	if not creatures.has(id) or side not in [0, 1]: return result
	var owner: int = creatures[id].owner
	var grave: Array = heroes[side].grave
	for index in grave.size():
		var card: String = grave[index]
		match key:
			"gnaw", "sinister": result.append(index)
			"recall_lamia":
				if side == owner and str(profile.table("CombatCreatures").get(card, {}).get("Race", "")) == "Lamia": result.append(index)
			"recall_spirit":
				if side == owner and card == "WRSP": result.append(index)
			"recall_rat":
				if side == owner and str(profile.table("CombatCreatures").get(card, {}).get("Race", "")) == "Rat": result.append(index)
			"necromancy":
				if profile.table("CombatCreatures").has(card) and int(profile.table("CombatSpells")[card].Cost) <= int(ELCatalog.FIRST_ABILITIES[creatures[id].card].maximum): result.append(index)
	return result

func can_use_ability(id: int, key: String) -> bool:
	var c := entity(id)
	if phase == Phase.FINISHED or c.is_empty() or int(c.get("owner", id)) != active_side(): return false
	if id >= 2 and _enchantment_count(id, "IRRT") + _enchantment_count(id, "MDNS") + _enchantment_count(id, "RDIS") > 0: return false
	if id < 2 and key.begins_with("artifact:"): return artifact_error(id, int(key.get_slice(":", 1))).is_empty()
	for ability: Dictionary in abilities(id):
		if ability.key != key: continue
		if id >= 2 and in_plane(id) and not ability.get("pale", false): return false
		if ability.get("pale", false): return _pale_error(id, ability).is_empty()
		if ability.get("used", false) or available_mana(active_side()) < maxi(int(ability.get("minimum", 0)), int(ability.cost)): return false
		if id >= 2 and ability.get("ready", true) and not ready(id): return false
		if id >= 2 and ability.get("ready", true) and _in_combat(id): return false
		if ability.get("resting", false) and not c.resting: return false
		if ability.get("tapped", false) and (not c.resting or c.sick): return false
		if ability.get("phase") == "attack" and phase != Phase.ATTACK: return false
		return true
	return false

## `enchantment_id` is the chosen enchantment, graveyard index or, for Combine,
## the creature receiving the sacrifice. `amount` is the X of pay-X abilities.
func use_ability(id: int, ability: String, target := -1, enchantment_id := -1, amount := -1) -> bool:
	if gate == null: return _use_ability_hooked(id, ability, target, enchantment_id, amount)
	var action := {"kind": "ability", "side": int(entity(id).get("owner", id)) if not entity(id).is_empty() else -1, "id": id, "ability": ability,
		"target": target, "enchantment": enchantment_id, "amount": amount}
	if not gate.gate_check(self, action): return _refused()
	var ok := _use_ability_hooked(id, ability, target, enchantment_id, amount)
	gate.gate_done(self, action, ok)
	return ok

func _use_ability_hooked(id: int, ability: String, target := -1, enchantment_id := -1, amount := -1) -> bool:
	# A creature's ability index (0 = its first) for the script hook.
	var index := -1
	if scripts != null and creatures.has(id):
		var listed := abilities(id)
		for i in listed.size():
			if listed[i].key == ability: index = i
	var side := int(entity(id).get("owner", id)) if not entity(id).is_empty() else -1
	if not _use_ability(id, ability, target, enchantment_id, amount): return false
	if index >= 0:
		var arguments: Array = [float(side), float(id), float(index)]
		if target >= 0: arguments.append(float(target))
		scripts.dispatch("CHook_OnVisualCreatureUseAbility", arguments)
		_drain_scripts()
		changed.emit()
	return true

func _use_ability(id: int, ability: String, target := -1, enchantment_id := -1, amount := -1) -> bool:
	error = ""
	var c := entity(id)
	if phase == Phase.FINISHED or c.is_empty() or int(c.get("owner", id)) != active_side(): return _fail("Select one of your characters.")
	var side := int(c.get("owner", id))
	if id >= 2 and _enchantment_count(id, "IRRT") + _enchantment_count(id, "MDNS") + _enchantment_count(id, "RDIS") > 0: return _fail("An enchantment prevents this creature from using abilities.")
	if id < 2 and ability.begins_with("artifact:"): return _use_artifact_now(id, int(ability.get_slice(":", 1)), target, enchantment_id)
	var definition := {}
	for item: Dictionary in abilities(id):
		if item.key == ability: definition = item
	if definition.is_empty(): return _fail("This character does not have that ability.")
	if id >= 2 and in_plane(id) and not definition.get("pale", false): return _fail("This ability cannot be used in the Colourless Plane.")
	if definition.get("pale", false): return _pale_ability(id, definition, target, enchantment_id)
	if definition.get("used", false): return _fail("This ability has already been used this turn.")
	if definition.get("ready", true) and id >= 2 and not ready(id): return _fail("This creature must be ready to use its ability.")
	if definition.get("ready", true) and id >= 2 and _in_combat(id): return _fail("This creature is in combat.")
	if definition.get("resting", false) and not c.resting: return _fail("This creature is already awake.")
	if definition.get("tapped", false) and (not c.resting or c.sick): return _fail("This creature must be resting to use its ability.")
	if definition.get("phase") == "attack" and phase != Phase.ATTACK: return _fail("This ability can be used only while attacking.")
	if id >= 2 and not ELCatalog.first_ability(profile, c.card).is_empty(): return _first_ability(id, definition, target, enchantment_id, amount)
	if id < 2 and definition.has("enchantment"):
		if available_mana(side) < int(definition.cost): return _fail("This ability costs %d ether." % definition.cost)
		if definition.target == "any" and entity(target).is_empty(): return _fail("Select a creature or hero.")
		# Only Ether recycling may name a creature in the Colourless Plane.
		if target >= 2 and creatures.has(target) and in_plane(target) and definition.effect != "recycle": return _fail("This creature is in the Colourless Plane.")
		var sacrificed := Vector2i.ZERO
		if definition.effect == "combine":
			if not creatures.has(target) or creatures[target].owner != side or not targetable(target): return _fail("Select one of your creatures to sacrifice.")
			# Naming the sacrifice twice only sacrifices it.
			if not creatures.has(enchantment_id) or not targetable(enchantment_id): return _fail("Select another creature to receive its strength.")
			sacrificed = Vector2i(creatures[target].power, creatures[target].toughness)
		if definition.effect == "burnout":
			if not creatures.has(target) or creatures[target].owner != side or not targetable(target): return _fail("Select one of your creatures to sacrifice.")
			if enchantment_id == target or entity(enchantment_id).is_empty() or not targetable(enchantment_id): return _fail("Select another creature or a hero to burn.")
			sacrificed = Vector2i(maxi(0, int(creatures[target].power)), 0)
		if definition.effect == "recycle":
			if not in_plane(target) or has_flag(target, "NoTarget"): return _fail("Choose a creature in the Colourless Plane.")
			if not creatures.has(enchantment_id) or in_plane(enchantment_id) or not targetable(enchantment_id): return _fail("Then choose a creature in the Ether.")
			if global_enchantment_count("PLSL") > 0: return _fail("A planar seal blocks every change of aspect.")
		if definition.effect in ["spirit_lock", "sacrifice"] and (not creatures.has(target) or creatures[target].owner != side or not targetable(target)):
			return _fail("Select one of your creatures to sacrifice.")
		if definition.effect == "energize":
			if not creatures.has(target) or not creatures[target].resting: return _fail("Select a resting creature.")
			if attacks.has(target) or blocks.has(target): return _fail("This creature is assigned to combat.")
		var price := 0 if definition.get("unpaid", false) else int(definition.cost)
		var revived := ""
		if definition.effect == "repair" and (target != side or not grave_ability_targets(id, definition.effect, side).has(enchantment_id)):
			return _fail("Choose a creature in your graveyard.")
		if definition.effect in ["rebirth", "second_birth"]:
			if army(side).size() >= 10: return _fail("A hero can control at most ten creatures.")
			if target != side or enchantment_id < 0 or enchantment_id >= heroes[side].grave.size() or not profile.table("CombatCreatures").has(heroes[side].grave[enchantment_id]):
				return _fail("Choose a creature in your graveyard.")
			revived = heroes[side].grave[enchantment_id]
			# Second birth pays the printed cost, without summoner discounts.
			if definition.effect == "second_birth": price = int(profile.table("CombatSpells")[revived].Cost)
			if available_mana(side) < price: return _fail("Not enough ether.")
		for e: Dictionary in c.enchantments:
			if e.id == definition.enchantment: e.used = true
		if definition.effect == "rebirth": _damage(side, 2)
		_spend_ether(side, price)
		var ability_event := {"kind": "ability", "source": id, "side": side, "ability": ability, "name": definition.name, "target": target}
		# Burnout has two targets: `target` is the sacrifice, while the
		# Fireball lands on `enchantment_id`. Keep the original two-choice
		# contract and identify the impact figure for EL2 presentation.
		if profile.id == "el2" and definition.effect == "burnout": ability_event.hit_target = enchantment_id
		# Outer Exchange's stream runs from the first choice to the second.
		if profile.id == "el2" and definition.effect == "recycle": ability_event.hit_target = enchantment_id
		# First game: a sacrifice spared by mastery shows no RedDamage either,
		# so the roll is taken before the event (nothing in between rolls).
		var spared: bool = definition.effect == "burnout" and ELSpecs.roll(self, side, "RBNO") != 0
		if profile.id == "el1" and definition.effect == "burnout":
			ability_event.hit_target = enchantment_id
			ability_event.spared = spared
		_emit(ability_event)
		match definition.effect:
			"heal":
				c.health += int(definition.amount)
				_emit({"kind": "heal", "target": id, "amount": int(definition.amount)})
			"fireball": _damage(target, int(definition.amount))
			"stone_rain":
				for victim: Dictionary in army(1 - side): _damage(victim.id, int(definition.amount))
			"energize": creatures[target].resting = false
			"burnout":
				# The sacrifice's power burns the chosen hero or creature; mastery spares it.
				if not spared: _kill(target)
				if sacrificed.x > 0: _damage(enchantment_id, sacrificed.x)
			"recycle":
				# Plane exchange: one creature manifests, the other dissipates.
				plane_change(target, false)
				plane_change(enchantment_id, true)
			"sacrifice":
				# First game: ether + power + toughness - 1 in one direct change (no
				# spending, so no mana thorns). Second game: the owner draws two instead.
				var value := int(creatures[target].power) + int(creatures[target].toughness)
				_kill(target)
				if profile.id == "el2":
					for i in 2: _draw(side)
				elif value - 1 != 0:
					var before := int(heroes[side].mana)
					heroes[side].mana = maxi(0, before + value - 1)
					_emit({"kind": "ether", "side": side, "amount": int(heroes[side].mana) - before})
				# Original EL1 SACR – registers a second,
				# hero-bound GainMana AFTER its direct ether settlement.
				# The first GreenDamage cue was bound to the victim by
				# the ability event, before _kill. No rules or EL2 changes.
				if profile.id == "el1": _emit({"kind": "sacr_mana_gain_cue", "side": side})
			"spirit_lock":
				# Ether feeding: the sacrifice becomes ether channels; mastery spares it.
				if ELSpecs.roll(self, side, "GSLO") == 0: _kill(target)
				_change_ether(side, 0, int(definition.amount))
			"combine":
				_kill(target)
				if creatures.has(enchantment_id): _enchant("CMBN", side, enchantment_id, {"power": sacrificed.x, "toughness": sacrificed.y})
			"rebirth", "second_birth":
				heroes[side].grave.remove_at(enchantment_id)
				_summon(side, revived)
			"repair":
				var repaired: String = heroes[side].grave[enchantment_id]
				heroes[side].grave.remove_at(enchantment_id)
				_give_card(side, repaired)
				_emit({"kind": "return_card", "side": side, "card": repaired})
				_damage(1 - side, 1)
		# Energy and repair masteries leave the hero ability unused this turn.
		if (definition.effect == "energize" and ELSpecs.roll(self, side, "BENG") > 0) or (definition.effect == "repair" and ELSpecs.roll(self, side, "BRST") > 0):
			for e: Dictionary in c.enchantments:
				if e.id == definition.enchantment: e.used = false
		_finish_action()
		return true
	match ability:
		"illusion":
			if available_mana(side) < 1: return _fail("Shadows of the dead costs 1 ether.")
			_spend_ether(side, 1)
			if not c.has("ability_used"): c.ability_used = {}
			if not c.has("temporary"): c.temporary = []
			c.ability_used.illusion = true
			# Original modifiers replace the base defence, retaining other enchantments.
			c.temporary.append({"id": next_enchantment, "kind": "illusion", "toughness": heroes[side].grave.size() + 1 - int(profile.table("CombatCreatures")[c.card].Toughness)})
			next_enchantment += 1
			_refresh_stats(c)
			_emit({"kind": "ability", "source": id, "side": side, "ability": ability, "target": id, "grave": heroes[side].grave.size()})
			# First-game Shadows of the dead can leave a wall at lethal health
			# until a spell resolves or combat ends. A later buff can save it.
			if profile.id == "el2" and c.damage >= c.toughness: _kill(id)
		"awaken", "unparalyze":
			var price := int(definition.cost)
			if available_mana(side) < price: return _fail("Awakening costs %d ether and %d health." % [price, price])
			_spend_ether(side, price)
			_damage(side, price)
			c.resting = false
			_emit({"kind": "ability", "source": id, "side": side, "ability": ability, "target": id})
		"spores":
			# Carnivorous fingus may name itself: it dies and deals nothing; burning spores refuse it.
			if (target == id and c.card != "CAFG") or entity(target).is_empty(): return _fail("Select another creature or a hero.")
			var spore_damage := maxi(0, int(c.power)) if c.card == "CAFG" else 1
			_emit({"kind": "ability", "source": id, "side": side, "ability": ability, "target": target})
			# Fingus mastery: three successes out of three regenerate it for free.
			var saved := ELSpecs.roll(self, side, "GFNR", 3) == 3
			# The target dies before the fingus; naming itself deals nothing.
			if target != id and not entity(target).is_empty(): _damage(target, spore_damage)
			if saved: _emit({"kind": "regenerate", "target": id, "cost": 0})
			elif creatures.has(id): _kill(id)
		"wake":
			if available_mana(side) < 3: return _fail("Breaking enfeeblement costs 3 ether.")
			_spend_ether(side, 3)
			c.erase("enfeebled")
			for ench: Dictionary in c.enchantments.duplicate():
				if ench.card == "ENFL":
					_remove_enchantment(id, ench.id)
					break
			if not enfeebled(id): c.resting = false
			_emit({"kind": "ability", "source": id, "side": side, "ability": ability, "target": id})
		"disenchant":
			var victim := entity(target)
			if victim.is_empty(): return _fail("Select an enchantment.")
			var chosen := {}
			for ench: Dictionary in victim.enchantments:
				if int(ench.id) == enchantment_id: chosen = ench
			if chosen.is_empty(): return _fail("Select an enchantment.")
			# The removal price, not a warded casting cost.
			var price := enchantment_price(chosen)
			if available_mana(side) < price: return _fail("Not enough ether to remove this enchantment.")
			_spend_ether(side, price)
			c.resting = true
			_unassign(id)
			_remove_enchantment(target, enchantment_id)
			_emit({"kind": "ability", "source": id, "side": side, "ability": ability, "target": target})
	_finish_action()
	return true

func _first_ability(id: int, definition: Dictionary, target: int, grave_index: int, amount := -1) -> bool:
	var c: Dictionary = creatures[id]
	var side: int = c.owner
	var price := int(definition.cost)
	if definition.get("variable", false):
		# Pay-X abilities: X is chosen by the player and paid in full.
		if amount < int(definition.get("minimum", 0)) or amount > available_mana(side): return _fail("Choose how much ether to pay (up to %d)." % available_mana(side))
		price = amount
	if available_mana(side) < price: return _fail("This ability costs %d ether." % price)
	# A rejected ability is an illegal move: nothing is paid and nothing taps.
	if definition.key in ["sting", "tap_target", "sacrifice", "shoot", "slay", "wall_break", "gaze", "hunt"] and creatures.has(target) and not targetable(target): return _fail("This creature is protected by a magic screen.")
	match definition.key:
		"sting":
			if entity(target).is_empty(): return _fail("Select a creature or hero.")
		"tap_target":
			if not creatures.has(target): return _fail("Select a creature.")
		"sacrifice":
			if not creatures.has(target) or target == id or creatures[target].owner != side: return _fail("Select another of your creatures to sacrifice.")
		"gnaw", "recall_lamia", "recall_spirit", "recall_rat":
			if not grave_ability_targets(id, definition.key, target).has(grave_index): return _fail("Choose a suitable creature in a graveyard.")
		"brood":
			if army(side).size() >= 10: return _fail("A hero can control at most ten creatures.")
		"shoot":
			if not creatures.has(target) or creatures[target].owner == side or not attacks.has(target): return _fail("Select an attacking enemy creature.")
		"plague":
			if target not in [0, 1]: return _fail("Select a hero's graveyard.")
		"dispel":
			var chosen := _enchantment_by_id(target, grave_index)
			if chosen.is_empty() or not dispellable(target, chosen): return _fail("Select an enchantment that can be removed.")
			price = enchantment_price(chosen)
			if available_mana(side) < price: return _fail("Not enough ether to remove this enchantment.")
		"phantasm":
			if c.get("ability_used", {}).get("phantasm", false): return _fail("This ability has already been used this round.")
		"slay":
			if not creatures.has(target) or target == id: return _fail("Select another creature.")
			if not creatures[target].resting or attacks.has(target) or blocks.has(target): return _fail("Select a resting creature that is not in combat.")
		"wall_break":
			if not creatures.has(target) or race(target) != "Wall": return _fail("Select a wall.")
		"hunt":
			# The hunter may name itself once its own power is 4 or more.
			if not creatures.has(target) or int(creatures[target].power) < 4: return _fail("Select a creature with power 4 or more.")
		"necromancy":
			if not grave_ability_targets(id, definition.key, target).has(grave_index): return _fail("Choose a cheap enough creature in a graveyard.")
			# The second game refuses when the necromancer's army is already full.
			if profile.id == "el2" and army(side).size() >= 10: return _fail("A hero can control at most ten creatures.")
		"siphon":
			if profile.id == "el2" and int(heroes[1 - side].mana) <= 0: return _fail("The opponent has no ether to draw.")
		"gaze":
			if not creatures.has(target): return _fail("Select a creature.")
			var beholders := 0
			for ally: Dictionary in army(side):
				if race(ally.id) == "Beholder": beholders += 1
			if definition.measure == "power" and race(target) == "Wall": return _fail("Walls resist this gaze.")
			if int(creatures[target][definition.measure]) > beholders: return _fail("Your beholders are too few for this creature.")
		"tap_race":
			if not creatures.has(target) or creatures[target].owner == side: return _fail("Select an enemy creature.")
			if profile.id == "el2":
				if in_plane(target): return _fail("This creature is in the Colourless Plane.")
				if not targetable(target): return _fail("This creature is protected by a magic screen.")
			price = 0
			for enemy: Dictionary in army(1 - side):
				if not enemy.resting and race(enemy.id) == race(target) and (profile.id != "el2" or not in_plane(enemy.id)): price += 1
			if available_mana(side) < price: return _fail("This costs %d ether." % price)
	if definition.get("ready", true):
		c.resting = true
		_unassign(id)
	_spend_ether(side, price)
	_emit({"kind": "ability", "source": id, "side": side, "ability": definition.key, "name": definition.name, "target": target})
	match definition.key:
		"sting": _damage(target, int(definition.get("amount", 1)))
		"draw": _draw(side)
		"siphon":
			var moved := mini(int(definition.amount), maxi(0, int(heroes[1 - side].mana)))
			_change_ether(1 - side, -moved)
			_change_ether(side, moved)
		"slay", "gaze", "hunt": _destroy(target)
		"wall_break": _destroy(target, true)
		"necromancy":
			# The card leaves the graveyard even when a full army leaves it nowhere to go.
			var raised: String = heroes[target].grave[grave_index]
			heroes[target].grave.remove_at(grave_index)
			if army(side).size() < 10: _summon(side, raised)
			else: _emit({"kind": "grave_removed", "side": target, "card": raised})
		"tap_race":
			var kind := race(target)
			for enemy: Dictionary in army(1 - side):
				if not enemy.resting and race(enemy.id) == kind and (profile.id != "el2" or not in_plane(enemy.id)):
					enemy.resting = true
					_unassign(enemy.id)
		"distortion":
			# The wall dies, every attacker withdraws and a dispellable fog covers its side.
			# The wall leaves play without reaching the graveyard (its leave hooks still run).
			_remove_creature(id, "death")
			attacks.clear()
			blocks.clear()
			# The second game's fog is its own support card, Distortion.
			_mark(side, "EWLD" if profile.id == "el2" else "WLDT", 0, 0, {"price": 10 if profile.id == "el2" else 0})
		"breath":
			for victim: Dictionary in army(1 - side):
				if creatures.has(victim.id) and has_flag(victim.id, "Fly") == (definition.scope == "flying"): _damage(victim.id, int(definition.amount))
		"bat_drain":
			var bats := 0
			for ally: Dictionary in army(side):
				if race(ally.id) == "Bat": bats += 1
			# The bats heal only by damage that actually reached the hero; the
			# second game heals by the amount dealt, at most the remaining health.
			var before := int(heroes[1 - side].health)
			var dealt := _damage(1 - side, bats)
			# Both originals start DrainLife only when the damage lands.
			if dealt > 0: _emit({"kind": "bat_drain_cue", "source": id, "side": side})
			var gained := mini(dealt, before) if profile.id == "el2" else (bats if dealt > 0 else 0)
			if gained > 0:
				heroes[side].health += gained
				_emit({"kind": "heal", "target": side, "amount": gained, "source": id})
		"rally":
			for ally: Dictionary in army(side):
				if ally.card != "KBEL" and ally.resting and race(ally.id) == "Kobold": ally.resting = false
		"tap_target":
			if not creatures[target].resting:
				creatures[target].resting = true
		"tap_walls":
			for wall: int in _resting_walls(1 - side):
				creatures[wall].resting = true
				_unassign(wall)
		"brood": _summon(side, definition.summon)
		"ether": _change_ether(side, 1)
		"shoot": _damage(target, int(definition.get("amount", 1)))
		"plague":
			# The oldest graveyard entries go first; unused ether is not refunded.
			for removal in mini(amount, heroes[target].grave.size()):
				var removed: String = heroes[target].grave.pop_front()
				_emit({"kind": "grave_removed", "side": target, "card": removed})
		"recall_rat":
			var rat: String = heroes[side].grave[grave_index]
			heroes[side].grave.remove_at(grave_index)
			_give_card(side, rat)
			_emit({"kind": "return_card", "side": side, "card": rat})
		"dispel": _dispel(target, grave_index)
		"spirit_flight":
			# Every warrior spirit flies, later arrivals included, until the end of the
			# opponent's next turn; the effect outlives the wizard.
			if not heroes[side].has("temporary"): heroes[side].temporary = []
			# `source`: the wizard, which holds the original's effect object even after it dies.
			heroes[side].temporary.append({"id": next_enchantment, "kind": "spirit_flight", "card": "WRSP", "flags": ["Fly"], "keeper": side, "source": id})
			next_enchantment += 1
			for spirit: Dictionary in creatures.values(): _refresh_stats(spirit)
		"phantasm", "lava_power", "hellfire_health":
			if definition.key == "phantasm":
				if not c.has("ability_used"): c.ability_used = {}
				c.ability_used.phantasm = true
			if not c.has("temporary"): c.temporary = []
			var boost := {"id": next_enchantment, "kind": definition.key}
			if definition.key == "hellfire_health": boost.toughness = amount
			else: boost.power = 2 if definition.key == "phantasm" else amount
			c.temporary.append(boost)
			next_enchantment += 1
			_refresh_stats(c)
		"rouse":
			if not c.has("ability_used"): c.ability_used = {}
			c.ability_used.rouse = true
			for spirit: Dictionary in creatures.values():
				if spirit.card == "WRSP" and spirit.resting: spirit.resting = false
		"sacrifice":
			_kill(target)
			if creatures.has(id): c.resting = false
		"gnaw":
			var removed: String = heroes[target].grave[grave_index]
			heroes[target].grave.remove_at(grave_index)
			_emit({"kind": "grave_removed", "side": target, "card": removed})
		"recall_lamia":
			var card: String = heroes[side].grave[grave_index]
			heroes[side].grave.remove_at(grave_index)
			_give_card(side, card)
			_emit({"kind": "return_card", "side": side, "card": card})
		"recall_spirit":
			heroes[side].grave.remove_at(grave_index)
			if army(side).size() < 10: _summon(side, "WRSP")
	_finish_action()
	return true

func _enchant(card: String, side: int, target: int, rule: Dictionary) -> void:
	var e := {"id": next_enchantment, "card": card, "owner": side, "born": turn_serial,
		"power": int(rule.get("power", 0)), "toughness": int(rule.get("toughness", 0))}
	if rule.get("fixed", false): e.fixed = true
	if rule.get("lethal", false): e.lethal = true
	if card == "WRBN":
		var exempt: Array[int] = []
		for c: Dictionary in creatures.values():
			if c.flags.has("NoAffect"): exempt.append(int(c.id))
		e.exempt = exempt
	if card == "ALNS" and target >= 2:
		# Mark of Pale: +N/+N for the Pale creatures the caster's opponent controls, counted once.
		var count := 0
		for c: Dictionary in army(1 - side):
			if pale(c.id): count += 1
		e.power = count
		e.toughness = count
	if card == "ALST" and target >= 2:
		# Alpha strike heals the creature and adds its printed power.
		creatures[target].damage = 0
		e.power = int(profile.table("CombatCreatures")[creatures[target].card].Power)
	if card == "ENFL" and target >= 2 and profile.id == "el1":
		# First-game enfeeblement is no enchantment: a stat modifier and the creature's own break ability,
		# so nothing can dispel it.
		creatures[target].enfeebled = true
		creatures[target].resting = true
		_emit({"kind": "enchant", "target": target, "card": card, "power": 0, "toughness": 0})
		return
	next_enchantment += 1
	# A water link is held by the caster's hero and names its creature.
	var holder := target
	if card == "WTLK" and target >= 2:
		e.link = target
		holder = side
	entity(holder).enchantments.append(e)
	# A new army enchantment also covers creatures that changed sides into this army.
	if target < 2 and ELCatalog.ARMY_AURAS.has(card):
		for c: Dictionary in creatures.values():
			if c.has("auras") and int(c.owner) == holder: c.auras.append(int(e.id))
	if target >= 2:
		_refresh_stats(creatures[target])
		if card in ["ENFL", "IMMB", "WNPZ"]:
			# Taps at once. A declared blocker keeps blocking; the second game withdraws a declared attacker,
			# the first lets it strike.
			creatures[target].resting = true
			if profile.id == "el2": attacks.erase(target)
		elif card == "SPWR": creatures[target].resting = false
		elif card in ELCatalog.CONTROL:
			# Control passes to the caster; the creature must wait a turn to act.
			var stolen: Dictionary = creatures[target]
			stolen.origin = origin(target)
			_move_army(stolen, side)
			stolen.sick = not (profile.id == "el2" and has_flag(target, "NSS"))
			_unassign(target)
			_refresh_armies()
	elif _changes_armies(card):
		for c: Dictionary in creatures.values(): _refresh_stats(c)
	if target < 2 and card in ["FOGG", "ASST", "PCDU"]:
		# Fog and ash withdraw every declared attacker; none can be declared while they last.
		attacks.clear()
		blocks.clear()
	if target < 2 and card == "BLKD":
		# Blockade withdraws the caster's declared attackers.
		for id: int in attacks.duplicate():
			if creatures.has(id) and creatures[id].owner == side: _unassign(id)
	if card == "ERBN":
		for c: Dictionary in creatures.values(): _refresh_stats(c)
	_emit({"kind": "enchant", "target": target, "card": card, "power": e.power, "toughness": e.toughness})
	# EL1 Fog@ and EL2 Fog@ register CantAttack against
	# each creature in the original combat list, after opening BlueFog.
	# These cues are transient and do not affect the enchantment/save rules.
	if profile.id in ["el1", "el2"] and card == "FOGG":
		for creature: Dictionary in creatures.values():
			_emit({"kind": "fog_creature_cue", "target": int(creature.id)})
	# The forests' per-creature hook (EL1 Ancient Forest@, EL2
	# @) shows the forest only on each opposing creature it stops.
	if target < 2 and forest_limit(card) >= 0:
		for creature: Dictionary in creatures.values():
			if creature.owner != target and creature.power <= forest_limit(card):
				_emit({"kind": "forest_creature_cue", "target": int(creature.id)})
	if target >= 2 and creatures[target].damage >= creatures[target].toughness: _lethal(target)
	elif target < 2 and _changes_armies(card):
		# Immolation's toughness cut kills creatures it brings to zero.
		for c: Dictionary in creatures.values():
			if creatures.has(c.id) and c.damage >= c.toughness: _lethal(c.id)

func _refresh_stats(c: Dictionary) -> void:
	var stats := creature_stats(c)
	c.power = stats.x
	c.toughness = stats.y
	var granted: Array[String] = []
	for e: Dictionary in c.enchantments:
		for flag: String in ELCatalog.GRANTED_FLAGS.get(e.card, []): granted.append(flag)
		# First-game redirection also forbids regeneration.
		if e.card == "REDR" and profile.id == "el1": granted.append("NoRegen")
	# Earth bonds keep every creature of the holder's race from recovering.
	if not c.flags.has("NoAffect"):
		for holder: Dictionary in creatures.values():
			if _enchantment_count(holder.id, "ERBN") > 0 and race(holder.id) == race(c.id):
				granted.append("NoUntap")
				break
	for aura: Dictionary in _creature_auras(c):
		for flag: String in aura.get("flags", []): granted.append(flag)
	for effect: Dictionary in c.get("temporary", []):
		for flag: String in effect.get("flags", []): granted.append(flag)
	for e: Dictionary in army_auras(c):
		for flag: String in ELCatalog.ARMY_AURAS[e.card].get("flags", []): granted.append(flag)
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments:
			var aura: Dictionary = ELCatalog.HERO_AURAS.get(e.card, {})
			# Unaffected creatures ignore them.
			if aura.is_empty() or (aura.scope == "enemy" and c.owner == int(e.owner)) or c.flags.has("NoAffect"): continue
			for flag: String in aura.flags: granted.append(flag)
	for hero: Dictionary in heroes:
		for effect: Dictionary in hero.get("temporary", []):
			if effect.get("card", c.card) == c.card:
				for flag: String in effect.get("flags", []): granted.append(flag)
	if granted.is_empty(): c.erase("granted")
	else: c.granted = granted

## Passive race auras from first-game creatures in play that cover `c`.
func _creature_auras(c: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind := str(profile.table("CombatCreatures").get(c.card, {}).get("Race", ""))
	for source: Dictionary in creatures.values():
		var aura: Dictionary = ELCatalog.creature_aura(profile, source.card)
		if not aura.is_empty() and _aura_covers(aura, source, c, kind): result.append(aura)
	return result

func _aura_covers(aura: Dictionary, source: Dictionary, c: Dictionary, kind: String) -> bool:
	if aura.get("race", kind) != kind or aura.get("card", c.card) != c.card: return false
	return not (aura.get("own", false) and source.owner != c.owner)

## Both originals show an aura's effect on each creature it newly covers: on every covered creature
## when the source arrives, and on a later arrival.
func _aura_arrival_cues(arrival: Dictionary) -> void:
	if not creatures.has(arrival.id): return
	var races: Dictionary = profile.table("CombatCreatures")
	for source: Dictionary in creatures.values():
		var aura: Dictionary = ELCatalog.creature_aura(profile, source.card)
		if aura.is_empty(): continue
		var covered: Array = creatures.values() if source.id == arrival.id else [arrival]
		for c: Dictionary in covered:
			if _aura_covers(aura, source, c, str(races.get(c.card, {}).get("Race", ""))):
				_emit({"kind": "aura_cue", "card": source.card, "source": source.id, "target": c.id})
	# Drowsy, Depressing and Frenzy Gas are auras over every creature: their per-creature callback also
	# runs for a later arrival, once per copy, with the same Target cues as the cast. Exemptions follow
	# the gases' stat rule.
	for card: String in ["DRGS", "DPGS", "FRGS"]:
		if arrival.flags.has("NoAffect") or arrival.get("plane", false): continue
		for copy in global_enchantment_count(card):
			_emit({"kind": "aura_cue", "card": card, "source": -1, "target": arrival.id})

## Recompute every creature after an aura source arrives or leaves; retained
## damage that becomes lethal kills without regeneration.
func _refresh_armies() -> void:
	for c: Dictionary in creatures.values(): _refresh_stats(c)
	for c: Dictionary in creatures.values():
		if creatures.has(c.id) and c.damage >= c.toughness: _lethal(c.id)

## First-game Wall of Illusion delays its ability's lethal health change.
## Attack declarations and other creature abilities do not settle that change.
func _settle_illusion_health() -> void:
	if profile.id != "el1": return
	for c: Dictionary in creatures.values():
		if creatures.has(c.id) and c.card == "WLIL" and c.get("ability_used", {}).get("illusion", false) and c.damage >= c.toughness:
			_lethal(c.id)

func creature_stats(c: Dictionary, additional_gas := 0) -> Vector2i:
	var base: Dictionary = profile.table("CombatCreatures")[c.card]
	# Spell-jammers created by traps carry their own base X/X.
	var printed := Vector2i(int(c.base[0]), int(c.base[1])) if c.has("base") else Vector2i(int(base.Power), int(base.Toughness))
	var power := printed.x
	var toughness := printed.y
	# The gases weaken every creature except unaffected ones and those in the Colourless Plane.
	if not c.flags.has("NoAffect") and not c.get("plane", false):
		power -= _enchantment_count(0, "DRGS") + _enchantment_count(1, "DRGS") + additional_gas
		power -= 2 * global_enchantment_count("DPGS")
		toughness -= 2 * global_enchantment_count("FRGS")
	var lethal := 0
	for e: Dictionary in c.enchantments:
		# Unaffected creatures keep lake snake venom's mark without its -1/-1.
		if e.card == "LASN" and c.flags.has("NoAffect"): continue
		power += int(e.power)
		# Lake snake venom lowers health past the usual minimum of one.
		if e.get("lethal", false): lethal -= int(e.toughness)
		else: toughness += int(e.toughness)
	for effect: Dictionary in c.get("temporary", []):
		power += int(effect.get("power", 0))
		toughness += int(effect.get("toughness", 0))
	# Army modifiers also cover creatures that arrive later.
	for e: Dictionary in army_auras(c):
		var aura: Dictionary = ELCatalog.ARMY_AURAS[e.card]
		power += int(aura.get("power", 0))
		toughness += int(aura.get("toughness", 0))
		lethal += int(aura.get("lethal", 0))
	for aura: Dictionary in _creature_auras(c):
		power += int(aura.get("power", 0))
		toughness += int(aura.get("toughness", 0))
	# Amulet of war: +1/+1 per other creature of the same race on either side;
	# unaffected creatures in play at the cast are exempt.
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments:
			if e.card != "WRBN" or e.get("exempt", []).has(int(c.id)): continue
			var kin := _kin(c)
			power += kin
			toughness += kin
	# Overload decay stays with the creature even after the enchantment goes.
	var decay := int(c.get("decay", 0))
	power -= 2 * decay
	lethal += 2 * decay
	# Delusion swaps power and toughness last (an even number cancels); a
	# swapped toughness has no minimum of one, so a 0-power creature dies.
	var delusions: int = c.enchantments.filter(func(e: Dictionary) -> bool: return e.card == "DELS").size()
	# Ordinary creature stats clamp after all modifiers, not after each one.
	var result := Vector2i(maxi(0, power), maxi(0, (maxi(1, toughness) if delusions % 2 == 0 else maxi(0, toughness)) - lethal))
	# Alpha strike caps toughness at one after every other modifier.
	for e: Dictionary in c.enchantments:
		if e.card == "ALST": result.y = mini(result.y, 1)
	if delusions % 2 == 1: result = Vector2i(result.y, result.x)
	return result

func _kin(c: Dictionary) -> int:
	var count := 0
	var own := race(int(c.id))
	for other: Dictionary in creatures.values():
		if other.id != c.id and race(int(other.id)) == own and not in_plane(int(other.id)): count += 1
	return count

## Presentation-only snapshots for both originals' WarBanner entry/exit hooks.
## The modifiers already live in creature_stats; comparing them lets the view
## show an effect only on a figure whose bonus actually changed.
func _war_banner_bonuses() -> Dictionary:
	var result := {}
	if profile.id not in ["el1", "el2"] or global_enchantment_count("WRBN") == 0: return result
	for c: Dictionary in creatures.values():
		var bonus := 0
		for hero: Dictionary in heroes:
			for e: Dictionary in hero.enchantments:
				if e.card == "WRBN" and not e.get("exempt", []).has(int(c.id)):
					bonus += _kin(c)
		if bonus != 0: result[int(c.id)] = bonus
	return result

func _war_banner_reactions(before: Dictionary) -> void:
	if profile.id not in ["el1", "el2"]: return
	var after := _war_banner_bonuses()
	for id: int in creatures:
		var change := int(after.get(id, 0)) - int(before.get(id, 0))
		if change != 0: _emit({"kind": "war_banner_shift", "target": id, "amount": change})

func _changes_armies(card: String) -> bool:
	return card in ["DRGS", "DPGS", "FRGS", "WRBN"] or ELCatalog.ARMY_AURAS.has(card) or ELCatalog.HERO_AURAS.has(card)

func _enchantment_by_id(holder: int, enchantment_id: int) -> Dictionary:
	for e: Dictionary in entity(holder).get("enchantments", []):
		if int(e.id) == enchantment_id: return e
	return {}

## A creature-made enchantment: not dispellable, priced -1 like the original.
func _mark(target: int, card: String, power: int, toughness: int, extra: Dictionary = {}) -> void:
	var e := {"id": next_enchantment, "card": card, "owner": int(entity(target).get("owner", target)), "born": turn_serial, "power": power, "toughness": toughness}
	e.merge(extra, true)
	next_enchantment += 1
	entity(target).enchantments.append(e)
	if target >= 2: _refresh_stats(creatures[target])
	_emit({"kind": "enchant", "target": target, "card": card, "power": power, "toughness": toughness})

func _enchantment_count(id: int, card: String) -> int:
	var count := 0
	for e: Dictionary in entity(id).get("enchantments", []):
		if e.card == card: count += 1
	return count

## A dispel by a spell, ability or artifact. First-game specialisations of the
## enchantment's caster: sentinel keeps it (the dispel still counts as done),
## eternal enchantment returns the card to the caster's hand.
func _dispel(holder: int, enchantment_id: int) -> void:
	var e := _enchantment_by_id(holder, enchantment_id)
	if e.is_empty(): return
	var caster := int(e.owner)
	if profile.id == "el1" and caster in [0, 1] and ELSpecs.roll(self, caster, "MSEN") > 0: return
	_remove_enchantment(holder, enchantment_id)
	if profile.id == "el1" and caster in [0, 1] and not ELCatalog.rule(profile, e.card).is_empty() and ELSpecs.roll(self, caster, "ETEN") > 0:
		_give_card(caster, e.card)
		_emit({"kind": "return_card", "side": caster, "card": e.card})
		# Original successful ETEN dispel registers one hero-bound
		# Target/Draw only after actually returning the enchantment card.
		_emit({"kind": "eten_return_draw_cue", "side": caster})

func _remove_enchantment(target: int, enchantment_id: int) -> void:
	var victim := entity(target)
	for e: Dictionary in victim.get("enchantments", []).duplicate():
		if int(e.id) != enchantment_id: continue
		victim.enchantments.erase(e)
		if target >= 2 and e.card in ELCatalog.CONTROL and victim.has("origin"):
			_move_army(victim, int(victim.origin))
			victim.erase("origin")
			# Returned control also waits a turn, as on the steal.
			victim.sick = not (profile.id == "el2" and has_flag(target, "NSS"))
			_unassign(target)
			_refresh_armies()
		if e.card == "ERBN":
			for c: Dictionary in creatures.values(): _refresh_stats(c)
		elif target >= 2:
			_refresh_stats(victim)
		elif _changes_armies(e.card):
			for c: Dictionary in creatures.values(): _refresh_stats(c)
		_emit({"kind": "disenchant", "target": target, "card": e.card})
		if scripts != null: scripts.dispatch("CHook_OnVisualRemoveEnchantment", [e.card, float(target)])
		# Alpha strike always costs the creature; a removed quick fix destroys it
		# without regeneration (and without returning the card to hand).
		if target >= 2 and e.card == "ALST":
			# AlphaStrikeEnchantment removal (EL1, EL2)
			# queues BlackDeath on its holder with the unavoidable death (EL2
			# once the holder is marked dead; the remake's kill always succeeds).
			if profile.id in ["el1", "el2"]: _emit({"kind": "alpha_strike_death", "target": target})
			_kill(target)
		elif target >= 2 and e.card == "QKFX": _destroy(target, true)
		elif target >= 2 and victim.damage >= victim.toughness: _lethal(target)
		elif target < 2:
			# Losing an army health modifier exposes retained lethal damage.
			for c: Dictionary in creatures.values():
				if c.damage >= c.toughness: _lethal(c.id)
		return

func end_phase() -> bool:
	if gate == null: return _end_phase_now()
	var action := {"kind": "end_phase", "side": active_side()}
	if not gate.gate_check(self, action): return _refused()
	var ok := _end_phase_now()
	gate.gate_done(self, action, ok)
	return ok

func _end_phase_now() -> bool:
	error = ""
	if phase == Phase.FINISHED: return false
	if phase == Phase.ATTACK:
		_sync_attacks()
		for c: Dictionary in creatures.values(): c.regenerated = false
		phase = Phase.DEFENCE
		_emit({"kind": "phase", "side": active_side(), "phase": "defence", "round": round_number})
		if attacks.is_empty(): return _end_phase_now()
	else:
		_resolve_attacks()
		_settle_illusion_health()
		_drain_scripts()
		if phase == Phase.FINISHED:
			changed.emit()
			return true
		# The last card of the hand goes first.
		while heroes[attacker].hand.size() > 5:
			var card := _take_card(attacker, hand_display(attacker).back())
			_emit({"kind": "discard", "side": attacker, "card": card})
		for c: Dictionary in creatures.values():
			# Second-game bloodlessness keeps the creature's damage.
			if not recovery_blocked(c.owner) and not (profile.id == "el2" and _enchantment_count(c.id, "RIOT") > 0): c.damage = 0
		_first_turn_end()
		_return_buried_creatures(attacker)
		for c: Dictionary in army(attacker): c.sick = false
		_turn_enchantments(false)
		_check_winner()
		if phase == Phase.FINISHED:
			changed.emit()
			return true
		attacker = 1 - attacker
		if attacker == first_side(): round_number += 1
		phase = Phase.ATTACK
		attacks.clear()
		blocks.clear()
		# Only the battle's very first turn skips the draw.
		_begin_attack(true)
	changed.emit()
	return true

## Velos that took no combat damage since their owner's last turn end destroy
## themselves; mechozaurus parasites drain their controller.
func _first_turn_end() -> void:
	for c: Dictionary in army(attacker):
		if creatures.has(c.id) and c.card in ELCatalog.FATALISTS and not c.sick and not c.get("hit", false): _trigger_damage(c.card, c.id, int(c.toughness))
	for c: Dictionary in army(attacker):
		c.erase("hit")
		if ELCatalog.PARASITES.has(c.card):
			# Parasite mastery: each point of the drain may be spared.
			var drain := int(ELCatalog.PARASITES[c.card])
			drain -= ELSpecs.roll(self, attacker, "BMZP", drain)
			# Original Mechozaurus callbacks (EL2, EL1) draw
			# BlackRedirect from the creature (Start) to its hero (Finish).
			if drain > 0: _trigger_damage(c.card, attacker, drain, int(c.id))
	# No winner check here: these are part of the original turn-end callback
	# list, and victory is decided after the whole sequence (a hero drained
	# here and the other hero killed by an enchantment is a draw).

## Enchantments with an end-of-turn effect (for the unused end-of-turn script hooks).
const END_OF_TURN_CARDS := ["MNBN", "WETX", "STTX", "WTX2", "OCRP", "ENVM", "SFGS", "TRSN", "SWSN", "ESWS", "ETRS", "IRRT", "MDNS", "RDIS", "OVRL", "TWEN"]

func _turn_enchantments(at_start: bool) -> void:
	# Hero and creature enchantments share one creation-order callback list.
	var pending: Array[Dictionary] = []
	for target: int in [0, 1] + creatures.keys():
		for e: Dictionary in entity(target).enchantments:
			pending.append({"target": target, "effect": e})
		for e: Dictionary in entity(target).get("temporary", []):
			pending.append({"target": target, "effect": e, "temporary": true})
	pending.sort_custom(func(a: Dictionary, b: Dictionary): return a.effect.id < b.effect.id)
	var ended_hooks := false
	for entry: Dictionary in pending:
		var target: int = entry.target
		var victim := entity(target)
		var e: Dictionary = entry.effect
		if victim.is_empty(): continue
		if entry.get("temporary", false):
			# A bless from an older save keeps an until_turn_of it no longer uses.
			var ends: bool = attacker == int(e.until_turn_of) if e.has("until_turn_of") and e.get("kind") != "bless" else (attacker != int(e.keeper) if e.has("keeper") else victim.owner != attacker)
			if not at_start and ends and victim.temporary.has(e):
				victim.temporary.erase(e)
				if victim.temporary.is_empty(): victim.erase("temporary")
				if target >= 2: _refresh_stats(victim)
				else:
					for c: Dictionary in creatures.values(): _refresh_stats(c)
				# Both Wand of Bless detach callbacks show negative modifiers
				# at the affected creature (EL1 -;
				# EL2). This is presentation only.
				if profile.id in ["el1", "el2"] and e.get("kind") == "bless":
					_emit({"kind": "bless_expire", "target": target})
			continue
		if not victim.enchantments.has(e): continue
		if at_start:
			var price := 0
			match e.card:
				"STSI":
					if e.owner != attacker: continue
					price = stasis_upkeep(e)
					if heroes[attacker].mana < price:
						_remove_enchantment(target, e.id)
						continue
				"SPTR": price = mini(army(attacker).size(), int(heroes[attacker].mana))
				_: continue
			_emit({"kind": "upkeep", "side": attacker, "card": e.card, "amount": price})
			_spend_ether(attacker, price)
			# EL1 original Stasis owner-start slot 2 registers
			# one Draw FX at the owner for each paid callback.
			# The earlier global BlueStasis turn cue is independent.
			if profile.id == "el1" and e.card == "STSI":
				_emit({"kind": "stsi_upkeep_draw_cue", "side": attacker})
			# EL1 SPTR slot 2 invokes original
			# GreenDamage for a nonempty current army at its active hero;
			# the callback is independent of the already-accounted ether.
			if profile.id == "el1" and e.card == "SPTR" and not army(attacker).is_empty():
				_emit({"kind": "sptr_upkeep_cue", "side": attacker, "amount": price})
		else:
			# No shipped script uses these two hooks; the holder ID stands in for the
			# unidentified second argument.
			if scripts != null and e.card in END_OF_TURN_CARDS:
				scripts.dispatch("CHook_OnVisualStartEnchantmentEndOfTurn", [e.card, float(target)])
				ended_hooks = true
			match e.card:
				"MNBN":
					# Burn resistance spares ether here too.
					var burn := int(heroes[attacker].mana)
					if burn > 0: burn -= ELSpecs.roll(self, attacker, "RMBD", burn)
					if burn > 0: _trigger_damage(e.card, attacker, burn)
				"WETX", "STTX", "WTX2":
					if target != attacker: _trigger_damage(e.card, target, 3 if e.card == "STTX" else 1)
				"OCRP":
					# Cripple: after each turn not owned by its caster, the opponent of
					# the holder's controller draws one card.
					if target >= 2 and int(e.owner) != attacker:
						# EL2 OuterCripple binds Draw at the drawing hero.
						_emit({"kind": "trigger_cue", "card": "OCRP", "target": 1 - int(victim.owner)})
						_draw(1 - int(victim.owner))
				"ENVM":
					if target == attacker: _trigger_damage(e.card, target, 2)
				"SFGS":
					if e.owner != attacker: continue
					for side in 2:
						# Gas mastery: each creature and the hero of that side may be spared.
						for c: Dictionary in army(side):
							if ELSpecs.roll(self, side, "BSGP") == 0: _trigger_damage(e.card, c.id, 2)
						if ELSpecs.roll(self, side, "BSGP") == 0: _trigger_damage(e.card, side, 2)
				"RDDF", "FOGG", "FDBK", "FURY", "ASST", "ASLT", "WLDT", "EWLD", "ETCH", "PLSL", "ORPL", "LNRD", "PCDU":
					# These end with a turn that their caster did not own.
					if e.owner != attacker: _remove_enchantment(target, e.id)
				"BLSS", "CMBN", "ALST", "RLSS":
					# Creature bonuses end with a turn not owned by the holder's original owner;
					# blessing mastery may keep a blessing for another turn.
					if target >= 2 and origin(target) != attacker:
						if e.card == "BLSS" and ELSpecs.roll(self, origin(target), "GBLP") > 0: continue
						_remove_enchantment(target, e.id)
						# Both original RLSS temporary bonuses detach with
						# Target/NegAttack/NegDefence/NegRune at the holder
						# (EL1, EL2).
						if profile.id in ["el1", "el2"] and e.card == "RLSS":
							_emit({"kind": "lightning_storm_bless_expire", "target": target})
						# Bless and Combine end the same way (EL1
						# EL2).
						elif profile.id in ["el1", "el2"] and e.card in ["BLSS", "CMBN"]:
							_emit({"kind": "bless_expire", "target": target, "card": e.card})
				"FREL":
					# The fire burn ends with a turn not owned by the burnt creature's controller.
					if target >= 2 and victim.owner != attacker: _remove_enchantment(target, e.id)
				"TRSN", "SWSN", "ESWS", "ETRS":
					# Venom strikes the poisoned hero at the end of that hero's own turns.
					if target < 2 and target == attacker: _trigger_damage(e.card, target, 1)
				"IRRT", "MDNS", "RDIS":
					# Original EL2 Irritation, Madness and
					# Insanity share one gate ([[holder+4]] == 0):
					# no damage and no effect while the holder is in the plane.
					if target >= 2 and victim.owner == attacker and (profile.id != "el2" or not in_plane(target)):
						_trigger_damage(e.card, attacker, 1 if e.card == "IRRT" else 2)
						# Irritation that kills its holder's hero shows the fight shot at that hero.
						if e.card == "IRRT" and int(heroes[attacker].health) <= 0: _camera_cue("IRRT", attacker, "fight")
				"OVRL":
					# Overload decays -2/-2 at each of its controller's turn ends; the
					# decay kills without regeneration.
					if target >= 2 and victim.owner == attacker:
						victim.decay = int(victim.get("decay", 0)) + 1
						_refresh_stats(victim)
						# Both original OverloadEnchantment end-of-turn callbacks
						# (EL1, EL2) queue NegAttack,
						# NegDefence and NegRune on the enchanted creature.
						if profile.id in ["el1", "el2"]:
							_emit({"kind": "overload_decay", "target": target, "card": "OVRL"})
						if victim.damage >= victim.toughness: _kill(target)
				"TWEN":
					if target < 2 or victim.owner != attacker: continue
					# Decay reduces current stats: a creature held at toughness 1 only by the floor dies.
					var floor_toughness := int(victim.toughness) - 1
					e.power -= 1
					e.toughness -= 1
					_refresh_stats(victim)
					# Both original TwistedEnhancement end-of-turn callbacks
					# (EL1, EL2) queue NegAttack,
					# NegDefence and NegRune on the enchanted creature.
					if profile.id in ["el1", "el2"]:
						_emit({"kind": "twisted_decay", "target": target, "card": "TWEN"})
					if victim.damage >= mini(int(victim.toughness), floor_toughness): _lethal(target)
	if ended_hooks: scripts.dispatch("CHook_OnVisualFinishEnchantmentEndOfTurn", [])
	if not at_start:
		# Expiring defence can expose damage retained by Fatal Disease. The original
		# final state check kills these creatures without ordinary regeneration.
		for c: Dictionary in creatures.values():
			if c.damage >= c.toughness: _lethal(c.id)

## Pale warp: at its owner's turn start each copy destroys the Pale creature
## with the least toughness (bright ones dissipate); with none, that copy ends.
func _pale_warp() -> void:
	for e: Dictionary in heroes[attacker].enchantments.duplicate():
		if e.card != "PLWP" or not heroes[attacker].enchantments.has(e): continue
		var chosen := -1
		for c: Dictionary in creatures.values():
			if pale(c.id) and (chosen < 0 or c.toughness - c.damage < creatures[chosen].toughness - creatures[chosen].damage or (c.toughness - c.damage == creatures[chosen].toughness - creatures[chosen].damage and c.id < chosen)):
				chosen = int(c.id)
		if chosen < 0:
			_remove_enchantment(attacker, int(e.id))
			continue
		# EL2: PlaneWarp from the warp's owner (Start) to
		# the victim (Finish), then OutplaneSpellDeath at the victim.
		_emit({"kind": "trigger", "card": "PLWP", "target": chosen, "source": attacker, "amount": 0})
		_damage(chosen, maxi(1, int(creatures[chosen].toughness) - int(creatures[chosen].damage)), false, false, true, true, true)

## Spell-jammer traps: after any sorcery each qualifying trap summons its
## jammer for its owner and leaves play.
func _spell_traps(side: int, card: String, extra_ether: int, traps: Array[Dictionary]) -> void:
	var printed := int(profile.table("CombatSpells")[card].Cost)
	for entry: Dictionary in traps:
		var owner: int = entry.owner
		var e: Dictionary = entry.effect
		if not heroes[owner].enchantments.has(e) or army(owner).size() >= 10: continue
		if e.card == "OST3" and side == owner: continue
		var jammer: String = "OSJ" + e.card.substr(3)
		_camera_cue(e.card, owner)
		_summon(owner, jammer)
		var id := next_id - 1
		if not creatures.has(id) or creatures[id].card != jammer: continue
		if e.card != "OST1":
			var x := printed if e.card == "OST2" else maxi(printed, 0) + extra_ether
			creatures[id].base = [x, x]
			_refresh_stats(creatures[id])
			if creatures[id].toughness <= 0 or x <= 0: _kill(id)
		_remove_enchantment(owner, int(e.id))

## An enchantment's own automatic-camera request (presentation only): a spell
## shot cast by `side`'s hero over `figures`, or a fight shot at that hero.
func _camera_cue(card: String, side: int, shot := "sorcery", figures: Array = []) -> void:
	_emit({"kind": "camera_cue", "card": card, "side": side, "shot": shot, "figures": figures})

## `source`: the figure the original draws the effect from (Start), if any.
func _trigger_damage(card: String, target: int, amount: int, source := -1) -> void:
	var event := {"kind": "trigger", "card": card, "target": target, "amount": amount}
	if source >= 0: event["source"] = source
	_emit(event)
	_damage(target, amount)

## Original tests the acting player's var 2, not the number
## enchantments on the active hero. These known auras add to their caster's
## counter, even when their effects apply to both sides.
func _el1_has_pos_rune(side: int) -> bool:
	for holder: Dictionary in heroes:
		for e: Dictionary in holder.enchantments:
			if int(e.owner) == side and String(e.card) in (EL2_POS_RUNE_SOURCES if profile.id == "el2" else EL1_POS_RUNE_SOURCES): return true
	return false

func _el1_has_neg_rune(side: int) -> bool:
	for holder: Dictionary in heroes:
		for e: Dictionary in holder.enchantments:
			if int(e.owner) == side and String(e.card) in (EL2_NEG_RUNE_SOURCES if profile.id == "el2" else EL1_NEG_RUNE_SOURCES): return true
	return false

func _begin_attack(draw_card: bool) -> void:
	turn_serial += 1
	var hero: Dictionary = heroes[attacker]
	hero.turns += 1
	var disturbance := ELHeroEffects.disturbance(profile.id, hero, heroes[1 - attacker], gift_turns(attacker))
	if disturbance > 0:
		_emit({"kind": "disturbance", "side": attacker, "amount": disturbance})
		_raw_hero_damage = true
		_damage(attacker, disturbance)
		_raw_hero_damage = false
		_check_winner()
		if phase == Phase.FINISHED:
			changed.emit()
			return
	if ELHeroEffects.regenerates(hero) and hero.health < hero.maximum:
		hero.health += 1
		_emit({"kind": "heal", "target": attacker, "amount": 1, "skill": "REGN"})
	for e: Dictionary in hero.enchantments: e.used = false
	# EL1 - queues PosRune once at the acting hero when
	# player var 2 is nonzero, before its separate NegRune/Stasis checks.
	if profile.id in ["el1", "el2"] and _el1_has_pos_rune(attacker):
		_emit({"kind": "turn_pos_rune", "side": attacker})
	# EL1 - queues NegRune once at the active hero if
	# caster/player variable 3 is nonzero; this precedes Stasis.
	if profile.id in ["el1", "el2"] and _el1_has_neg_rune(attacker):
		_emit({"kind": "turn_neg_rune", "side": attacker})
	# EL1 checks global state modifier 4 (Stasis) and plays
	# BlueStasis at the active hero once, before graveyard/untap/draw.
	# EL2 checks the same global modifier (site).
	if profile.id in ["el1", "el2"] and global_enchantment_count("STSI") > 0:
		_emit({"kind": "turn_stasis", "side": attacker})
	# EL2 - runs the same per-creature loop.
	if profile.id in ["el1", "el2"]:
		# - visits each active creature's positive and
		# negative counters (creature variables 0 and 1), in that order,
		# and queues a rune at the creature while one is positive. Only the
		# enchantments in the setter census write them (EL1, EL2
		# ); other stat changes, Bless included, leave them alone.
		var pos_sources: Array = EL2_CREATURE_POS_RUNE_SOURCES if profile.id == "el2" else EL1_CREATURE_POS_RUNE_SOURCES
		var neg_sources: Array = EL2_CREATURE_NEG_RUNE_SOURCES if profile.id == "el2" else EL1_CREATURE_NEG_RUNE_SOURCES
		for c: Dictionary in army(attacker):
			if profile.id == "el1" and in_plane(int(c.id)): continue
			var positive := false
			var negative := false
			for e: Dictionary in c.enchantments:
				positive = positive or String(e.card) in pos_sources
				negative = negative or String(e.card) in neg_sources
			# A hero-held water link still marks its creature (creature variable 0).
			positive = positive or not water_links(int(c.id)).is_empty()
			if positive: _emit({"kind": "turn_creature_pos_rune", "target": int(c.id)})
			if negative: _emit({"kind": "turn_creature_neg_rune", "target": int(c.id)})
	if profile.id == "el1":
		# The four original immortal dragons return before ETTI and the draw.
		# The original loop compares concrete card IDs, not the Race text field.
		var index := 0
		while index < hero.grave.size():
			if str(hero.grave[index]) not in EL1_IMMORTAL_DRAGONS:
				index += 1
				continue
			var dragon: String = hero.grave[index]
			hero.grave.remove_at(index)
			_give_card(attacker, dragon)
			_emit({"kind": "return_card", "side": attacker, "card": dragon})
	# Eternal tide: a random graveyard creature card returns to the hand.
	if not hero.grave.is_empty() and ELSpecs.roll(self, attacker, "ETTI") > 0:
		var index := random_index(hero.grave.size())
		var returned: String = hero.grave[index]
		hero.grave.remove_at(index)
		# EL1 -: the ETTI card arrives as a DrawSpell (front).
		_give_card(attacker, returned, -1, true)
		_emit({"kind": "return_card", "side": attacker, "card": returned})
	# Original EL1 -: the selected CRDS event rolls
	# once in ten when the acting army is nonempty. A hit picks one of
	# that side's creatures and deals exactly its remaining toughness as
	# ordinary damage (so NoAffect/Lifeguard/regeneration still apply).
	# Battle opening, not this subsequent-turn hook.
	if profile.id == "el1" and turn_serial > 1 and str(setup.get("combat_event", "")) == "CRDS":
		var eligible: Array[Dictionary] = army(attacker)
		if not eligible.is_empty() and random_index(10) == 5:
			var victim: int = int(eligible[random_index(eligible.size())].id)
			if creatures.has(victim):
				_damage(victim, maxi(0, int(creatures[victim].toughness) - int(creatures[victim].damage)))
	# Non-Pale creatures sent to the plane return at their original owner's turn.
	for c: Dictionary in creatures.values():
		if in_plane(c.id) and not pale(c.id) and origin(c.id) == attacker: plane_change(c.id, false)
	var thick_air := global_enchantment_count("CNAR") > 0
	var flood := global_enchantment_count("FLOD") > 0
	for c: Dictionary in army(attacker):
		if in_plane(c.id):
			# Pale aspect ignores freezes and smoke, not the creature's own no-untap.
			c.sick = false
			if c.has("ability_used"): c.ability_used.clear()
			if not enfeebled(c.id) and _enchantment_count(c.id, "IMMB") == 0 and not has_flag(c.id, "NoUntap"): c.resting = false
			continue
		# Condensed air holds flyers and a flood holds the rest: no recovery,
		# sickness or ability reset.
		# Flood mastery lets a held ground creature recover anyway.
		if (thick_air or flood) and has_flag(c.id, "Fly") == thick_air and not has_flag(c.id, "NoAffect"):
			if thick_air or ELSpecs.roll(self, attacker, "UFLP") == 0: continue
		c.sick = false
		if c.has("ability_used"): c.ability_used.clear()
		# Smoke keeps tapped creatures tapped, except unaffected ones.
		var smoked := global_enchantment_count("SMOK") > 0 and not has_flag(c.id, "NoAffect")
		# Smoke mastery: a tapped creature may recover anyway.
		if smoked and c.resting and ELSpecs.roll(self, attacker, "RSMP") > 0: smoked = false
		if not enfeebled(c.id) and _enchantment_count(c.id, "IMMB") == 0 and not has_flag(c.id, "NoUntap") and not smoked: c.resting = false
	_pale_warp()
	if draw_card: _draw(attacker)
	if ELHeroEffects.extra_draw(hero) and _draw(attacker):
		_emit({"kind": "skill", "side": attacker, "skill": "CONC"})
	# First-game enlightenment: every copy gives both heroes an extra draw.
	var enlightenment := _enchantment_count(0, "ENLH") + _enchantment_count(1, "ENLH")
	for i in enlightenment: _draw(attacker)
	# The original starts one Draw visual for a positive additional-draw count,
	# after those draws and before the separate QIHN specialisation draw.
	if profile.id == "el1" and enlightenment > 0: _combat_effect("ENLH", attacker, attacker)
	if ELSpecs.roll(self, attacker, "QIHN") > 0: _draw(attacker)
	var income: Dictionary = profile.table("CombatManaIncome")
	# The final ether-income row is not applied in either edition.
	var row: Dictionary = income.get(str(hero.turns), {}) if int(hero.turns) < income.size() else {}
	var stasis := global_enchantment_count("STSI") > 0
	if not stasis or profile.id == "el1": hero.channels += int(row.get("Level%d" % hero.level, 0))
	if not stasis: hero.mana = hero.channels * (1 + global_enchantment_count("MNVR"))
	_sync_attacks()
	_turn_enchantments(true)
	_check_winner()
	if phase == Phase.FINISHED:
		changed.emit()
		return
	if scripts != null:
		# The turn-start hook is the last step; its actions resolve before the hero acts.
		scripts.turn_start(attacker, int(hero.turns))
		_check_winner()
		_drain_scripts()
		if phase == Phase.FINISHED:
			changed.emit()
			return
	_emit({"kind": "phase", "side": attacker, "phase": "attack", "round": round_number, "ether": hero.mana})
	changed.emit()

## Second game: each Gift on a creature the hero controls brings its ether
## disturbance two turns earlier.
func gift_turns(side: int) -> int:
	if profile.id != "el2": return 0
	var count := 0
	for c: Dictionary in army(side): count += _enchantment_count(c.id, "GIFT")
	return 2 * count

## `reject` ("creatures" or "spells") picks normally but keeps nothing of that class.
func _draw(side: int, reject := "") -> bool:
	var hero: Dictionary = heroes[side]
	var slot := -1
	var card := ""
	if profile.id == "el2":
		slot = ELSpellCharges.choose(hero, random_index)
		if slot < 0: return false
		card = hero.deck[slot]
	else:
		var selected := ELSpellCharges.choose_el1(hero, profile.table("CombatSpells"), random_index)
		if selected.is_empty(): return false
		card = selected.card
		slot = selected.slot
	if not reject.is_empty() and (profile.table("CombatSpells")[card].get("Class") == "Creature") == (reject == "creatures"): return false
	_give_card(side, card, slot, true)
	_emit({"kind": "draw", "side": side, "card": card})
	return true

## `front`: the card shows at the left of the hand rail. Drawn cards arrive at the front;
## returned cards normally arrive at the back. First-game ETTI and JRRG returns also go
## to the front. The array keeps arrival order; positional rules such as random discards,
## Curse and the turn-end trim use the rail order.
func _give_card(side: int, card: String, slot := -1, front := false) -> void:
	var hero: Dictionary = heroes[side]
	var keys := _hand_view(hero)
	hero.hand.append(card)
	hero.hand_slots.append(slot)
	if hero.has("hand_ids"):
		hero.hand_ids.append(next_card)
		next_card += 1
	var key := 0
	if not keys.is_empty(): key = (int(keys.min()) - 1) if front else (int(keys.max()) + 1)
	keys.append(key)
	hero.hand_view = keys

func _take_card(side: int, index: int) -> String:
	var hero: Dictionary = heroes[side]
	var keys := _hand_view(hero)
	var card: String = hero.hand[index]
	hero.hand.remove_at(index)
	hero.hand_slots.remove_at(index)
	if hero.has("hand_ids"): hero.hand_ids.remove_at(index)
	keys.remove_at(index)
	hero.hand_view = keys
	return card

## Display keys parallel to the hand; array order when missing or out of step
## (older saves, prepared states that edit the hand directly).
static func _hand_view(hero: Dictionary) -> Array:
	var keys: Variant = hero.get("hand_view")
	if keys is Array and keys.size() == hero.hand.size(): return keys
	var fresh: Array = []
	for i in hero.hand.size(): fresh.append(i)
	return fresh

## Hand indices in the order the hand rail shows them, left to right.
func hand_display(side: int) -> Array[int]:
	var keys := _hand_view(heroes[side])
	var order: Array[int] = []
	for i in keys.size(): order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return int(keys[a]) < int(keys[b]) or (int(keys[a]) == int(keys[b]) and a < b))
	return order

## Discards up to `count` random cards, one random choice per card.
func _discard_random(side: int, count: int) -> void:
	for i in count:
		if heroes[side].hand.is_empty(): return
		_emit({"kind": "discard", "side": side, "card": _take_card(side, hand_display(side)[random_index(heroes[side].hand.size())])})

func hand_uses(side: int, index: int) -> int:
	var slot: int = heroes[side].hand_slots[index]
	return int(heroes[side].spell_uses[slot]) if slot >= 0 else -1

func random_index(count: int) -> int:
	rng_state = (rng_state * 0x343fd + 0x269ec3) & 0xffffffff
	return ((rng_state >> 16) & 0x7fff) % maxi(1, count)

func _summon(side: int, card: String) -> void:
	var banner_before := _war_banner_bonuses()
	var data: Dictionary = profile.table("CombatCreatures")[card]
	var flags := ELCatalog.flags(data)
	var creature := {"id": next_id, "owner": side, "card": card, "power": int(data.Power),
		"toughness": int(data.Toughness), "damage": 0, "resting": _enchantment_count(1 - side, "HOAM") > 0 and not (profile.id == "el2" and flags.has("NoAffect")), "sick": not flags.has("NSS"),
		"flying": flags.has("Fly"), "flags": flags, "enchantments": [], "regenerated": false}
	if profile.id == "el2":
		# Pale creatures arrive in pale aspect (the first spell-jammer does not);
		# prime watch sends every other affected arrival there too.
		if (flags.has("Outerplanar") and card != "OSJ1") or (global_enchantment_count("PRWT") > 0 and not flags.has("NoAffect")): creature.plane = true
	creatures[next_id] = creature
	next_id += 1
	if scripts != null:
		# Summon hooks see the new creature before its stats settle and may edit its base.
		if scripts.search_only: scripts.bind(self)
		scripts.summoned(side, card, int(creature.id))
		if not creatures.has(creature.id): return
	if not ELCatalog.creature_aura(profile, card).is_empty() or global_enchantment_count("WRBN") > 0: _refresh_armies()
	else: _refresh_stats(creature)
	_emit({"kind": "summon", "creature": creature.duplicate(true)})
	_aura_arrival_cues(creature)
	# Summon first: the new model must exist before any targeted aura effect.
	_war_banner_reactions(banner_before)
	if creatures.has(creature.id) and creature.damage >= creature.toughness: _lethal(creature.id)
	if card == "WKHR":
		# The walking horror's arrival hurts every other creature, each hit
		# with BlackDamage at that creature (EL1, EL2); its
		# death wave has no effect of its own.
		for other: Dictionary in creatures.values():
			if other.id != creature.id and creatures.has(other.id):
				if profile.id in ["el1", "el2"]: _emit({"kind": "walking_horror_hit", "target": int(other.id)})
				_trigger_damage(card, other.id, 3)

func _return_buried_creatures(side: int) -> void:
	var grave: Array = heroes[side].grave
	var first := profile.id == "el1"
	var rising: Array = ELCatalog.FIRST_RISING if first else ELCatalog.FIRST_RISING.filter(func(card: String) -> bool: return card in ELCatalog.RISING or ELCatalog.shared(profile, card))
	var index := 0
	while index < grave.size() and (first or army(side).size() < 10):
		if grave[index] in rising and grave.size() - index - 1 >= 3:
			var card: String = grave[index]
			grave.remove_at(index)
			# The first game removes the card even when a full army leaves it nowhere to go.
			if army(side).size() < 10: _summon(side, card)
			else: _emit({"kind": "grave_removed", "side": side, "card": card})
			# Original processing restarts at the oldest entry after each return.
			index = 0
		else: index += 1

func _sync_attacks() -> void:
	if phase != Phase.ATTACK: return
	for id: int in attacks.duplicate():
		if not can_attack(id, true): attacks.erase(id)
	# Original compulsory assignment is suppressed while attacking has a cost.
	if global_enchantment_count("LSDS") > 0: return
	for c: Dictionary in army(attacker):
		if has_flag(c.id, "Berserk") and can_attack(c.id) and not attacks.has(c.id) and (not has_flag(c.id, "TeamAttack") or _team_partner(c.id)):
			attacks.append(c.id)

func _resolve_attacks() -> void:
	var poisoned: Array[int] = []
	var regenerated_before: Array = creatures.keys().filter(func(i: int) -> bool: return creatures[i].regenerated)
	for id in attacks.duplicate():
		if not creatures.has(id): continue
		var attack: Dictionary = creatures[id]
		# First game: an attacker that regenerated in the defence phase stays declared (it can still be
		# blocked) but neither fights nor rests.
		if profile.id == "el1" and attack.regenerated: continue
		attack.resting = not has_flag(id, "Restless")
		var defenders: Array[int] = []
		# A declared blocker rested afterwards still blocks.
		for blocker: int in blocks:
			if blocks[blocker] == id and creatures.has(blocker): defenders.append(blocker)
		# Kobold and aviak masteries double an attacker's whole damage pool.
		var remaining: int = maxi(0, attack.power) * (2 if _doubles(id) else 1)
		var walled := false
		var gazed := 0
		if defenders.is_empty():
			_strike(id, 1 - attacker, remaining, poisoned)
		else:
			for blocker in defenders:
				if not creatures.has(id) or attack.regenerated: break
				if not creatures.has(blocker): continue
				# Evil eye mastery: a beholder destroys its combat opponent before damage.
				if race(id) == "Beholder" and not (profile.id == "el2" and has_flag(blocker, "NoAffect")) and ELSpecs.roll(self, int(attack.owner), "GBHD") > 0:
					_combat_effect("GBHD", id, blocker)
					_destroy(blocker)
					gazed += 1
					continue
				if race(blocker) == "Beholder" and not (profile.id == "el2" and has_flag(id, "NoAffect")) and ELSpecs.roll(self, int(creatures[blocker].owner), "GBHD") > 0:
					_combat_effect("GBHD", blocker, id)
					_destroy(id)
					remaining = 0
					break
				# Wall masteries: stone walls doom ground attackers, air walls flyers.
				var wall: String = creatures[blocker].card
				if (wall in ["WLBR", "SLWL", "RKWL"] and not has_flag(id, "Fly") and ELSpecs.roll(self, int(creatures[blocker].owner), "RWSW") > 0) or (wall in ["WLAR", "WLWD", "WLBZ"] and has_flag(id, "Fly") and ELSpecs.roll(self, int(creatures[blocker].owner), "UWAW") > 0): walled = true
				# A first-striking blocker gives no counter-strike.
				var defender_first := has_flag(blocker, "FS") and not has_flag(id, "FS")
				var pre := defender_first
				# Hornet mastery: a hornet's hero may cancel the blocker's first strike, or win a first strike
				# for a blocking hornet; the blocker's hero rolls before the attacker's.
				if defender_first: pre = not _hornet(id)
				else: pre = _hornet(blocker) and not _hornet(id)
				if pre:
					_strike(blocker, id, _blocker_damage(blocker), poisoned)
					if not creatures.has(id) or attack.regenerated or in_plane(id): break
					if _witch_wall(blocker, id):
						remaining = 0
						break
				# The allotment covers what Stone Skin will absorb, so a trampler carries only the rest over.
				var dealt := mini(remaining, maxi(0, creatures[blocker].toughness - creatures[blocker].damage) + 2 * _enchantment_count(blocker, "STSK"))
				remaining -= dealt
				_strike(id, blocker, dealt, poisoned)
				# A blocker that dissipated into the plane has left combat.
				if not defender_first and creatures.has(blocker) and not creatures[blocker].regenerated and not in_plane(blocker):
					_strike(blocker, id, _blocker_damage(blocker), poisoned)
					if _witch_wall(blocker, id):
						remaining = 0
						break
			# A beholder whose gaze destroyed every blocker hits the hero with its whole damage; one that
			# fought any blocker does not.
			if gazed == defenders.size() and creatures.has(id) and not attack.regenerated and remaining > 0:
				_strike(id, 1 - attacker, remaining, poisoned)
			elif creatures.has(id) and not attack.regenerated and has_flag(id, "Trample") and remaining > 0:
				_strike(id, 1 - attacker, remaining, poisoned)
		if walled and creatures.has(id): _damage(id, 1000000)
		# Rest is settled after the attacker's own fight: a creature aura's Restless (OREL, MOTI) lost
		# because the attacker killed its source in that fight, even in the ordinary exchange, leaves the
		# attacker resting.
		if creatures.has(id) and not attack.resting and not has_flag(id, "Restless"): attack.resting = true
		# Cutter and gibberling masteries: a surviving attacker stays ready.
		if creatures.has(id) and attack.resting and race(id) in ["Cutter", "Gibberling"] and ELSpecs.roll(self, int(attack.owner), "BCTR" if race(id) == "Cutter" else "UOCR") > 0: attack.resting = false
		_check_winner()
		if phase == Phase.FINISHED: break
	if scripts != null and not poisoned.is_empty(): scripts.dispatch("CHook_OnVisualStartMeleeDestroyFlag", [])
	for id: int in poisoned:
		# A creature that regenerated during this combat is already saved.
		if creatures.has(id) and not (creatures[id].regenerated and not regenerated_before.has(id)): _ability_lethal(id)
	if scripts != null and not poisoned.is_empty(): scripts.dispatch("CHook_OnVisualFinishMeleeDestroyFlag", [])

## Presentation of a combat strike's creature power (first game): `key` names
## the power (a mastery code or a strike property), drawn from `source` to `target`.
func _combat_effect(key: String, source: int, target: int) -> void:
	if profile.id != "el1": return
	var side := source if source < 2 else int(entity(source).get("owner", -1))
	_emit({"kind": "combat_ability", "key": key, "source": source, "target": target, "side": side})

func _doubles(id: int) -> bool:
	var kind := race(id)
	if kind == "Kobold": return ELSpecs.roll(self, int(creatures[id].owner), "RKBC") > 0
	if kind == "Aviak": return ELSpecs.roll(self, int(creatures[id].owner), "UAVC") > 0
	return false

func _blocker_damage(blocker: int) -> int:
	if not creatures.has(blocker): return 0
	return maxi(0, int(creatures[blocker].power)) * (2 if _doubles(blocker) else 1)

## Witch mastery on a shadow wall's strike: the second game enfeebles the
## attacker and ends its combat; the first taps it for good and combat goes on.
func _witch_wall(blocker: int, id: int) -> bool:
	if not creatures.has(blocker) or creatures[blocker].card != "WLIL" or not creatures.has(id): return false
	if ELSpecs.roll(self, int(creatures[blocker].owner), "BWIT") == 0: return false
	if profile.id == "el2":
		_enchant("ENFL", int(creatures[blocker].owner), id, ELCatalog.rule(profile, "ENFL"))
		return true
	creatures[id].resting = true
	_mark(id, "BWIT", 0, 0, {"fixed": true})
	_combat_effect("BWIT", blocker, id)
	return false

func _strike(source: int, target: int, amount: int, poisoned: Array[int]) -> void:
	var incoming := amount
	# Stone skin lowers physical damage by 2 per copy.
	if not entity(target).is_empty() and _enchantment_count(target, "STSK") > 0:
		if incoming > 0: _emit({"kind": "stoneskin", "target": target})
		amount -= 2 * _enchantment_count(target, "STSK")
	if amount <= 0:
		# The original queues the material-hit sound before Stone Skin reduces
		# damage. An absorbed, positive-power attack still plays its strike.
		if incoming > 0: _emit({"kind": "strike", "from": source, "to": target})
		return
	var destroys := has_flag(source, "Destroy")
	var disenchants := has_flag(source, "Disenchant")
	var drains := has_flag(source, "Lifetap")
	var card: String = creatures[source].card if creatures.has(source) else ""
	var owner: int = creatures[source].owner if creatures.has(source) else -1
	var before := int(heroes[target].health) if target in [0, 1] else 0
	_emit({"kind": "strike", "from": source, "to": target})
	# Combat damage marks a creature; Velos survive their turn end with this mark.
	if creatures.has(target): creatures[target].hit = true
	var flyer := has_flag(target, "Fly")
	# The fire elemental's burn lands before the lethal check, so it blocks regeneration.
	if card == "FREL" and creatures.has(target) and (profile.id == "el1" or amount > 0): _mark(target, "FREL", 0, 0, {"fixed": true})
	# Second-game snake venom lowers health before the lethal check, so a creature it reduces to
	# nothing cannot regenerate.
	var venom_first := card == "LASN" and profile.id == "el2" and creatures.has(target)
	if venom_first: _mark(target, "LASN", -1, -1, {"fixed": true, "lethal": true})
	# First game: a disenchanting strike strips a creature before its (already allotted) damage is
	# checked. The second game strips after.
	var stripped_first: bool = profile.id == "el1" and disenchants and creatures.has(target) and not creatures[target].enchantments.is_empty()
	if stripped_first:
		_combat_effect("Disenchant", source, target)
		for e: Dictionary in creatures[target].enchantments.duplicate(): _remove_enchantment(target, e.id)
	# A hit its hero redirects onto a creature robs no cards.
	var shielded: bool = target in [0, 1] and army(target).any(func(x: Dictionary) -> bool: return _enchantment_count(int(x.id), "REDR") > 0)
	var dealt := _damage(target, amount, true)
	if venom_first and creatures.has(target) and creatures[target].damage >= creatures[target].toughness: _ability_lethal(target)
	if destroys and creatures.has(target) and not poisoned.has(target): poisoned.append(target)
	if card in ELCatalog.MECHOS and creatures.has(target) and race(target) != "Wall" and not poisoned.has(target): poisoned.append(target)
	# The hellfire wall's whirl destroys flyers it damages, like poison.
	if card == "WLIF" and flyer and creatures.has(target) and not poisoned.has(target): poisoned.append(target)
	if card == "LASN" and not venom_first and creatures.has(target):
		_mark(target, "LASN", -1, -1, {"fixed": true, "lethal": true})
		if creatures[target].damage >= creatures[target].toughness: _ability_lethal(target)
	var robbed := 0
	if target in [0, 1] and creatures.has(source):
		if card == "GRSN": _mark(source, "GRSN", 1, 1, {"fixed": true})
		# Venom is priced like its token row: free in the first game, 1 in the second. The second game's
		# venom is its own support card.
		if card in ["TRSN", "SWSN"]: _mark(target, ({"TRSN": "ETRS", "SWSN": "ESWS"}[card] if profile.id == "el2" else card), 0, 0, {"owner": owner, "price": 1 if profile.id == "el2" else 0})
		for flag: String in creatures[source].flags:
			if flag.begins_with("Discard("): robbed += int(flag.trim_prefix("Discard(").trim_suffix(")"))
		for e: Dictionary in creatures[source].enchantments: robbed += ELCatalog.granted_discard(profile, e.card)
		# Lamia and orc masteries: one more discard on a hit.
		var kind := race(source)
		if dealt > 0 and kind in ["Lamia", "Orc"] and ELSpecs.roll(self, owner, "UMTD" if kind == "Lamia" else "RORT") > 0: robbed += 1
		if shielded: robbed = 0
		# Snake mastery envenoms the hero.
		if dealt > 0 and kind == "Snake" and ELSpecs.roll(self, owner, "GSNV") > 0: _mark(target, "ENVM", 0, 0, {"owner": owner})
		# EL1 - queues DrainLife before +
		# processes the discard and Target/Discard. Keep EL2's prior order
		# until its own combat callback is confirmed independently.
		if profile.id != "el1": _discard_on_hit(source, target, robbed)
	if target in [0, 1]:
		# Life drain heals by the damage actually taken, without a maximum.
		if drains and owner >= 0 and before > 0 and dealt > 0:
			var gained := mini(dealt, before)
			heroes[owner].health += gained
			_combat_effect("Lifetap", target, owner)
			_emit({"kind": "heal", "target": owner, "amount": gained, "source": source})
		if profile.id == "el1": _discard_on_hit(source, target, robbed)
		# Fighter, treant and bat masteries: an attacker's hit on the hero heals its controller.
		var healer := {"Fighter": "BFGL", "Treant": "GTRL", "Bat": "RBTD"}
		if not drains and owner >= 0 and dealt > 0 and attacks.has(source) and healer.has(race(source)) and ELSpecs.roll(self, owner, healer[race(source)]) > 0:
			heroes[owner].health += dealt
			_emit({"kind": "heal", "target": owner, "amount": dealt, "source": source})
		if card in ELCatalog.STINGERS and creatures.has(source) and not poisoned.has(source): poisoned.append(source)
	# Pteros mastery: a strike strips the enchantments the target's own hero cast.
	var stripped := false
	if card in ["PTRS", "RFPT"] and not entity(target).is_empty() and ELSpecs.roll(self, owner, "BPTD") > 0:
		stripped = true
		_combat_effect("BPTD", source, target)
		var controller := target if target < 2 else int(creatures[target].owner)
		for e: Dictionary in entity(target).enchantments.duplicate():
			if int(e.owner) == controller and not entity(target).is_empty(): _remove_enchantment(target, e.id)
	if disenchants and not entity(target).is_empty() and not stripped_first:
		if not stripped and not entity(target).enchantments.is_empty(): _combat_effect("Disenchant", source, target)
		for e: Dictionary in entity(target).enchantments.duplicate(): _remove_enchantment(target, e.id)

## Original EL1 places the successful life-drain cue before the discard
## callback. No change to discard amount, selection RNG or authored effects.
func _discard_on_hit(source: int, target: int, count: int) -> void:
	if count <= 0: return
	_combat_effect("Discard", source, target)
	for discard in count:
		if heroes[target].hand.is_empty(): break
		var dropped := _take_card(target, hand_display(target)[random_index(heroes[target].hand.size())])
		_emit({"kind": "discard", "side": target, "card": dropped})

## Returns the damage that landed: zero when a hero's feedback redirected it or
## an unaffected creature ignored it. Only combat can hurt unaffected creatures.
## `bypass` reaches creatures in the Colourless Plane; `destroying` (lethal
## destroy damage) ignores the energy barrier.
func _damage(target: int, amount: int, combat := false, no_regeneration := false, linked := true, bypass := false, destroying := false) -> int:
	if target in [0, 1]: return _hurt_hero(target, amount, false, combat)
	if not creatures.has(target): return 0
	if not combat and has_flag(target, "NoAffect"): return 0
	if in_plane(target) and not bypass: return 0
	# Energy barrier: 3 less non-combat damage per copy; lifeguard negates one hit.
	if not combat and not destroying and _enchantment_count(target, "ENBR") > 0:
		var softened := amount > 0
		amount -= 3 * _enchantment_count(target, "ENBR")
		if softened: _emit({"kind": "barrier", "target": target, "amount": amount})
	# EL2's creature-damage routine checks Lifeguard after Energy Barrier,
	# even when the barrier absorbs the full hit (before).
	if profile.id == "el2" and _lifeguard(target): return 0
	if amount <= 0: return 0
	if profile.id != "el2" and _lifeguard(target): return 0
	# Pain link: the controller takes the same damage once per copy (never redirected); combat damage
	# only up to the creature's remaining toughness.
	var pain := amount if not combat else mini(amount, maxi(0, int(creatures[target].toughness) - int(creatures[target].damage)))
	creatures[target].damage += amount
	# Any damage marks the creature; Velos survive their turn end with this mark.
	if amount > 0: creatures[target].hit = true
	_emit({"kind": "damage", "target": target, "amount": amount})
	if linked and pain > 0:
		for copy in _enchantment_count(target, "PALN"): _hurt_hero(int(creatures[target].owner), pain, true)
	if not creatures.has(target): return amount
	if creatures[target].damage < creatures[target].toughness: return amount
	var victim: Dictionary = creatures[target]
	var regeneration := regeneration_cost(target)
	var free_regeneration := false
	if no_regeneration or has_flag(target, "NoRegen"): regeneration = 0
	elif (race(target) == "Rat" and ELSpecs.roll(self, int(victim.owner), "RRTR") > 0) or (race(target) == "Fingus" and ELSpecs.roll(self, int(victim.owner), "GFNR") > 0):
		# Rat and fingus masteries regenerate for nothing, even without the ability.
		free_regeneration = true
		regeneration = 0
	var dissipates: bool = profile.id == "el2" and pale(target) and not in_plane(target) and victim.toughness > 0 and not _plane_guard
	if (free_regeneration or regeneration > 0) and not recovery_blocked(victim.owner) and victim.toughness > 0 and heroes[victim.owner].mana >= regeneration:
		# Complicity: every regeneration heals each hero 5 per copy it holds.
		for side in 2:
			var gain := 5 * _enchantment_count(side, "COPL")
			if gain > 0:
				heroes[side].health += gain
				_emit({"kind": "heal", "target": side, "amount": gain, "card": "COPL"})
		_spend_ether(victim.owner, regeneration)
		victim.damage = 0
		victim.regenerated = true
		if profile.id == "el2": _unassign(target)
		_emit({"kind": "regenerate", "target": target, "cost": regeneration})
	elif dissipates and plane_change(target, true):
		# A bright Pale creature dissipates instead of dying: healed and tapped.
		victim.damage = 0
		victim.resting = true
		_emit({"kind": "dissipate", "target": target})
	else:
		_kill(target)
	return amount

## Lifeguard negates one damage instance, then that enchantment goes.
func _lifeguard(target: int) -> bool:
	for e: Dictionary in entity(target).get("enchantments", []):
		if e.card == "LFGR":
			_emit({"kind": "lifeguard", "target": target})
			_remove_enchantment(target, int(e.id))
			return true
	return false

## Printed regeneration, or granted regeneration (self repair, vitality): the
## cheapest positive cost applies.
func regeneration_cost(id: int) -> int:
	var costs: Array[int] = []
	var c: Dictionary = creatures[id]
	for flag: String in c.flags:
		if flag.begins_with("Regen("): costs.append(int(flag.trim_prefix("Regen(").trim_suffix(")")))
	for e: Dictionary in c.enchantments:
		if ELCatalog.GRANTED_REGENERATION.has(e.card): costs.append(int(ELCatalog.GRANTED_REGENERATION[e.card]))
	for e: Dictionary in army_auras(c):
		if ELCatalog.ARMY_AURAS[e.card].has("regeneration"): costs.append(int(ELCatalog.ARMY_AURAS[e.card].regeneration))
	var best := 0
	for value: int in costs:
		if value > 0 and (best == 0 or value < best): best = value
	return best

## Feedback (first game): the enchanted hero takes nothing; the opponent takes
## the full amount once per copy while it still has health.
func _hurt_hero(target: int, amount: int, redirected := false, combat := false) -> int:
	# Script damage kinds: 1 skips redirection and feedback; 2 also skips the
	# barrier, lifeguard and protective specialisations (p4).
	var kind := _hero_damage_kind
	_hero_damage_kind = 0
	if kind >= 1: redirected = true
	if amount > 0 and kind < 2:
		# Second-game protections apply before redirection.
		if not combat and _enchantment_count(target, "ENBR") > 0:
			amount -= 3 * _enchantment_count(target, "ENBR")
			_emit({"kind": "barrier", "target": target, "amount": amount})
		if amount <= 0 or _lifeguard(target): return 0
		if not _raw_hero_damage:
			# Specialisations, one roll each in order: ancient magic (spells) or iron
			# skin (combat), then dragon or lord skin negate the hit; a backlash
			# answers it with 1 to the enemy hero and each enemy creature.
			if ELSpecs.roll(self, target, "IRSK" if combat else "ATMF") > 0: return 0
			if ELSpecs.roll(self, target, "DRSK") + ELSpecs.roll(self, target, "DRSL") > 0: return 0
			if ELSpecs.roll(self, target, "FRBD" if combat else "WRBD") > 0: _backlash(target)
	if not redirected and amount > 0:
		# Redirection: the hero's own redirect creatures take the damage times their copies.
		var shields: Array[int] = []
		for c: Dictionary in army(target):
			if _enchantment_count(c.id, "REDR") > 0: shields.append(int(c.id))
		if not shields.is_empty():
			_emit({"kind": "redirect", "target": target, "amount": amount, "creatures": shields})
			for id: int in shields:
				if creatures.has(id): _damage(id, amount * _enchantment_count(id, "REDR"), false, false, false)
			_camera_cue("REDR", target, "sorcery", shields.filter(func(id: int) -> bool: return creatures.has(id)))
			return 0
	var copies := _enchantment_count(target, "FDBK") + _enchantment_count(target, "LNRD") if not redirected and amount > 0 else 0
	if copies > 0:
		_emit({"kind": "feedback", "target": target, "amount": amount})
		for copy in copies:
			if heroes[1 - target].health < 1: break
			_hurt_hero(1 - target, amount, true)
			_camera_cue("FDBK", target, "sorcery", [target, 1 - target])
	# Ethereal chain mirrors the damage to the opponent: once per copy in the
	# first game, once in all in the second.
	var mirrors := _enchantment_count(target, "ETCH") if not redirected and amount > 0 else 0
	if profile.id == "el2": mirrors = mini(mirrors, 1)
	for copy in mirrors:
		if heroes[1 - target].health < 1: break
		# EL2 – starts RedDamage at the opposite hero
		# before applying Ethereal Chain's mirrored hit.
		if profile.id == "el2":
			_emit({"kind": "chain_mirror", "source": target, "target": 1 - target, "amount": amount})
		_hurt_hero(1 - target, amount, true)
		_camera_cue("ETCH", target, "sorcery", [target, 1 - target])
	if copies > 0: return 0
	heroes[target].health = maxi(0, heroes[target].health - amount)
	_emit({"kind": "damage", "target": target, "amount": amount})
	# Revival: a lethal hit halves the maximum health and refills to it (repeatable).
	if heroes[target].health <= 0 and int(heroes[target].maximum) > 1 and ELSpecs.roll(self, target, "RVVE") > 0:
		heroes[target].maximum = int(heroes[target].maximum) / 2
		heroes[target].health = heroes[target].maximum
		_emit({"kind": "heal", "target": target, "amount": heroes[target].health, "spec": "RVVE"})
	return amount

## ExAddPlayerDamage: immediate non-combat hero damage of kind 0 (full chain),
## 1 (no redirection or feedback) or 2 (raw), then the end check.
func script_damage(side: int, amount: int, kind: int) -> void:
	if amount <= 0: return
	_hero_damage_kind = kind
	_hurt_hero(side, amount)
	_hero_damage_kind = 0
	_check_winner()

## ExSetManalinks: channels are set at once (at least zero); ether is kept.
func script_channels(side: int, value: int) -> void:
	var delta := value - int(heroes[side].channels)
	heroes[side].channels = value
	if delta != 0: _emit({"kind": "channels", "side": side, "amount": delta, "script": true})

func _backlash(side: int) -> void:
	var enemy := 1 - side
	if heroes[enemy].health > 0:
		_raw_hero_damage = true
		_hurt_hero(enemy, 1, true)
		_raw_hero_damage = false
	for c: Dictionary in army(enemy):
		if creatures.has(c.id): _damage(c.id, 1)

## Destruction is ordinary damage equal to the remaining toughness.
func _destroy(id: int, no_regeneration := false) -> void:
	if creatures.has(id): _damage(id, maxi(1, int(creatures[id].toughness) - int(creatures[id].damage)), false, no_regeneration, true, false, true)

func _kill(id: int) -> void:
	if not creatures.has(id): return
	var dead: Dictionary = creatures[id]
	var owner := origin(id)
	var links: Array[int] = []
	for e: Dictionary in water_links(id): links.append(int(e.owner))
	heroes[owner].grave.append(dead.card)
	_remove_creature(id, "death")
	# Barbed souls: the dead creature's controller draws once per copy in play.
	for copy in global_enchantment_count("BASO"):
		_draw(int(dead.owner))
		# EL1 BarbedSoulsEnchantment left-play –
		# registers Target/Draw on this controller after the draw attempt,
		# even if the book is empty. One original callback per active copy.
		if profile.id == "el1":
			_emit({"kind": "baso_death_draw_cue", "side": int(dead.owner)})
		# EL2 slot6 – has its own creature-to-grave
		# callback: [dead] must be clear; [dead] is the
		# current controller hero. Queue Target/Draw after the real draw,
		# unconditionally even when the book is empty.
		elif profile.id == "el2":
			_emit({"kind": "baso_el2_death_draw_cue", "side": int(dead.owner)})
		_camera_cue("BASO", int(dead.owner))
	# Spiritual web: each copy heals its holder by 1 for every creature sent to a graveyard.
	for side in 2:
		var copies := _enchantment_count(side, "SPWB")
		var webs := copies
		# Web mastery: each copy may give 2.
		if webs > 0: webs += ELSpecs.roll(self, side, "GSWS", webs, webs > 0)
		if webs > 0:
			heroes[side].health += webs
			# EL2 original SpiritualWebEnchantment@ registers a
			# separate Target/GainLife after health settles for each copy,
			# even when Web mastery makes a copy heal by two.
			if profile.id == "el2":
				for copy in copies: _emit({"kind": "spwb_gain_life_cue", "side": side})
			_emit({"kind": "heal", "target": side, "amount": webs, "card": "SPWB"})
	# Water link: each link heals its caster by the creature's toughness; the
	# first caster with room in the army reanimates the creature under its control.
	var returned := false
	# The second game heals by the printed toughness, the first by the current one.
	var linked_health := int(profile.table("CombatCreatures")[dead.card].Toughness) if profile.id == "el2" else int(dead.toughness)
	for caster: int in links:
		# Link mastery: the caster gains power + toughness.
		var gain := linked_health + (maxi(0, int(dead.power)) if ELSpecs.roll(self, caster, "UWLS") > 0 else 0)
		heroes[caster].health += gain
		_emit({"kind": "heal", "target": caster, "amount": gain, "card": "WTLK"})
		# EL1 WaterLinkEnchantment creature-left –:
		# actual death-to-grave (both original exit flags clear) registers
		# one Target/GainLife at this link's owning hero after changing
		# health, before optional resurrection, even if that army is full.
		if profile.id == "el1":
			_emit({"kind": "wtlk_el1_gain_life_cue", "side": caster})
		# EL2 WaterLinkEnchantment slot6 - registers
		# Target/GainLife on the link owner after the real health award,
		# before its independent capacity/corpse-return guards. Each
		# qualifying copy queues its own effect, even when the army is full.
		elif profile.id == "el2":
			_emit({"kind": "wtlk_el2_gain_life_cue", "side": caster})
		var index: int = heroes[owner].grave.rfind(dead.card)
		if not returned and index >= 0 and army(caster).size() < 10:
			returned = true
			# The original takes the graveyard's first card, whichever it is.
			heroes[owner].grave.remove_at(0)
			_summon(caster, dead.card)

func _unassign(id: int) -> void:
	attacks.erase(id)
	blocks.erase(id)
	for blocker: int in blocks.keys():
		if blocks[blocker] == id: blocks.erase(blocker)

func _remove_creature(id: int, kind: String) -> void:
	var banner_before := _war_banner_bonuses()
	var card: String = creatures[id].card
	var owner: int = creatures[id].owner
	var true_owner := origin(id)
	var base_power := int(creatures[id].get("base", [int(profile.table("CombatCreatures")[card].Power)])[0])
	var leaving: Array = creatures[id].enchantments
	# Its water links end with it, by any route (death, exile, unsummon).
	for hero: Dictionary in heroes:
		for e: Dictionary in hero.enchantments.duplicate():
			if e.card == "WTLK" and int(e.get("link", -1)) == id:
				hero.enchantments.erase(e)
				leaving.append(e)
	creatures.erase(id)
	_unassign(id)
	# Presentation of EL1 Unsummon needs the departed creature's owner
	# after the creature has left the gameplay dictionary.
	if kind == "unsummon":
		_emit({"kind": kind, "target": id, "owner": owner})
	else:
		_emit({"kind": kind, "target": id})
	if not ELCatalog.creature_aura(profile, card).is_empty() or global_enchantment_count("WRBN") > 0: _refresh_armies()
	# Only surviving models receive the original modifier-decrease cue.
	_war_banner_reactions(banner_before)
	if scripts != null:
		# The holder's enchantments go with it, then the creature leaves (death:
		# graveyard; exile and unsummon are non-graveyard exits).
		for e: Dictionary in leaving: scripts.dispatch("CHook_OnVisualRemoveEnchantment", [e.card, float(id)])
		scripts.dispatch("CHook_OnVisualCreatureDeath", [card, float(id), null if kind == "death" else 1.0, 1.0 if kind == "unsummon" else null, float(true_owner), float(owner)])
	if card == "MOBE" and kind == "death":
		# Its hero's bees become aggressive until the end of that hero's turn.
		for bee: Dictionary in creatures.values():
			if race(bee.id) != "Bee" or int(bee.owner) != owner: continue
			if not bee.has("temporary"): bee.temporary = []
			bee.temporary.append({"id": next_enchantment, "kind": "frenzy", "flags": ["Berserk"], "until_turn_of": owner})
			next_enchantment += 1
			_refresh_stats(bee)
			_emit({"kind": "aura_cue", "card": "MOBE:death", "source": id, "target": bee.id})
		_sync_attacks()
	for e: Dictionary in leaving:
		# Bloodlessness returns to its caster's hand however the creature leaves play.
		if e.card == "RIOT":
			_give_card(int(e.owner), "RIOT")
			_camera_cue("RIOT", int(e.owner))
	if leaving.any(func(e: Dictionary) -> bool: return e.card == "ERBN"):
		for c: Dictionary in creatures.values(): _refresh_stats(c)
	if profile.id == "el2":
		# Second-game delusion, Lock Aspect and Mark of Pale return to their caster's
		# hand whenever the creature leaves play; each Lock Aspect on a Pale holder
		# then costs the holder's owner its base power.
		var pale_card := ELCatalog.flags(profile.table("CombatCreatures")[card]).has("Outerplanar")
		for e: Dictionary in leaving:
			if e.card in ["DELS", "PRBN", "ALNS"]:
				_give_card(int(e.owner), e.card)
				_camera_cue(e.card, int(e.owner))
				if e.card == "DELS":
					# EL2 DelusionEnchantment leave-play callback
					# registers Draw at its caster, not a fresh deck draw.
					_emit({"kind": "delusion_return", "side": int(e.owner)})
			if e.card == "PRBN" and pale_card and base_power > 0: _trigger_damage("PRBN", true_owner, base_power)
	if kind in ["death", "exile"]:
		# Leaving play by death or exile returns quick fix to its caster's hand and
		# releases the walking horror's final wave.
		for e: Dictionary in leaving:
			if e.card == "QKFX":
				# QuickFixEnchantment leave-play callback (EL1, EL2
				# ) starts Draw at its caster. This is a visual cue, not
				# a deck draw.
				if profile.id in ["el1", "el2"]: _emit({"kind": "quick_fix_return", "side": int(e.owner)})
				_give_card(int(e.owner), "QKFX")
				_camera_cue("QKFX", int(e.owner))
		if card == "WKHR":
			for other: Dictionary in creatures.values():
				if creatures.has(other.id): _trigger_damage(card, other.id, 3)

func _check_winner() -> void:
	if phase == Phase.FINISHED: return
	if scripts != null:
		for side in 2:
			if heroes[side].health <= 0: scripts.dispatch("CHook_OnVisualHeroDeath", [float(side)])
	if heroes[0].health <= 0 and heroes[1].health <= 0:
		winner = -1
		phase = Phase.FINISHED
		_emit({"kind": "duel_draw"})
		return
	for side in 2:
		if heroes[side].health <= 0:
			winner = 1 - side
			phase = Phase.FINISHED
			_emit({"kind": "victory", "side": winner})
			return

func _finish_action() -> void:
	_sync_attacks()
	_check_winner()
	_drain_scripts()
	changed.emit()

## Resolves queued script actions before anyone acts again.
func _drain_scripts() -> void:
	if scripts == null or scripts.draining or scripts.queue.is_empty(): return
	if phase == Phase.FINISHED:
		scripts.queue.clear()
		return
	scripts.drain()
	_sync_attacks()
	_check_winner()

func _emit(data: Dictionary) -> void:
	history.append(data)
	event.emit(data)

func _fail(message: String) -> bool:
	error = message
	return false

## An action the replay controller did not expect: ignored without a message,
## as the original's tutorial player discards it.
func _refused() -> bool:
	error = ""
	return false

## The side that took the battle's first attack phase (0 for older saves).
func first_side() -> int:
	return int(setup.get("first_side", 0))

## An independent copy for the combat opponent's lookahead: the same rules and
## random sequence, no replay gate, event listeners or history. Battle scripts
## are reduced to the lookahead layer (`ELBattleScripts.search_layer`), shared
## by every copy made from it.
## `expected_specs_on` makes specialisation rolls use their expected outcome.
func search_copy(expected_specs_on := false) -> ELDuel:
	var d := ELDuel.new()
	d.profile = profile
	d.hero_template = hero_template
	d.heroes.assign(heroes.duplicate(true))
	d.creatures = creatures.duplicate(true)
	d.attacks.assign(attacks)
	d.blocks = blocks.duplicate()
	d.phase = phase
	d.attacker = attacker
	d.round_number = round_number
	d.winner = winner
	d.next_id = next_id
	d.next_enchantment = next_enchantment
	d.turn_serial = turn_serial
	d.rng_state = rng_state
	d.setup = setup
	d.next_card = next_card
	d.expected_specs = expected_specs_on or self.expected_specs
	d.spec_expect = spec_expect
	if scripts != null: d.scripts = scripts.search_layer(d)
	return d

## Lookahead copies whose specialisation rolls use their expected outcome.
var expected_specs := false
## Sampled successes per hundred for each hero (ELSpecs.sample_expectation),
## set on a think's root copy; empty means the table chance.
var spec_expect: Array[int] = []

func snapshot() -> Dictionary:
	var result := _snapshot()
	if scripts != null: result.scripts = scripts.snapshot()
	return result

func _snapshot() -> Dictionary:
	return {"profile": profile.id, "charge_version": 2, "payment_version": 1, "round": round_number, "phase": phase, "attacker": attacker,
		"heroes": heroes.duplicate(true), "creatures": creatures.duplicate(true),
		"attacks": attacks.duplicate(), "blocks": blocks.duplicate(), "winner": winner,
		"rng": rng_state, "next_id": next_id, "next_enchantment": next_enchantment,
		"turn_serial": turn_serial, "setup": setup.duplicate(true)}

func save_file(path: String, session: Dictionary = {}) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return _fail("Cannot write the duel save.")
	file.store_string(JSON.stringify({"format": "etherlords-duel", "version": 1, "state": snapshot(), "session": session}, "", true, true))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return _fail("Cannot replace the duel save.")
	return true

func restore(data: ELProfile, document: Dictionary) -> bool:
	if document.get("format") != "etherlords-duel" or int(document.get("version", 0)) != 1:
		return _fail("Unsupported duel save.")
	var saved: Variant = document.get("state")
	if saved is not Dictionary or saved.get("profile") != data.id: return _fail("This save needs its original game edition.")
	var result := ELMatchSave.decode(data, saved)
	if result.has("error"): return _fail(result.error)
	var restored_scripts: ELBattleScripts = null
	if result.has("scripts"):
		# Chunks reload without CHook_Init; globals and the queue come from the save.
		var previous_profile := profile
		profile = data
		restored_scripts = ELBattleScripts.new(self)
		var problem := restored_scripts.restore(result.scripts)
		profile = previous_profile
		if not problem.is_empty(): return _fail(problem)
	if scripts != null: scripts.close()
	scripts = restored_scripts
	profile = data
	heroes.assign(result.heroes)
	creatures = result.creatures
	attacks.assign(result.attacks)
	blocks = result.blocks
	phase = int(result.phase)
	attacker = int(result.attacker)
	round_number = int(result.round)
	winner = int(result.winner)
	rng_state = int(result.rng)
	next_id = int(result.next_id)
	next_enchantment = int(result.next_enchantment)
	turn_serial = int(result.turn_serial)
	setup = result.setup
	hero_template = data.table("HeroTemplates")[heroes[0].template]
	history.clear()
	error = ""
	load_note = ""
	if (data.id == "el1" and not saved.has("charge_version")) or saved.heroes.any(func(h: Dictionary) -> bool: return not h.has("spell_uses")):
		load_note = "Older save: spellbook charges reset because charge history was not recorded. Cards in hand were kept."
	changed.emit()
	return true
