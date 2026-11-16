extends SceneTree
## Fixed trade and planning positions for the smarter computer opponent: each
## is a small duel (tools/duel_fixtures.gd) where one choice is plainly better
## over the next turns than the one that looks good at once, played by the
## opponent as in a battle (ELCombatSearch.think and ELPracticeAI.send for
## the side to act, through its phase) and judged by what it did: blocks (chump or value, or none),
## blockers held back, the target of a removal spell, a spell kept for a
## better target, the race against the ether disturbance. A position goes in
## only where playing both choices out with the smarter player on both sides
## bears the judgement out: a double block that the rules do not let kill
## the attacker, and a removal kept for a creature the other hero never gets
## through with, were taken out on that ground.
##
##   godot --headless --path game --script ../tools/duel_trade_corpus.gd -- \
##       [--game=el1|el2|both] [--set=name=value,...] [--only=<text>] [--repeat=N]
##
## --set overrides ELCombatSearch's `smart_*` variables as the bench does
## (the `smart_` prefix left out), so that a setting can be screened here
## before it is played in whole duels. --repeat plays each position N times
## (the think is limited by time, so a close choice may differ from run to
## run). Prints PASS/FAIL per position and play, and TOTAL passed/played.
## --saved=<folder> also reads the positions tools/duel_ai_regret.gd saved
## there (--save): each holds the command the opponent chose and a command
## that won more of the play-outs; the position is asked again and counted
## BETTER (the better command), WORSE (the one that did worse) or OTHER.
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var passed := 0
var saved_tally := {"better": 0, "worse": 0, "other": 0}
var played := 0

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func _profile(game: String) -> ELProfile:
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount(game, folder): return null
	return profile

func _initialize() -> void:
	for item: String in _arg("set", "").split(",", false):
		(ELCombatSearch as Script).set("smart_" + item.get_slice("=", 0), str_to_var(item.get_slice("=", 1)))
	var games := ["el1", "el2"] if _arg("game", "both") == "both" else [_arg("game", "el1")]
	for game: String in games:
		var profile := _profile(game)
		if profile == null:
			print("SKIP %s: no game files" % game)
			continue
		for position: Dictionary in _positions():
			if not _arg("only", "").is_empty() and not String(position.name).contains(_arg("only", "")): continue
			for n in int(_arg("repeat", "1")): _play(profile, position, n)
		if not _arg("saved", "").is_empty(): _saved(profile, _arg("saved", ""))
	print("TOTAL passed=%d played=%d" % [passed, played])
	if not _arg("saved", "").is_empty(): print("SAVED better=%d worse=%d other=%d" % [saved_tally.better, saved_tally.worse, saved_tally.other])
	quit(0)

## A plain creature of the given strength (ORSH has no ability of its own).
static func _c(owner: int, power: int, toughness: int, extra := {}) -> Dictionary:
	var c := {"card": "ORSH", "owner": owner, "power": power, "toughness": toughness, "flags": []}
	c.merge(extra, true)
	return c

func _positions() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	# 1. Value block: a 4/4 comes at a hero with plenty of health; the 2/6
	# takes it without loss, and the 1/1 beside it would not make the kill
	# (1 + 2 < 4): it would only throw itself away.
	list.append({"name": "value block, no chump at full health", "side": 0, "spec": {"attacker": 1, "phase": "defence", "attacks": [4],
		"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 1, 1), _c(0, 2, 6), _c(1, 4, 4)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return d.creatures.has(2)})
	# 2. Chump block that is needed: the attack is lethal unblocked.
	list.append({"name": "chump block when the attack is lethal", "side": 0, "spec": {"attacker": 1, "phase": "defence", "attacks": [3],
		"heroes": [{"health": 4, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 1, 1), _c(1, 5, 5)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return int(d.heroes[0].health) > 0 and d.winner != 1})
	# 3. Hold the blocker: sending the only creature lets the other hero's two
	# 4/1s through for 8 against 6 health next turn.
	list.append({"name": "hold the only blocker against a lethal swing back", "side": 0, "spec": {"attacker": 0,
		"heroes": [{"health": 6, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 3, 3), _c(1, 4, 1), _c(1, 4, 1)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return not d.attacks.has(2)})
	# 4. Removal on the threat: Rift on the 8/8, not on the 1/1.
	list.append({"name": "removal on the real threat", "side": 0, "spec": {"attacker": 0,
		"heroes": [{"health": 12, "mana": 10, "hand": ["RIFT"]}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 2, 2), _c(1, 8, 8), _c(1, 1, 1)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return not d.creatures.has(3)})
	# 6. Trade up: the 3/2 attacker is blocked best by the 2/4 (it kills
	# nothing but loses nothing); blocking with the 3/3 trades a creature for
	# a creature of the same worth, the 2/4 keeps the board.
	list.append({"name": "block that loses nothing over an even trade", "side": 0, "spec": {"attacker": 1, "phase": "defence", "attacks": [4],
		"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 3, 3), _c(0, 2, 4), _c(1, 3, 2)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return d.creatures.has(2) and d.creatures.has(3)})
	# 7. Race: the other hero is at 4 and has no blocker; sending everything
	# wins now, holding back loses tempo for nothing.
	list.append({"name": "send everything for the win", "side": 0, "spec": {"attacker": 0,
		"heroes": [{"health": 3, "mana": 0}, {"health": 4, "mana": 0}],
		"creatures": [_c(0, 2, 2), _c(0, 2, 2), _c(1, 5, 5, {"resting": true})]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return d.attacks.has(2) and d.attacks.has(3)})
	# 8. Do not attack into a bad trade: the 3/3 would be blocked by the 5/5
	# and die for nothing.
	list.append({"name": "no attack into a losing block", "side": 0, "spec": {"attacker": 0,
		"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_c(0, 3, 3), _c(1, 5, 5)]},
		"good": func(d: ELDuel, _b: ELDuel) -> bool: return not d.attacks.has(2)})
	return list

## Plays the position's side through its phase as in a battle (one request,
## the think, the sending, which ends the phase where the opponent ends it)
## and judges the duel where the phase has passed on: after the fight for a
## defence, with the attackers still declared for an attack.
func _play(profile: ELProfile, position: Dictionary, n: int) -> void:
	var duel := Fixtures.build(profile, position.spec)
	if duel == null:
		print("SKIP %s %s: fixture does not restore" % [profile.id, position.name])
		return
	var start := duel.search_copy()
	var side := int(position.side)
	var phase := duel.phase
	var smart: Array[int] = [side]
	duel.smart_sides = smart
	ELCombatSearch.reset_caches()
	for steps in 40:
		if duel.phase != phase or duel.active_side() != side: break
		var asked := ELCombatSearch.request(duel)
		var command := ELCombatSearch.think(duel, {}, false, asked)
		if command.is_empty():
			duel.end_phase()
			continue
		ELPracticeAI.send(duel, command, false, asked)
	var good: bool = (position.good as Callable).call(duel, start)
	played += 1
	if good: passed += 1
	print("%s %s %s #%d: %s" % ["PASS" if good else "FAIL", profile.id, position.name, n, _said(duel)])

## The saved positions of one game in `folder`, asked again.
func _saved(profile: ELProfile, folder: String) -> void:
	# The folder itself, or its subfolder named for the game.
	if DirAccess.dir_exists_absolute(folder.path_join(profile.id)): folder = folder.path_join(profile.id)
	var dir := DirAccess.open(folder)
	if dir == null: return
	var names := Array(dir.get_files()).filter(func(f: String) -> bool: return f.begins_with(profile.id + "-") and f.ends_with(".json"))
	names.sort()
	for name: String in names:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(name)))
		if not data is Dictionary or not data.has("found"): continue
		var duel := ELDuel.new()
		if not duel.restore(profile, data):
			print("SKIP %s: %s" % [name, duel.error])
			continue
		var side := int(data.found.side)
		var smart: Array[int] = [side]
		duel.smart_sides = smart
		ELCombatSearch.reset_caches()
		var asked := ELCombatSearch.request(duel)
		var command := ELCombatSearch.think(duel, {}, false, asked)
		var verdict := "other"
		if _same(command, data.found.better): verdict = "better"
		elif _same(command, data.found.chosen): verdict = "worse"
		saved_tally[verdict] += 1
		print("%s %s regret=%.2f: %s (better %s, worse %s)" % [verdict.to_upper(), name, float(data.found.regret), str(command), str(data.found.better), str(data.found.chosen)])

## Two commands alike, the saved one having come through JSON (numbers as floats).
static func _same(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["kind", "id", "target", "key", "card", "hand", "choice", "amount"]:
		var x: Variant = a.get(key)
		var y: Variant = b.get(key)
		if (x == null) != (y == null): return false
		if x == null: continue
		if (x is int or x is float) and (y is int or y is float):
			if int(x) != int(y): return false
		elif str(x) != str(y): return false
	return true

func _said(d: ELDuel) -> String:
	var parts: Array[String] = []
	parts.append("attacks %s" % str(d.attacks))
	parts.append("blocks %s" % str(d.blocks))
	parts.append("creatures %s" % str(d.creatures.keys()))
	parts.append("health %d/%d" % [int(d.heroes[0].health), int(d.heroes[1].health)])
	if d.phase == ELDuel.Phase.FINISHED: parts.append("winner %d" % d.winner)
	return ", ".join(parts)
