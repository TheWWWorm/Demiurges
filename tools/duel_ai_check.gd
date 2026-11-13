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
##   Both sides are played by the option as shipped, with no thinking between
##   the commands of a chosen plan, as in the game.
##
##   godot --headless --path game --script ../tools/duel_ai_check.gd [-- --only=<text>]
##
## Needs the original games' files (user://profiles.json or --el1=/--el2=); a
## game without them is skipped. Positions come from tools/duel_ai_audit.gd
## and tools/duel_ai_regret.gd (--save), with an "expect" entry added.

const POSITIONS := "res://../tools/duel_ai_positions"
const FLY := 1
const FIRST := 2
const RESTING := 8192
const SICK := 16384
const ATTACKING := 65536
const NO_UNTAP := 256
const HEADER := 15
const FIXED := HEADER + 2 * (16 + 32 + 48)

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
	if only.is_empty() or "lookahead".contains(only): _lookahead()
	_positions(only)
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# --- The compiled lookahead ------------------------------------------------------

## One call of the library. heroes: [health, ether, channels] per side; units:
## [id, owner, power, toughness, flags, attacker it blocks or -1, wake cost];
## hand: the computer's creature cards as [cost, power, toughness].
func _ask(ai: int, attacker: int, phase: int, turns: int, heroes: Array, units: Array, cards := false, hand: Array = []) -> Dictionary:
	var state := PackedInt32Array()
	state.resize(FIXED + units.size() * 13)
	state[0] = 3
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
		var at := HEADER + side * 16
		var hero: Array = heroes[side]
		state[at] = hero[0]
		state[at + 1] = hero[1] if hero.size() > 1 else 5
		state[at + 2] = hero[2] if hero.size() > 2 else 5
	var hands := HEADER + 32 + 64
	for i in 12: state[hands + i * 8] = -1
	for i in hand.size():
		var slot := hands + ai * 48 + i * 8
		state[slot] = hand[i][0]
		state[slot + 1] = hand[i][1]
		state[slot + 2] = hand[i][2]
		state[slot + 3] = SICK
		state[slot + 5] = int((600 + 800 * int(hand[i][2]) + 1200 * int(hand[i][1])) * 0.7) - 800
		state[slot + 6] = state[slot + 5] - 350
	var u := FIXED
	for unit: Array in units:
		for i in 5: state[u + i] = unit[i]
		state[u + 8] = 600 + 800 * int(unit[3]) + 1200 * int(unit[2])
		state[u + 9] = state[u + 8] - 500
		state[u + 11] = unit[5] if unit.size() > 5 else -1
		state[u + 12] = unit[6] if unit.size() > 6 else 0
		u += 13
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
	for step in 80:
		if duel.phase == ELDuel.Phase.FINISHED: break
		var over := [duel.round_number, duel.attacker] != turn
		match kind:
			"win", "keep": if over: break
			"survive": if over or duel.phase != ELDuel.Phase.DEFENCE: break
			"attack", "spare": if over or duel.phase != phase: break
		var acting := duel.active_side()
		var smart: Array[int] = [acting]
		duel.smart_sides = smart
		var command := ELCombatSearch.think(duel)
		if acting == side:
			said.append(_describe(command))
			if command.get("kind", "") == "attack": attacked = true
			if kind == "spare" and command.get("kind", "") == "cast" and command.get("card", "") == expect.card: return "cast it: " + ", ".join(said)
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	var finished := duel.phase == ELDuel.Phase.FINISHED
	var line := ", ".join(said)
	match kind:
		"win": return "" if finished and duel.winner == side else "no win: " + line
		"survive": return "" if not finished or duel.winner == side else "the hero died: " + line
		"attack": return "" if attacked or (finished and duel.winner == side) else "no attack: " + line
		"keep":
			if finished: return ""
			var lost := duel.army(side).size() < army
			var gained := duel.army(1 - side).size() < foes or int(duel.heroes[1 - side].health) < health
			return "" if not lost or gained else "lost a creature for nothing: " + line
	return ""

func _describe(command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s" % command.card
		"attack": return "attack #%d" % command.id
		"block": return "#%d blocks #%d" % [command.id, command.target]
		"ability": return "%s of #%d" % [command.key, command.id]
	return "end"
