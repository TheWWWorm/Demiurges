extends SceneTree
## Headless check of the first game's 23 adventure global spells that did
## nothing in the original (cast, listed and paid for, or used up, with no
## effect) and now do what their texts promise, with the real game data:
## - castle shields (Chaos Shield, Shield of Ice, Ice Barriers), Erosion and
##   Shock Resonance on each attack; Continuous Restoration, Fresh Breeze, Mass
##   Restoration and Decay on regeneration;
## - Ether Calm calls off the Warriors of the Realm;
## - the ethereal-battle rewards: Wrath of the Dead, Biohazard, Enchanted
##   Herbs, Rush Reward, Blessing of the Forest for a winning attacker,
##   Retribution and Retaliation for a winning defender;
## - Terminal Discharge, Disenchant, Disjunction (with protection), Spell
##   Blast, Ether Leak, Visions;
## - Boon of Nature repairs the allies' castles too;
## - their texts carry no "no effect" note; the computer casts the useful ones
##   at the right castles; a save keeps them, and an older one still loads;
## - second game: the Wand of Hunger and Rod of Venom recipe texts.
##
##   godot --headless --path game --script ../tools/global_spells_effects_check.gd
##
## Needs the original games' files (user://profiles.json); without them it
## skips. Nothing is saved.

const MAP := "mmission01"
const CODES := ["AURP", "ERBR", "MSRP", "SHIC", "WTWL", "BLED", "FRGT", "RSNC", "ETSL", "ICBR", "GRIF", "BFDK", "NTLK", "QSTR", "RTRB", "RNBR", "VIGR",
	"CLPS", "DSGB", "DSLC", "ETWB", "SPBS", "SPWD"]

var failures: Array[String] = []
var profile: ELProfile
var director: ELAdventureDirector
var state: ELAdventureSession
## Three living players: A the human, B a computer rival, C (allied with A
## where a case says so).
var a := -1
var b := -1
var c := -1

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is Dictionary and paths.has("el2"):
		var second := ELProfile.new()
		if second.mount("el2", str(paths.el2)): _recipes(second)
		else: print("SKIP: the second game's files could not be mounted")
	else: print("SKIP: no second-game files configured")
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		_finish()
		return
	profile = ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		_finish()
		return
	_texts()
	if not _world():
		check(false, "the test map %s starts with three castles" % MAP)
		_finish()
		return
	for case: String in ["shields", "erosion", "resonance", "regeneration", "calm", "attacker", "defender", "discharge", "disenchant", "disjunction", "blast", "leak", "visions", "boon", "fallen", "computer"]:
		_reset()
		call("_case_" + case)
	_reset()
	_case_save()
	_finish()

func _finish() -> void:
	print("GLOBAL SPELLS EFFECTS: %d failure(s)" % failures.size())
	if state != null: state.close()
	quit(1 if not failures.is_empty() else 0)

# --- Setup -------------------------------------------------------------------

func _world() -> bool:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, MAP): return false
	state = ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false): return false
	director = ELAdventureDirector.new()
	if not director.build(state): return false
	director.fast_mode = true
	var ids: Array = state.scenario.get("castles", {}).keys()
	ids.sort()
	var living: Array[int] = []
	for id: int in ids:
		if id >= 1 and state.players.has(id) and not ELFirstScenario.castle_object(state, id).is_empty(): living.append(id)
	if living.size() < 3: return false
	a = state.current_player
	living.erase(a)
	b = living[0]
	c = living[1]
	return true

## Every castle whole, no spells, no alliances, no productions.
func _reset() -> void:
	for player: int in state.players:
		var record := ELGlobalSpells.data(state, player)
		if record.is_empty(): continue
		record.active = []
		record.production = {}
		state.players[player].relations = {}
		for kind: String in state.players[player].resources: state.players[player].resources[kind] = 1000
	for id: int in state.scenario.castles:
		var castle: Dictionary = state.scenario.castles[id]
		castle.health = int(castle.max)
		castle.pending = 0
		castle.alive = true
	ELGlobalSpells.sync(state)

func _ally(first: int, second: int) -> void:
	state.players[mini(first, second)].get_or_add("relations", {})[maxi(first, second)] = 0xff

## Casts `code` for `player` as if its production had just finished.
func _cast(player: int, code: String, chosen: Array = [], extra := 0) -> bool:
	var cost := int(ELGlobalSpells.row(profile, code).get("CostMana", 0)) + extra
	ELGlobalSpells.data(state, player).production = {"code": code, "cost": cost, "spent": cost, "state": 2}
	var done := ELGlobalSpells.cast(state, player, chosen)
	if not done: print("  cast %s for %d refused: %s" % [code, player, state.error])
	return done

func _pending(player: int) -> int:
	return int(state.scenario.castles[player].pending)

func _hero(player: int, level := 3) -> Dictionary:
	var rows: Dictionary = profile.table("HeroTemplates")
	var colour := str(state.players[player].color)
	var template := ""
	for key: String in rows:
		if str(rows[key].get("Quest", "")) != "Yes" and int(rows[key].get("Level", 1)) == 1 and str(rows[key].get("Color", "")) == colour:
			template = key
			break
	var spot := ELGlobalSpells.near_castle(state, player)
	var id := ELAdditionalBuildings.spawn_hero(state, template, player, spot.x, spot.y)
	if level > 1: state.add_experience(id, ELHeroProgression.threshold(profile, level))
	return state.object(id)

func _has(player: int, code: String) -> bool:
	for spell: Dictionary in ELGlobalSpells.data(state, player).active:
		if spell.code == code: return true
	return false

# --- Texts -------------------------------------------------------------------

func _texts() -> void:
	for code: String in CODES:
		var key := "GlSpTt" + code
		var shown := profile.text(key)
		var raw := String(profile.texts.get(key, "")).strip_edges()
		check(shown != key and shown == raw and not shown.contains("no effect") and not shown.contains("ничего не делает"), "el1 %s: the text is the original one, with no \"no effect\" note: %s" % [code, shown])
	var boon := profile.text("GlSpTtBNNT")
	check(boon == String(profile.texts.get("GlSpTtBNNT", "")).strip_edges(), "el1 BNNT: the text keeps its \"all friendly castles\": %s" % boon)

func _recipes(second: ELProfile) -> void:
	var hunger := second.text("MT_E2_ARTEFACT_RECIPE_5")
	var curses := second.text("MT_E2_ARTEFACT_RECIPE_4")
	var name := second.text("T_CUSTOM_ARTEFACT_WAND_OF_HUNGER")
	check(hunger != curses and hunger.contains(name), "el2 recipe 5 has its own text naming the %s: %s" % [name, hunger.substr(0, 160).replace("\n", " ")])
	check(not hunger.contains("Malison") and not hunger.contains("Напасти"), "el2 recipe 5 no longer describes the Wand of Curses")
	check((hunger.contains("Hunger") and hunger.contains("5")) or (hunger.contains("Голод") and hunger.contains("5")), "el2 recipe 5 names the Hunger spells and the five creatures")
	var venom := second.text("MT_E2_ARTEFACT_RECIPE_8")
	var rod := second.text("T_CUSTOM_ARTEFACT_ROD_OF_VENOM")
	check(venom.contains(rod) and not venom.contains("Ring of Venom") and not venom.contains("Кольцо Ядов"), "el2 recipe 8 names the %s" % rod)
	# The English text as shipped, through the same correction.
	var english := ELTextFixes.apply("el2", "MT_E2_ARTEFACT_RECIPE_5", "During a combat the hero must do the following:\n\nResult:\n\n1. If only summon spells were used, the artifact Wand of Curses is created; otherwise, the Wand of Malisons is created.")
	check(english.contains("Wand of Hunger") and english.contains("Ravaging Hunger") and english.contains("at least 5 creatures"), "el2 recipe 5, English: the copied Wand of Curses text is replaced")
	check(ELTextFixes.apply("el2", "MT_E2_ARTEFACT_RECIPE_8", "During a combat the hero must do the following:\n\n1. The artifact Ring of Venom is created").contains("Rod of Venom"), "el2 recipe 8, English: the Rod of Venom is named")
	# Every recipe, in both languages, names its artifacts and the blank.
	var names := {1: ["ROD_OF_PTEROSES", "WAND_OF_PURIFY"], 2: ["RING_OF_GASES", "RING_OF_SUFFOCATION"], 3: ["ROD_OF_MECHOSES"], 4: ["WAND_OF_CURSES", "WAND_OF_MALISONS"], 5: ["WAND_OF_HUNGER"],
		6: ["WAND_OF_ETHER_HARVEST"], 7: ["ROD_OF_HALOS"], 8: ["ROD_OF_VENOM"], 9: ["ROD_OF_CANTRIPS"]}
	var blank := second.text("ArtBlank")
	for number: int in names:
		var shown := second.text("MT_E2_ARTEFACT_RECIPE_%d" % number)
		var missing: Array = names[number].filter(func(item: String) -> bool: return not shown.contains(second.text("T_CUSTOM_ARTEFACT_" + item)))
		check(missing.is_empty() and shown.contains(blank), "el2 recipe %d names its artifacts %s and the %s" % [number, str(missing), blank])

# --- Castle damage -----------------------------------------------------------

func _case_shields() -> void:
	_cast(a, "ERBR")
	_cast(b, "METR", [a])
	check(_pending(a) == 4, "ERBR: Chaos Shield absorbs 3 of a Meteor's 7 (pending %d)" % _pending(a))
	check(ELFirstScenario.damage(state, a, 2) == 0 and _pending(a) == 4, "ERBR: a hit of 2 is absorbed whole")
	_reset()
	_cast(a, "SHIC")
	_cast(b, "METR", [a])
	check(_pending(a) == 2, "SHIC: Shield of Ice absorbs 5 of 7 (pending %d)" % _pending(a))
	_reset()
	_ally(a, c)
	_cast(a, "ICBR")
	for id: int in [a, b, c]: ELFirstScenario.damage(state, id, 7)
	check(_pending(a) == 4 and _pending(c) == 4 and _pending(b) == 7, "ICBR: Ice Barriers absorb 3 on the caster's and its ally's castles, not a rival's (%d %d %d)" % [_pending(a), _pending(c), _pending(b)])
	_cast(a, "SHIC")
	ELFirstScenario.damage(state, a, 7)
	check(_pending(a) == 4 + 0, "SHIC + ICBR: shields add up (8 absorb a 7)")
	# An assault goes through the same rule.
	_reset()
	_cast(a, "SHIC")
	var hero := _hero(b, 7)
	ELFirstScenario.assault(director, hero, ELFirstScenario.castle_object(state, a))
	check(_pending(a) == maxi(0, ELFirstScenario.hero_value(hero) - 5), "SHIC: an assault of %d loses 5 (pending %d)" % [ELFirstScenario.hero_value(hero), _pending(a)])
	director.notice = ""
	state._native([float(hero.uid)], "ExKillHero")

func _case_erosion() -> void:
	_cast(b, "FRGT", [a])
	check(ELGlobalSpells.acting_on(state, a).size() == 1, "FRGT: Erosion is listed as acting on the target castle")
	_cast(b, "METR", [a])
	check(_pending(a) == 10, "FRGT: a Meteor's 7 becomes 10 (pending %d)" % _pending(a))
	_cast(a, "ERBR")
	ELFirstScenario.damage(state, a, 7)
	check(_pending(a) == 17, "FRGT + ERBR: raised first, then absorbed: 7 -> 10 -> 7 (pending %d)" % _pending(a))

func _case_resonance() -> void:
	_cast(b, "RSNC", [a])
	_cast(b, "METR", [a])
	check(_pending(a) == 7 and _pending(b) == 7 and _pending(c) == 7, "RSNC: every castle takes what the enchanted one takes (%d %d %d)" % [_pending(a), _pending(b), _pending(c)])
	_cast(c, "SHIC")
	ELFirstScenario.damage(state, a, 4)
	check(_pending(c) == 11, "RSNC: the echo is no attack, shields do not stop it (%d)" % _pending(c))
	ELFirstScenario.damage(state, b, 4)
	check(_pending(a) == 11 and _pending(b) == 15, "RSNC: only attacks on the enchanted castle echo")

func _case_regeneration() -> void:
	check(ELFirstScenario.regained(state, a, 54) == 3, "no spell: 54 free ether regenerate 3")
	_cast(a, "AURP")
	check(ELFirstScenario.regained(state, a, 54) == 6, "AURP: Continuous Restoration doubles it to 6 (%d)" % ELFirstScenario.regained(state, a, 54))
	_reset()
	_cast(a, "WTWL")
	check(ELFirstScenario.regained(state, a, 54) == 5 and ELFirstScenario.regained(state, a, 6) == 2, "WTWL: Fresh Breeze: 3 -> 5, 1 -> 2 (rounded up)")
	_reset()
	_ally(a, c)
	_cast(a, "MSRP")
	check(ELFirstScenario.regained(state, a, 54) == 5 and ELFirstScenario.regained(state, c, 54) == 5 and ELFirstScenario.regained(state, b, 54) == 3, "MSRP: Mass Restoration speeds the caster's and its ally's castles, not a rival's")
	_cast(b, "BLED", [a])
	check(ELFirstScenario.regained(state, a, 54) == 0, "BLED: a decayed castle does not regenerate, boosts or not")
	# The day's end applies it.
	var castle: Dictionary = state.scenario.castles[a]
	castle.health = int(castle.max) - 10
	ELFirstScenario.regenerate(state)
	check(int(castle.health) == int(castle.max) - 10, "BLED: the day's end leaves the decayed castle at %d" % int(castle.health))
	_reset()
	_cast(a, "AURP")
	castle.health = int(castle.max) - 20
	var expect := ELFirstScenario.regained(state, a, ELGlobalSpells.free_ether(state, a))
	ELFirstScenario.regenerate(state)
	check(int(castle.health) == int(castle.max) - 20 + expect, "AURP: the day's end regenerates the doubled amount (%d)" % expect)

func _case_calm() -> void:
	var raider := _hero(b, 5)
	var record := ELGlobalSpells.data(state, b)
	record.serial = int(record.serial) + 1
	record.active.append({"serial": record.serial, "code": ELGlobalSpells.WARRIOR, "hero": int(raider.uid), "castle": a, "attacked": false, "protection": 0})
	ELGlobalSpells.sync(state)
	_cast(c, "ETSL")
	ELGlobalSpells.plan_ethereal(director)
	check(_pending(a) == 0 and record.active[-1].get("attacked", false), "ETSL: under Ether Calm the Warrior of the Realm is called off")
	record.active[-1].attacked = false
	ELGlobalSpells.dispel(state, c, int(ELGlobalSpells.data(state, c).active[-1].serial))
	ELGlobalSpells.plan_ethereal(director)
	check(_pending(a) == ELFirstScenario.hero_value(raider), "ETSL: without it the Warrior strikes the undefended castle (%d)" % _pending(a))
	director.notice = ""
	state._native([float(raider.uid)], "ExKillHero")

# --- Ethereal battles --------------------------------------------------------

func _case_attacker() -> void:
	var report := {"round": 3, "health": 25, "grave": 4, "army": 2}
	var expect := {"GRIF": 4, "BFDK": 2, "QSTR": 7, "VIGR": 2}
	for code: String in expect:
		_reset()
		var attacker := _hero(a, 4)
		var guard := _hero(b, 2)
		_cast(a, code, [int(attacker.uid)])
		ELGlobalSpells.ethereal_result(state, int(guard.uid), int(attacker.uid), int(attacker.uid), report)
		var value := ELFirstScenario.hero_value(attacker)
		check(_pending(b) == value + int(expect[code]), "%s: a winning attacker deals %d more (%d)" % [code, int(expect[code]), _pending(b) - value])
		for hero: Dictionary in [attacker, guard]: state._native([float(hero.uid)], "ExKillHero")
	# Without a duel (two computer players): round 5, the hero's own health.
	_reset()
	var quick := _hero(a, 4)
	var keeper := _hero(b, 2)
	_cast(a, "QSTR", [int(quick.uid)])
	check(ELGlobalSpells.battle_bonus(quick, {}) == 5, "QSTR: a battle settled without a duel counts as won in round 5")
	# A finished duel's report.
	var duel := ELDuel.new()
	duel.heroes = [{"health": 17, "grave": []}, {"health": 0, "grave": ["A", "B", "C"]}]
	duel.creatures = {5: {"owner": 1}, 6: {"owner": 1}, 7: {"owner": 0}}
	duel.winner = 0
	duel.round_number = 6
	check(ELGlobalSpells.battle_report(duel) == {"round": 6, "health": 17, "grave": 3, "army": 2}, "battle_report reads the round, the winner's health, the loser's graveyard and creatures (%s)" % ELGlobalSpells.battle_report(duel))
	for hero: Dictionary in [quick, keeper]: state._native([float(hero.uid)], "ExKillHero")
	# Enchanted Herbs.
	_reset()
	var thief := _hero(a, 4)
	var victim := _hero(b, 2)
	_cast(a, "NTLK", [int(thief.uid)])
	state.players[b].resources.Root = 30
	state.players[b].resources.Lotus = 1000
	var before_root := int(state.players[a].resources.Root)
	var before_lotus := int(state.players[a].resources.Lotus)
	ELGlobalSpells.ethereal_result(state, int(victim.uid), int(thief.uid), int(thief.uid), report)
	var dealt := _pending(b)
	check(int(state.players[a].resources.Root) - before_root == 30 and int(state.players[b].resources.Root) == 0, "NTLK: the Mandrake Root taken is what the loser holds (30)")
	check(int(state.players[a].resources.Lotus) - before_lotus == 10 * dealt and int(state.players[b].resources.Lotus) == 1000 - 10 * dealt, "NTLK: Black Lotus taken is 10 per point of castle damage (%d)" % (10 * dealt))
	# A defender that wins earns the attacker no reward.
	var root := int(state.players[a].resources.Root)
	ELGlobalSpells.ethereal_result(state, int(victim.uid), int(victim.uid), int(thief.uid), report)
	check(int(state.players[a].resources.Root) == root, "NTLK: nothing when the attacker loses")
	for hero: Dictionary in [thief, victim]: state._native([float(hero.uid)], "ExKillHero")

func _case_defender() -> void:
	var attacker := _hero(a, 4)
	var guard := _hero(b, 4)
	_cast(b, "RTRB", [int(guard.uid)])
	ELGlobalSpells.ethereal_result(state, int(guard.uid), int(attacker.uid), int(attacker.uid))
	check(attacker.alive, "RTRB: a defender that loses kills nobody")
	ELGlobalSpells.ethereal_result(state, int(guard.uid), int(guard.uid), int(attacker.uid))
	check(not attacker.alive, "RTRB: a winning defender's Retribution kills the attacker")
	_reset()
	var other := _hero(a, 4)
	var keeper := _hero(b, 4)
	_cast(b, "RNBR", [int(keeper.uid)])
	check(ELRunes.restore(profile, other), "RNBR: the attacker has a rune book")
	for index in other.cards.size():
		if int(other.rune_uses[index]) >= 0: other.rune_uses[index] = 3 + index * 2
	var before: Array = other.rune_uses.duplicate()
	ELGlobalSpells.ethereal_result(state, int(keeper.uid), int(keeper.uid), int(other.uid))
	var ok := not before.is_empty()
	for index in before.size():
		var want := -1 if int(before[index]) < 0 else maxi(0, int(before[index]) - 5)
		ok = ok and int(other.rune_uses[index]) == want
	check(ok and before.has(-1) == other.rune_uses.has(-1), "RNBR: every spell that is not a cantrip loses 5 runes (%s -> %s)" % [before, other.rune_uses])
	for hero: Dictionary in [other, keeper]: state._native([float(hero.uid)], "ExKillHero")

# --- Dispels and the rest ----------------------------------------------------

func _case_discharge() -> void:
	var castle: Dictionary = state.scenario.castles[a]
	var full := int(castle.health)
	_cast(a, "CLPS", [b])
	check(int(castle.health) == full - full / 2 and _pending(b) == full / 2, "CLPS: the caster pays half its energy (%d) and the target takes it (%d)" % [full / 2, _pending(b)])
	_reset()
	_cast(b, "SHIC")
	_cast(a, "CLPS", [b])
	check(_pending(b) == maxi(0, full / 2 - 5), "CLPS: the discharge is one attack, a shield absorbs its share (%d)" % _pending(b))

func _case_disenchant() -> void:
	_cast(b, "BLED", [a])
	_cast(b, "FRGT", [a], 20)
	_cast(c, "RSNC", [a])
	_cast(b, "BLED", [c])
	_cast(a, "DSLC")
	var left: Array = []
	for entry: Dictionary in ELGlobalSpells.acting_on(state, a): left.append(entry.spell.code)
	check(left == ["FRGT"], "DSLC: Disenchant ends the spells on the caster's castle, but not one of protection 2 (left %s)" % [left])
	check(ELGlobalSpells.on_castle(state, c, "BLED"), "DSLC: spells on other castles stay")
	_cast(a, "DSLC", [], 20)
	check(ELGlobalSpells.acting_on(state, a).is_empty(), "DSLC: with 20 extra ether it overcomes protection 2")

func _case_disjunction() -> void:
	_ally(a, c)
	_cast(b, "BLRT")
	_cast(b, "ETSL")
	_cast(b, "SHIC")
	_cast(c, "ICBR")
	_cast(a, "DSGB")
	check(not _has(b, "ETSL") and _has(b, "BLRT") and _has(b, "SHIC"), "DSGB: Disjunction removes the rival's costliest spell (Ether Calm)")
	_cast(a, "DSGB")
	check(not _has(b, "BLRT") and _has(b, "SHIC") and _has(c, "ICBR"), "DSGB: then the next costliest; an ally's spells are left alone")
	_reset()
	_cast(b, "ETSL", [], 30)
	check(not ELGlobalSpells.disjoin(state, a, 0) and _has(b, "ETSL"), "DSGB: protection 3 resists a plain Disjunction")
	check(ELGlobalSpells.disjoin(state, a, 3) and not _has(b, "ETSL"), "DSGB: one with protection 3 removes it")

func _case_blast() -> void:
	var record := ELGlobalSpells.data(state, b)
	var price := ELGlobalSpells.resources(profile, "METR")
	record.production = {"code": "METR", "cost": 100, "spent": 0, "state": 1}
	var held := int(state.players[b].resources.get("Ruby", 0))
	_cast(a, "SPBS", [b])
	check(record.production.is_empty() and int(state.players[b].resources.get("Ruby", 0)) == held + int(price.get("Ruby", 0)), "SPBS: nothing invested yet, the blast always dispels and the resources come back")
	var hits := 0
	for attempt in 400:
		record.production = {"code": "METR", "cost": 300, "spent": 100, "state": 1}
		if ELGlobalSpells.blast(state, a, b, 100): hits += 1
	check(hits > 140 and hits < 260, "SPBS: 100 ether against 100 invested succeeds about half the time (%d of 400)" % hits)
	hits = 0
	for attempt in 400:
		record.production = {"code": "METR", "cost": 1000, "spent": 900, "state": 1}
		if ELGlobalSpells.blast(state, a, b, 100): hits += 1
	check(hits < 80, "SPBS: against 900 invested it rarely does (%d of 400)" % hits)
	record.production = {}
	check(not ELGlobalSpells.blast(state, a, b, 100), "SPBS: nothing is being created, nothing happens")

## Lets `player` order the colourless Disenchant.
func _learn(player: int) -> Dictionary:
	var hero := _hero(player, 2)
	hero.gs_items = [{"kind": ELMapPickups.FULL, "spells": ["DSLC"]}]
	return hero

func _case_leak() -> void:
	var plain := ELGlobalSpells.ether_cost(state, b, "METR")
	_cast(a, "SPWD", [b])
	check(ELGlobalSpells.ether_cost(state, b, "METR") == plain, "SPWD: without extra ether the leak adds nothing")
	_reset()
	_cast(a, "SPWD", [b], 40)
	check(ELGlobalSpells.ether_cost(state, b, "METR") == plain + 20 and ELGlobalSpells.ether_cost(state, a, "METR") == plain, "SPWD: 40 extra ether make the target's spells cost 20 more, not the caster's")
	var learner := _learn(b)
	var simple := int(ELGlobalSpells.row(profile, "DSLC").get("CostMana", 0))
	check(ELGlobalSpells.produce(state, b, "DSLC"), "SPWD: the target orders Disenchant (%s)" % state.error)
	var production: Dictionary = ELGlobalSpells.data(state, b).production
	check(int(production.get("cost", 0)) == simple + 20 and int(production.get("leak", 0)) == 20, "SPWD: an order of the target pays the leak (%s)" % production)
	production.spent = production.get("cost", 0)
	production.state = 2
	ELGlobalSpells.cast(state, b, [])
	state._native([float(learner.uid)], "ExKillHero")
	check(ELGlobalSpells.protection(state, "DSLC", int(production.get("cost", 0)) - int(production.get("leak", 0))) == 0, "SPWD: the leaked ether gives no protection")

func _case_visions() -> void:
	ELGlobalSpells.data(state, b).production = {"code": "METR", "cost": 100, "spent": 40, "state": 1}
	check(ELGlobalSpells.seen_production(state, a, b).is_empty(), "ETWB: without Visions a rival's spell is hidden")
	_cast(a, "ETWB")
	check(_has(a, "ETWB") and str(ELGlobalSpells.seen_production(state, a, b).get("code", "")) == "METR", "ETWB: Visions show what the rival is creating")
	check(ELGlobalSpells.seen_production(state, b, a).is_empty(), "ETWB: only to the caster")

func _case_boon() -> void:
	_ally(a, c)
	_cast(a, "BNNT")
	check(_pending(a) == -4 and _pending(c) == -4 and _pending(b) == 0, "BNNT: Boon of Nature repairs 4 on the caster's and its ally's castles (%d %d %d)" % [_pending(a), _pending(c), _pending(b)])
	_reset()
	_ally(a, c)
	_cast(a, "REPR")
	check(_pending(a) == -4 and _pending(c) == 0, "REPR: Restoration repairs the caster's castle alone")

func _case_fallen() -> void:
	_cast(a, "BLED", [b])
	state.scenario.castles[b].alive = false
	ELGlobalSpells.settle(state, a)
	check(not _has(a, "BLED"), "a spell on a fallen castle ends at the settlement (no more upkeep)")
	state.scenario.castles[b].alive = true

# --- Computer ----------------------------------------------------------------

func _case_computer() -> void:
	var player := b
	for code: String in ["RSNC", "ETSL", "ETWB", "SPWD", "SPBS", "GRIF", "RTRB"]:
		check(not ELFirstAIEconomy.castable(code), "computer: leaves %s alone" % code)
	for code: String in ["ERBR", "SHIC", "ICBR", "AURP", "WTWL", "MSRP", "BLED", "FRGT", "CLPS", "DSLC", "DSGB"]:
		check(ELFirstAIEconomy.castable(code), "computer: may cast %s" % code)
	check(ELFirstAIEconomy._score(director, player, "SHIC") == 0.0, "computer: no shield for a whole, unthreatened castle")
	state.scenario.castles[player].pending = 3
	check(ELFirstAIEconomy._score(director, player, "SHIC") > 0.0, "computer: a shield once damage is on its way")
	state.scenario.castles[player].pending = 0
	check(ELFirstAIEconomy._score(director, player, "AURP") == 0.0, "computer: no regeneration boost for a whole castle")
	check(ELFirstAIEconomy._score(director, player, "DSLC") == 0.0, "computer: no Disenchant with nothing on its castle")
	_cast(a, "BLED", [player])
	check(ELFirstAIEconomy._score(director, player, "DSLC") > 0.0, "computer: Disenchant once a rival's Decay is on its castle")
	# Hostile castle spells go to an enemy castle.
	for code: String in ["BLED", "FRGT", "CLPS"]:
		_reset()
		var cost := int(ELGlobalSpells.row(profile, code).get("CostMana", 0))
		ELGlobalSpells.data(state, player).production = {"code": code, "cost": cost, "spent": cost, "state": 2}
		ELFirstAIEconomy._cast(director, player)
		var aimed := -1
		for owner: int in state.players:
			for spell: Dictionary in ELGlobalSpells.data(state, owner).get("active", []):
				if spell.code == code: aimed = int(spell.castle)
		if code == "CLPS": aimed = b if _pending(b) > 0 else (a if _pending(a) > 0 else (c if _pending(c) > 0 else -1))
		check(aimed >= 1 and aimed != player and not ELGlobalSpells._allied(state, player, aimed), "computer: %s is aimed at an enemy castle (%d)" % [code, aimed])
	# The whole day's routine: it orders and casts Disenchant against Decay.
	_reset()
	_cast(a, "BLED", [player])
	var hero := _learn(player)
	for item: Dictionary in state.objects.values():
		if item.get("group") == "buildings" and item.get("name") == "MainTower" and int(item.get("owner", -1)) == player:
			if not item.node.has("attrs"): item.node.attrs = {}
			item.node.attrs.mana_income = 100
	ELStrategy.mana_budget(state, player, true)
	var spare := ELGlobalSpells.free_ether(state, player)
	if spare < 5:
		print("SKIP: computer: player %d has no free ether for Disenchant" % player)
	else:
		ELFirstAIEconomy.global_spells(director, player)
		check(not ELGlobalSpells.on_castle(state, player, "BLED"), "computer: it creates and casts Disenchant to end the Decay on its castle")
	# A regeneration boost on a whole castle is dispelled.
	_reset()
	_cast(player, "AURP")
	ELFirstAIEconomy.global_spells(director, player)
	check(not _has(player, "AURP"), "computer: dispels Continuous Restoration once its castle is whole")
	state._native([float(hero.uid)], "ExKillHero")

# --- Saves -------------------------------------------------------------------

func _case_save() -> void:
	var guard := _hero(a, 2)
	_cast(a, "SHIC")
	_cast(a, "RTRB", [int(guard.uid)])
	_cast(a, "SPWD", [b], 40)
	_cast(c, "BLED", [a])
	_learn(b)
	ELGlobalSpells.produce(state, b, "DSLC")
	var codec := ELAdventureSave.new()
	var document := codec.encode(director, {})
	check(not document.is_empty(), "save: the game with the new spells active encodes (%s)" % codec.error)
	if document.is_empty(): return
	var text := JSON.stringify(document, "", true, true)
	var restored := codec.decode(JSON.parse_string(text), {"el1": profile})
	check(not restored.is_empty(), "save: it loads back (%s)" % codec.error)
	if not restored.is_empty():
		var next: ELAdventureSession = restored.state
		var codes: Array = []
		var leak := -1
		for spell: Dictionary in ELGlobalSpells.data(next, a).active:
			codes.append(spell.code)
			if spell.code == "SPWD": leak = int(spell.get("leak", -1))
		check(codes == ["SHIC", "RTRB", "SPWD"] and leak == 20, "save: the spells and the leak survive (%s, %d)" % [codes, leak])
		check(int(ELGlobalSpells.data(next, b).production.get("leak", 0)) == 20 and ELGlobalSpells.ether_cost(next, b, "METR") == ELGlobalSpells.ether_cost(state, b, "METR"), "save: the leaked production and the leak on the castle survive")
		check(ELGlobalSpells.on_castle(next, a, "BLED") and ELGlobalSpells.absorption(next, a) == 5, "save: the castle's Decay and Shield of Ice still act")
		next.close()
	# A save from before these spells worked: no leak fields.
	var old: Variant = JSON.parse_string(text)
	_strip_leak(old)
	var older := codec.decode(old, {"el1": profile})
	check(not older.is_empty(), "save: an older save without leak fields loads (%s)" % codec.error)
	if not older.is_empty():
		var next: ELAdventureSession = older.state
		check(ELGlobalSpells.leak(next, b) == 0 and int(ELGlobalSpells.data(next, b).production.get("leak", 0)) == 0, "save: there the leak reads as 0")
		next.close()

func _strip_leak(value: Variant) -> void:
	if value is Dictionary:
		value.erase("leak")
		for key: Variant in value: _strip_leak(value[key])
	elif value is Array:
		for item: Variant in value: _strip_leak(item)
