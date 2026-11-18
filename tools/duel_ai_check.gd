extends SceneTree
## Headless check of the computer opponent's remake option ("smart" mode):
##
## - the compiled combat lookahead (el_duel_brain.c) on small
##   hand-made fights: it takes a win on the board, holds back a creature the
##   hero needs as a blocker, blocks to survive, finishes blocks already begun,
##   and reports the turn that decides a duel;
## - positions from real computer-vs-computer duels (tools/duel_ai_positions)
##   where the opponent once played plainly badly. Each names the side to
##   move and what must come of its play:
##     win      it wins the duel before the turn passes on
##     survive  its hero is alive when the fight under way is over
##     attack   it sends at least one creature to attack this turn
##     spare    it does not cast the named card this phase
##     keep     it does not lose a creature in a fight that hurts nobody
##     use      it uses the named ability this phase
##     cast     it casts the named card this phase
##     aim      it aims no harm at its own side (a damaging or crippling
##              card, the hero's fireball, a creature's harmful ability on
##              its own hero or creatures) before the turn passes on; with
##              "card", that card cast at all goes to the other side; with
##              "win", it also wins the duel before the turn passes on
##   Both sides are played by the option as shipped, with no thinking between
##   the commands of a chosen plan, as in the game.
##
##   godot --headless --path game --script ../tools/duel_ai_check.gd [-- --only=<text>]
##
## Needs the original games' files (user://profiles.json or --el1=/--el2=); a
## game without them is skipped. Positions come from tools/duel_ai_audit.gd
## and tools/duel_ai_regret.gd (--save), with an "expect" entry added.

const POSITIONS := "res://../tools/duel_ai_positions"
const Fixtures := preload("res://../tools/duel_fixtures.gd")
const FLY := 1
const FIRST := 2
const RESTING := 8192
const SICK := 16384
const ATTACKING := 65536
const NO_UNTAP := 256
## The state the library reads (see ELCombatBrain, which packs a real duel).
const HEADER := ELCombatBrain.HEADER
const HERO := ELCombatBrain.HERO_FIELDS
const TYPICAL := ELCombatBrain.COSTS * ELCombatBrain.TYPICAL_FIELDS
const CARD := ELCombatBrain.CARD_FIELDS
const HAND := ELCombatBrain.SLOTS * CARD
const UNIT := ELCombatBrain.UNIT_FIELDS
const FIXED := ELCombatBrain.FIXED

var failures: Array[String] = []
var profiles := {}

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	var only := _arg("only", "")
	# The positions are put to the compiled engine, as the game does by
	# default; --engine=false puts them to the search written in the game's
	# own language instead.
	ELCombatSearch.smart_engine = _arg("engine", "true") == "true"
	if only.is_empty() or "lookahead".contains(only): _lookahead()
	if only.is_empty() or "fixtures".contains(only): _fixtures()
	if only.is_empty() or "passing".contains(only): _passing()
	_positions(only)
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# --- The compiled lookahead ------------------------------------------------------

## One call of the library. heroes: [health, ether, channels] per side; units:
## [id, owner, power, toughness, flags, attacker it blocks or -1, wake cost,
## damage taken];
## hand: the computer's creature cards as [cost, power, toughness].
func _ask(ai: int, attacker: int, phase: int, turns: int, heroes: Array, units: Array, cards := false, hand: Array = []) -> Dictionary:
	var state := PackedInt32Array()
	state.resize(FIXED + units.size() * UNIT)
	state[0] = ELCombatBrain.VERSION
	state[1] = ai
	state[2] = attacker
	state[3] = phase
	state[4] = turns
	state[5] = 200000
	state[7] = 1600
	state[10] = 1
	state[11] = units.size()
	state[12] = 1 if cards else 0
	state[13] = 1 if phase == 0 else 0
	for side in 2:
		var at := HEADER + side * HERO
		var hero: Array = heroes[side]
		state[at] = hero[0]
		state[at + 1] = hero[1] if hero.size() > 1 else 5
		state[at + 2] = hero[2] if hero.size() > 2 else 5
	var hands := HEADER + 2 * HERO + 2 * TYPICAL
	for i in 2 * ELCombatBrain.SLOTS: state[hands + i * CARD] = -1
	for i in hand.size():
		var slot := hands + ai * HAND + i * CARD
		state[slot] = hand[i][0]
		state[slot + 1] = hand[i][1]
		state[slot + 2] = hand[i][2]
		state[slot + 3] = SICK
		state[slot + 5] = int((600 + 800 * int(hand[i][2]) + 1200 * int(hand[i][1])) * 0.7) - 800
		state[slot + 6] = state[slot + 5] - 350
		state[slot + 8] = 1
	var u := FIXED
	for unit: Array in units:
		for i in 5: state[u + i] = unit[i]
		state[u + 8] = 600 + 800 * int(unit[3]) + 1200 * int(unit[2])
		state[u + 9] = state[u + 8] - 500
		state[u + 11] = unit[5] if unit.size() > 5 else -1
		state[u + 12] = unit[6] if unit.size() > 6 else 0
		state[u + 13] = unit[7] if unit.size() > 7 else 0
		u += UNIT
	var out: PackedInt32Array = (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", state.to_byte_array()) as PackedByteArray).to_int32_array()
	if out.size() < 5: return {"status": 0, "value": 0, "choice": [], "searched": 0}
	return {"status": out[0], "value": out[1], "searched": out[3], "choice": Array(out.slice(5, 5 + out[4]))}

func _lookahead() -> void:
	if not ClassDB.class_exists(&"ELNativeDuelBrain"):
		print("SKIP: the compiled lookahead is not built for this platform")
		return
	var a := _ask(0, 0, 0, 2, [[10], [3]], [[2, 0, 3, 3, 0], [3, 0, 3, 3, 0], [4, 1, 1, 1, 0]])
	check(a.choice == [2, 3] and a.status == 1 and a.value == 1, "lookahead: two 3/3 against 3 health and one blocker both attack, a win this turn")
	a = _ask(0, 0, 0, 2, [[10], [5]], [[2, 0, 3, 3, 0], [3, 0, 3, 3, 0], [4, 1, 1, 1, 0]])
	check(a.choice == [2, 3] and a.status == 0, "lookahead: against 5 health they still both attack, with no win yet")
	a = _ask(0, 0, 0, 3, [[3], [10]], [[2, 0, 2, 2, 0], [3, 1, 3, 3, RESTING]])
	check(a.choice == [], "lookahead: at 3 health the only blocker stays home from a resting 3/3")
	a = _ask(0, 0, 0, 3, [[20], [10]], [[2, 0, 2, 2, 0], [3, 1, 3, 3, RESTING]])
	check(a.choice == [2], "lookahead: at 20 health it attacks past the resting 3/3")
	a = _ask(0, 0, 0, 3, [[20], [20]], [[2, 0, 2, 2, 0], [3, 1, 3, 3, 0]])
	check(a.choice == [], "lookahead: a 2/2 does not run into a ready 3/3")
	a = _ask(0, 1, 1, 2, [[4], [10]], [[2, 0, 2, 2, 0], [3, 0, 5, 5, 0], [4, 1, 4, 4, ATTACKING], [5, 1, 1, 1, ATTACKING]])
	check(a.choice == [2, 5, 3, 4], "lookahead: at 4 health the 5/5 blocks the 4/4 and the 2/2 the 1/1")
	a = _ask(0, 1, 1, 1, [[4], [10]], [[2, 0, 1, 1, 0], [4, 1, 4, 4, ATTACKING], [5, 1, 4, 4, ATTACKING]])
	check(a.status == -1 and a.value == 1, "lookahead: one blocker against two 4/4 at 4 health is a loss this turn")
	# Blocks already begun: two blockers stand on one attacker, three are free
	# and five attackers are open; stopping the two strongest and one more
	# leaves 14 damage at 21 health.
	var fight := [[2, 1, 9, 6, ATTACKING], [3, 1, 9, 6, ATTACKING], [4, 1, 9, 6, ATTACKING], [5, 1, 7, 4, ATTACKING], [6, 1, 7, 4, ATTACKING], [7, 1, 7, 4, ATTACKING],
		[8, 0, 9, 6, 0, 4], [9, 0, 7, 4, 0, 4], [10, 0, 9, 6, 0], [11, 0, 9, 6, 0], [12, 0, 7, 4, 0]]
	a = _ask(0, 1, 1, 1, [[21], [21]], fight)
	var stopped := {}
	for i in range(1, a.choice.size(), 2): stopped[a.choice[i]] = true
	check(a.status == 0 and stopped.has(2) and stopped.has(3) and stopped.size() == 3 and not stopped.has(4), "lookahead: with blocks begun on one attacker, the free blockers stop three others and the hero lives")
	# Three flyers at home against two dragons, one of them resting: two of
	# the three can kill an attacker together, so none is sent to die first.
	a = _ask(0, 0, 0, 2, [[25], [33]], [[3, 0, 5, 3, FLY | FIRST], [5, 0, 3, 3, FLY], [7, 0, 6, 7, FLY | SICK], [4, 1, 9, 8, FLY | RESTING], [6, 1, 8, 9, FLY]])
	check(a.choice == [], "lookahead: a third blocker is not thrown away so that the other two can block together")
	a = _ask(0, 0, 0, 3, [[4, 3, 3], [12, 3, 3]], [[2, 0, 3, 3, 0], [3, 1, 4, 4, RESTING | NO_UNTAP, -1, 3]])
	check(a.choice == [2], "lookahead: armies only, it attacks past an enfeebled 4/4")
	a = _ask(0, 0, 0, 3, [[4, 3, 3], [12, 3, 3]], [[2, 0, 3, 3, 0], [3, 1, 4, 4, RESTING | NO_UNTAP, -1, 3]], true)
	check(a.choice == [], "lookahead: with cards, the enemy can wake its 4/4, so the blocker stays")
	a = _ask(0, 0, 0, 3, [[3, 2, 2], [10, 0, 0]], [[2, 0, 2, 2, 0], [3, 1, 3, 3, RESTING]], true, [[2, 2, 2]])
	check(a.choice == [2], "lookahead: with cards, a 2/2 in hand will block, so the 2/2 in play attacks")
	# Two 2/6 alike but for wounds are not one kind: the wounded one (five
	# damage taken) would die to the ready 1/3 for nothing, so it stays home
	# (the two once counted as one, and so went or stayed together).
	a = _ask(0, 0, 0, 2, [[20], [20]], [[2, 0, 2, 6, 0, -1, 0, 5], [3, 0, 2, 6, 0], [4, 1, 1, 3, 0]])
	check(not a.choice.has(2), "lookahead: of two 2/6, the one at five damage is not sent into a ready 1/3 (%s)" % [a.choice])

func _passing() -> void:
	if not ELCombatBrain.available: return
	var previous := ELCombatSearch.smart_engine
	ELCombatSearch.smart_engine = true
	for game: String in ["el1", "el2"]:
		var profile := _profile(game)
		if profile == null: continue
		var duel := Fixtures.build(profile, {
			"heroes": [{"mana": 2, "hand": ["ERQA"]}, {"mana": 0, "health": 1}],
			"creatures": [{"owner": 0, "card": "GBAT", "power": 1, "flags": ["Fly"]}, {"owner": 1, "card": "KBGD", "toughness": 1, "flags": []}],
			"attacks": [2],
		})
		if duel == null:
			check(false, game + ": Earthquake fixture loads")
			continue
		duel.smart_sides = [0]
		var ctx := Fixtures.context(profile, 0)
		var offered := ELCombatBrain.weigh(ctx, duel, 2, 20000, 4)
		var offered_pass := offered.any(func(item: Dictionary) -> bool: return item.command.kind == "end_phase")
		var offered_quake := offered.any(func(item: Dictionary) -> bool: return item.command.get("card") == "ERQA")
		check(duel.maximum_power("ERQA") == 0 and offered_pass and not offered_quake,
			game + ": an Earthquake with zero damage is left out of the ordinary search")
		var tied := duel.search_copy()
		tied.heroes[0].mana = 3
		var prove := ELCombatSearch.smart_engine_prove
		ELCombatSearch.smart_engine_prove = 0
		var answer := ELCombatBrain.choose(ctx, tied, 2, 20000, 4)
		ELCombatSearch.smart_engine_prove = prove
		check(answer.get("command", {}).get("kind") == "end_phase",
			game + ": ordinary search passes when casting Earthquake wins just as soon")
		ELPracticeAI.step(duel)
		check(duel.phase != ELDuel.Phase.ATTACK and duel.heroes[0].hand.has("ERQA"),
			game + ": smart AI passes with lethal damage already attacking and keeps Earthquake")
		duel = Fixtures.build(profile, {
			"heroes": [{"mana": 3, "hand": ["ERQA"]}, {"mana": 0, "health": 1}],
			"creatures": [{"owner": 0, "card": "GBAT", "power": 1, "toughness": 2, "flags": []}, {"owner": 1, "card": "KBGD", "toughness": 1, "flags": []}],
			"attacks": [2],
		})
		if duel == null:
			check(false, game + ": positive Earthquake fixture loads")
			continue
		duel.smart_sides = [0]
		var command := ELCombatSearch.think(duel)
		check(command.get("card") == "ERQA" and command.get("power") == 1 and ELCombatSearch.apply(duel, command) and duel.army(1).is_empty(),
			game + ": smart AI casts Earthquake to remove the blocker for lethal damage")
		_discard_targets(profile, ctx)
	ELCombatSearch.smart_engine = previous

func _discard_targets(profile: ELProfile, ctx: ELCombatSearch.Context) -> void:
	for card: String in ["MALS", "CURS"]:
		var discard := "ERQA" if card == "MALS" else "MTPT"
		var keep := "MTPT" if card == "MALS" else "ERQA"
		for eligible: bool in [false, true]:
			var duel := Fixtures.build(profile, {"heroes": [
				{"mana": 3, "hand": [card]}, {"mana": 0, "hand": [discard if eligible else keep]},
			]})
			var label := "%s: %s against %s" % [profile.id, card, discard if eligible else keep]
			if duel == null:
				check(false, label + " loads")
				continue
			var offered := ELCombatBrain.weigh(ctx, duel, 2, 20000, 4)
			var cast := offered.any(func(item: Dictionary) -> bool: return item.command.get("card") == card and item.command.get("target") == 1)
			check(cast == eligible, label + (" is worth considering" if eligible else " is omitted from the ordinary search"))

# --- Positions from real duels -----------------------------------------------------

func _profile(game: String) -> ELProfile:
	if profiles.has(game): return profiles[game]
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	var profile := ELProfile.new()
	profiles[game] = profile if not folder.is_empty() and profile.mount(game, folder) else null
	if profiles[game] == null: print("SKIP: no files of %s" % game)
	return profiles[game]

func _positions(only: String) -> void:
	var folder := ProjectSettings.globalize_path("res://").path_join("../tools/duel_ai_positions").simplify_path()
	var names := Array(DirAccess.get_files_at(folder))
	names.sort()
	if names.is_empty(): check(false, "positions found in " + folder)
	for name: String in names:
		if not name.ends_with(".json") or (not only.is_empty() and not name.contains(only)): continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(name)))
		if document is not Dictionary or not document.has("expect"):
			check(false, name + ": readable, with an expectation")
			continue
		var profile := _profile(String(document.state.profile))
		if profile == null: continue
		var duel := ELDuel.new()
		if not duel.restore(profile, document):
			check(false, "%s: restores (%s)" % [name, duel.error])
			continue
		var result := _play(duel, document.expect)
		check(result.is_empty(), "%s: %s%s" % [name.get_basename(), document.get("about", ""), "" if result.is_empty() else " -- " + result])

## Plays the position until the expectation is settled; "" when it is met.
func _play(duel: ELDuel, expect: Dictionary) -> String:
	var side := int(expect.side)
	var kind := String(expect.kind)
	var turn := [duel.round_number, duel.attacker]
	var phase := duel.phase
	var attacked := false
	var army := duel.army(side).size()
	var foes := duel.army(1 - side).size()
	var health := int(duel.heroes[1 - side].health)
	var said: Array[String] = []
	# An ability may be given turns of its hero to be used in (`within`): one
	# that costs health is as well used a turn later as at once.
	var within := int(expect.get("within", 1))
	var own_turns := 1
	var last := turn
	for step in 80 * within:
		if duel.phase == ELDuel.Phase.FINISHED: break
		var over := [duel.round_number, duel.attacker] != turn
		if [duel.round_number, duel.attacker] != last:
			last = [duel.round_number, duel.attacker]
			if duel.attacker == side: own_turns += 1
		match kind:
			"win", "keep", "aim": if over: break
			"survive": if over or duel.phase != ELDuel.Phase.DEFENCE: break
			"attack", "spare", "cast": if over or duel.phase != phase: break
			"use":
				if within > 1:
					if own_turns > within: break
				elif over or duel.phase != phase: break
		var acting := duel.active_side()
		var smart: Array[int] = [acting]
		duel.smart_sides = smart
		var command := ELCombatSearch.think(duel)
		var harm := own_harm(duel, acting, command)
		# A command counts only once the rules have taken it.
		var applied := not command.is_empty() and ELCombatSearch.apply(duel, command)
		if acting == side:
			said.append(_describe(command) + ("" if applied or command.is_empty() else " (refused)"))
			if applied and command.get("kind", "") == "attack": attacked = true
			if applied and kind == "spare" and command.get("kind", "") == "cast" and command.get("card", "") == expect.card: return "cast it: " + ", ".join(said)
			if applied and kind == "use" and command.get("kind", "") == "ability" and command.get("key", "") == expect.ability: return ""
			if applied and kind == "cast" and command.get("kind", "") == "cast" and command.get("card", "") == expect.card: return ""
			if applied and kind == "aim" and not harm.is_empty(): return "aimed at its own side: " + harm + " (" + ", ".join(said) + ")"
		if not applied: duel.end_phase()
	var finished := duel.phase == ELDuel.Phase.FINISHED
	var line := ", ".join(said)
	match kind:
		"win": return "" if finished and duel.winner == side else "no win: " + line
		"survive": return "" if not finished or duel.winner == side else "the hero died: " + line
		"attack": return "" if attacked or (finished and duel.winner == side) else "no attack: " + line
		"use": return "not used: " + line
		"cast": return "not cast: " + line
		"aim": return "" if not expect.get("win", false) or (finished and duel.winner == side) else "no win: " + line
		"keep":
			if finished: return ""
			var lost := duel.army(side).size() < army
			var gained := duel.army(1 - side).size() < foes or int(duel.heroes[1 - side].health) < health
			return "" if not lost or gained else "lost a creature for nothing: " + line
	return ""

## What a command of `side` aims at its own side that harms it ("" for
## nothing): the cards the original opponent keeps for the other side
## (ELCombatSearch.SPELL_SIDES, bit 1 creatures, bit 3 heroes), the hero's
## fireball and the creatures' harmful abilities.
static func own_harm(duel: ELDuel, side: int, command: Dictionary) -> String:
	var target := int(command.get("target", -1))
	if target < 0 or command.get("kind", "") not in ["cast", "ability"]: return ""
	var own := target == side if target < 2 else duel.creatures.has(target) and int(duel.creatures[target].owner) == side
	if not own: return ""
	var flags := 0
	if command.kind == "cast": flags = int(ELCombatSearch.SPELL_SIDES.get(duel.profile.id, {}).get(String(command.card), 0))
	elif String(command.key).get_slice(":", 0) in ["fireball", "sting", "gaze", "hunt", "spores", "tap_target", "tap_race", "pale_devour"]: flags = 0xa
	if not (flags & (8 if target < 2 else 2)): return ""
	return "%s at %s" % [command.get("card", command.get("key", "")), "its hero" if target < 2 else String(duel.creatures[target].card)]

func _describe(command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s%s" % [command.card, " at #%d" % int(command.target) if int(command.get("target", -1)) >= 0 else ""]
		"attack": return "attack #%d" % command.id
		"block": return "#%d blocks #%d" % [command.id, command.target]
		"ability": return "%s of #%d" % [command.key, command.id]
	return "end"

# --- Proofs on hand-made duels -----------------------------------------------------

## A proof of `side` winning within `turns` own turns, on a duel restored
## from a fixture (tools/duel_fixtures.gd).
func _proof(profile: ELProfile, duel: ELDuel, side: int, turns: int, budget := 2000000) -> Dictionary:
	ELCombatSearch._proofs.clear()
	ELCombatSearch._plans.clear()
	return ELCombatBrain.prove(Fixtures.context(profile, side), duel, turns, budget)

func _fixtures() -> void:
	if not ClassDB.class_exists(&"ELNativeDuelBrain") or not ELCombatBrain.available:
		print("SKIP: the compiled engine is not built for this platform")
		return
	var el1 := _profile("el1")
	if el1 == null: return
	# A defence of one choice among several: an unblockable 5/5 attacks a hero
	# at 1 health and 1 ether, whose creatures both rest. Sacrificing the 5/5
	# (ether + power + toughness - 1) pays for three Lesser Healings and the
	# hero lives at 2; the 1/1 pays for only two.
	var duel := Fixtures.build(el1, {"attacker": 1, "phase": "defence", "attacks": [4],
		"heroes": [{"health": 1, "mana": 1, "enchantments": ["SACR", "LSHE", "LSHE", "LSHE"]}, {"health": 20, "mana": 0}],
		"creatures": [{"card": "KBWR", "owner": 0, "power": 1, "toughness": 1, "resting": true},
			{"card": "GROG", "owner": 0, "power": 5, "toughness": 5, "resting": true},
			{"card": "STAB", "owner": 1, "power": 5, "toughness": 5, "flags": ["UB"]}]})
	check(duel != null, "fixture: sacrifice defence restores")
	if duel != null:
		var proof := _proof(el1, duel, 1, 1)
		check(not proof.is_empty() and int(proof.turns) == 0 and int(proof.get("settled", 0)) >= 1,
			"proof: the attack is no win, for sacrificing the 5/5 heals the hero out of reach (%s)" % _proof_said(proof))
	# Attacks strike in the order sent: the disenchanting 3/5 first strips the
	# Stone Skin (1 + 6 = 7 against 7 health), the 6/5 first does not.
	var el2 := _profile("el2")
	duel = null if el2 == null else Fixtures.build(el2, {"heroes": [{"health": 20, "mana": 0}, {"health": 7, "mana": 0, "enchantments": ["STSK"]}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 6, "toughness": 5},
			{"card": "IRAB", "owner": 0, "power": 3, "toughness": 5, "flags": ["Disenchant"]}]})
	if el2 != null: check(duel != null, "fixture: stone skin restores")
	if duel != null:
		var proof := _proof(el2, duel, 0, 1)
		check(int(proof.get("turns", 0)) == 1, "proof: the disenchanter attacks first and the hero falls (%s)" % _proof_said(proof))
		check(Fixtures.play_proof(el2, duel, 0, 1, 2000000) == 0, "proof: the stone skin win holds when played by the rules")
	# Hero abilities deal damage too: two Fireballs (2 each) and 2 ether
	# against 3 health.
	duel = Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 2, "enchantments": ["FRBL", "FRBL"]}, {"health": 3, "mana": 0}], "creatures": []})
	check(duel != null, "fixture: two fireballs restore")
	if duel != null:
		var proof := _proof(el1, duel, 0, 1)
		check(int(proof.get("turns", 0)) == 1 and int(proof.get("positions", 0)) > 0, "proof: two fireballs at 3 health are a win (%s)" % _proof_said(proof))
		check(Fixtures.play_proof(el1, duel, 0, 1, 2000000) == 0, "proof: the fireball win holds when played by the rules")
	# A hand of one card more than the model holds: no proof stands.
	var nine: Array = []
	for i in ELCombatBrain.HAND + 1: nine.append("MGHT")
	duel = Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 0, "hand": nine}, {"health": 20, "mana": 0}], "creatures": []})
	if duel != null:
		var proof := _proof(el1, duel, 0, 1)
		check(bool(proof.get("incomplete", false)) and int(proof.get("turns", 0)) == 0, "proof: a hand of one card too many is told as more than the model holds (%s)" % _proof_said(proof))
	# A spell of any power is read at every power: two 6/6 against 12 health
	# and blockers 1/2 and 1/5 win only by Comets (1 + X) of X2 and X5, which
	# 9 ether pays for and 8 does not. (Comet is no defence spell: the hero
	# attacked cannot answer with it.)
	if el2 != null:
		for ether: int in [9, 8]:
			duel = Fixtures.build(el2, {"heroes": [{"health": 20, "mana": ether, "hand": ["COMT", "COMT"]}, {"health": 12, "mana": 0}],
				"creatures": [{"card": "GROG", "owner": 0, "power": 6, "toughness": 6, "flags": []}, {"card": "GROG", "owner": 0, "power": 6, "toughness": 6, "flags": []},
					{"card": "GROG", "owner": 1, "power": 1, "toughness": 2, "flags": []}, {"card": "GROG", "owner": 1, "power": 1, "toughness": 5, "flags": []}]})
			check(duel != null, "fixture: two comets restore")
			if duel == null: continue
			var proof := _proof(el2, duel, 0, 1)
			check((int(proof.get("turns", 0)) == 1) == (ether == 9), "proof: two Comets and %d ether %s both blockers (%s)" % [ether, "clear" if ether == 9 else "do not clear", _proof_said(proof)])
			if ether == 9 and int(proof.get("turns", 0)) == 1: check(Fixtures.play_proof(el2, duel, 0, 1, 2000000) == 0, "proof: the Comet win holds when played by the rules")
		# Combine gives up any creature for any other: the 9/9 for the flying
		# 1/1, which then stops a flying, trampling 10/10 whole.
		duel = Fixtures.build(el2, {"heroes": [{"health": 20, "mana": 0}, {"health": 5, "mana": 5, "enchantments": ["CMBN"]}],
			"creatures": [{"card": "GROG", "owner": 0, "power": 10, "toughness": 10, "flags": ["Fly", "Trample"]},
				{"card": "GROG", "owner": 1, "power": 9, "toughness": 9, "flags": []}, {"card": "GROG", "owner": 1, "power": 1, "toughness": 1, "flags": ["Fly"]}]})
		check(duel != null, "fixture: combine defence restores")
		if duel != null:
			var proof := _proof(el2, duel, 0, 1)
			check(int(proof.get("turns", 0)) == 0, "proof: the attack is no win, for the 9/9 combined into the flier stops it (%s)" % _proof_said(proof))
		# Blocks fight in the order they were set: the trampling 6/1 stopped by
		# the 0/5 first and the walking horror second sends nothing on, and the
		# flying 5/4 alone leaves the hero at 1.
		duel = Fixtures.build(el2, {"heroes": [{"health": 1, "mana": 0}, {"health": 6, "mana": 0}],
			"creatures": [{"card": "GROG", "owner": 0, "power": 1, "toughness": 1, "flags": []},
				{"card": "GROG", "owner": 0, "power": 5, "toughness": 4, "flags": ["Fly"]},
				{"card": "GROG", "owner": 0, "power": 6, "toughness": 1, "flags": ["Trample"], "enchantments": ["LFGR"]},
				{"card": "WKHR", "owner": 1, "power": 0, "toughness": 1}, {"card": "GROG", "owner": 1, "power": 0, "toughness": 5, "flags": []},
				{"card": "GROG", "owner": 1, "power": 0, "toughness": 1, "flags": []}]})
		check(duel != null, "fixture: ordered blocks restore")
		if duel != null:
			var proof := _proof(el2, duel, 0, 1)
			check(int(proof.get("turns", 0)) == 0, "proof: the attack is no win against blocks set in the right order (%s)" % _proof_said(proof))
			if int(proof.get("turns", 0)) > 0: check(Fixtures.play_proof(el2, duel, 0, 1, 2000000) == 0, "proof: the claimed win holds when played by the rules")
	# What the engine is told under the full policy (the default) hangs on
	# the cards the other hero drew and on the duel's run of chance, which
	# holds the cards both heroes will draw; under the fair policy, set here
	# by name, it hangs on neither. A card that came into the other hand in the
	# open is told by name either way, and a puzzle is always told in full.
	var info_default := ELCombatSearch.smart_engine_info
	check(info_default == "full", "information: the smarter player's policy is \"full\" by default")
	for policy: String in ["full", "fair"]:
		(ELCombatSearch as Script).set("smart_engine_info", policy)
		for what: String in ["the cards the other hero drew", "the duel's run of chance", "a card the other hero was given in the open"]:
			var told: Array = []
			for variant in 2:
				var other: Array = [["MGHT", "MGHT"], ["DELS", "ENFL"]][variant if what != "the duel's run of chance" else 0]
				duel = Fixtures.drawn_hands(el1, other, variant if what == "the duel's run of chance" else 0, what.begins_with("a card"))
				if duel == null: continue
				ELCombatBrain.ask(Fixtures.context(el1, 0), duel, 1, 1000, true, 5)
				told.append(ELCombatBrain.last_packed)
			var hangs: bool = policy == "full" or what.begins_with("a card")
			check(told.size() == 2 and (told[0] != told[1]) == hangs,
				"information: under \"%s\" the packed position %s on %s" % [policy, "hangs" if hangs else "does not hang", what])
	(ELCombatSearch as Script).set("smart_engine_info", "fair")
	# Under the fair policy no win is proved over a hero that may hold a card
	# to stop it: an ogre attacks a hero at 1 health with no blocker, whose
	# book holds a Fog and whose hand a card it drew. With ether for the Fog
	# the win is not proved; with none it is.
	for ether: int in [0, 10]:
		duel = Fixtures.drawn_hands(el1, ["MGHT"])
		if duel == null: continue
		duel.creatures.erase(3)
		duel.heroes[1].health = 1
		duel.heroes[1].mana = ether
		duel.heroes[1].deck = ["STRT", "FOGG"]
		duel.heroes[1].spell_uses = [-1, -1]
		var proof := _proof(el1, duel, 0, 1)
		check((int(proof.get("turns", 0)) == 1) == (ether == 0), "information: a win over a hero with %d ether, a Fog in its book and a card nobody saw is %s (%s)" % [ether, "proved" if ether == 0 else "not proved", _proof_said(proof)])
	duel = Fixtures.drawn_hands(el1, ["DELS", "ENFL"])
	if duel != null:
		check(ELCombatSearch.info_policy(duel) == "fair", "information: with the policy set to \"fair\" a duel whose books deal is read under it")
		(ELCombatSearch as Script).set("smart_engine_info", "full")
		check(ELCombatSearch.info_policy(duel) == "full", "information: with the policy left at \"full\" such a duel is read in full")
		(ELCombatSearch as Script).set("smart_engine_info", "fair")
		duel.setup["puzzle_fixed_hands"] = true
		check(ELCombatSearch.info_policy(duel) == "full", "information: a duel of fixed hands (a puzzle) is read in full")
		duel.setup["puzzle_fixed_hands"] = false
		duel.setup["puzzle_goal"] = {"type": "win", "side": 0}
		check(ELCombatSearch.info_policy(duel) == "full", "information: a duel with a puzzle's objective is read in full")
	(ELCombatSearch as Script).set("smart_engine_info", info_default)
	# Packed puzzles proved from their start, without their solutions, each
	# for a choice a proof once left out: Gnaw on its own graveyard, a sting
	# on its own creature, the exact health to channel, a creature with no
	# power sent beside the guards, and objectives other than a kill.
	ELPuzzles.remember = false
	for wanted: Array in [["el1", "count_the_ashes"], ["el1", "room_for_two"], ["el1", "empty_handed_standard"], ["el1", "dangerous_promotion"],
			["el1", "wings_outlive_wizard"], ["el1", "borrowed_armour"], ["el2", "exact_price"], ["el2", "last_line_of_defence"], ["el2", "shared_escape"],
			# A gain laid on a deluded creature and a beholder mother's ban on walls.
			["el1", "curiosity_inferno_geometry"], ["el2", "curiosity_needed_enemy"],
			# An enchantment's card that comes back to the hand and is cast
			# again, one a weaver copies, a lifeguard laid on the attacker, and
			# a water link an older position keeps on its creature.
			["el1", "paradox_riot_on_repeat"], ["el2", "curiosity_glass"], ["el2", "crossroads_last_reprieve"], ["el1", "curiosity_two_mouths"]]:
		var profile := _profile(String(wanted[0]))
		if profile == null: continue
		var entries := ELPuzzles.list(profile.id)
		for i in entries.size():
			if not String(entries[i].id).ends_with(String(wanted[1])): continue
			var run := ELPuzzles.Run.new()
			if not run.begin(profile, i):
				check(false, "puzzle %s: begins" % wanted[1])
				continue
			var proof := _proof(profile, run.duel, ELPuzzles.Run.SIDE, int(entries[i].turns), 5000000)
			check(int(proof.get("turns", 0)) > 0, "puzzle %s (%s): proved from the start (%s)" % [wanted[1], String(entries[i].get("objective", {}).get("type", "win")), _proof_said(proof)])

func _proof_said(proof: Dictionary) -> String:
	if proof.is_empty(): return "no answer"
	return "turns=%d settled=%d positions=%d aborted=%s unknown=%s incomplete=%s" % [int(proof.get("turns", 0)), int(proof.get("settled", -1)),
		int(proof.get("positions", 0)), str(proof.get("aborted", false)), str(proof.get("unknown", "-")), str(proof.get("incomplete", "-"))]
