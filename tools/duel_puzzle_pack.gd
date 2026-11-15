extends SceneTree
## Rates generated battle-puzzle candidates for review.
##
## tools/duel_ai_puzzles.gd finds positions with a forced win a few turns
## off. This tool takes those of the first hero, has the compiled engine
## prove each win and the fewest turns it takes, plays it through against
## every defence the game can put up, sets aside the ones a player wins
## without having to think (see OBVIOUS), counts how many first commands keep
## the win, and writes a separate candidate pack, easiest tier first. The
## authored collection is maintained separately; generated output does not
## replace it without an explicit --out-pack destination.
##
##   Rating (each shard writes <out>.<shard>):
##   godot --headless --path game --script ../tools/duel_puzzle_pack.gd --
##       --rate=<folder> --out=<file> [--game=el1|el2] [--shard=I/N]
##
##   Packing the rated ones (--skip leaves out the ones tools/puzzles_check.gd
##   failed when it played them through the battle screen):
##   godot --headless --path game --script ../tools/duel_puzzle_pack.gd --
##       --pack=<folder> --ratings=<file> [--game=el1|el2] [--count=N] [--skip=<id>,...]
##       [--out-pack=<path>]
##
## Generated candidates go to res://puzzles/generated/<game>.json by default.
## The authored collection is never replaced implicitly. Installing a generated
## pack over it requires an explicit --out-pack=res://puzzles/<game>.json.

## How the engine reads when it solves a puzzle and when it defends one.
const DEEP := {"engine": true, "engine_phases": 6, "engine_steps": 24, "engine_budget": 3000000, "engine_table": true, "engine_ms": 0, "engine_prove_share": 50}
## The remake option's own search, without the compiled engine.
const SEARCH := {"engine": false}
## The computer player as the option ships (by positions read, not by the clock).
const SHIPPED := {"engine_ms": 0}
## The computer player without the option.
const PLAIN := {"plain": true}
## No thought at all: every creature attacks, nothing is cast or blocked.
const BLUNT := {"blunt": true}
## Nothing at all: every phase is ended as it stands.
const IDLE := {"idle": true}
## The first thing a player tries: what the plain computer player would cast
## or use, then every creature sent forward. Players found the easiest level
## too easy when it was the one the plain computer player won by itself, and
## a puzzle this solves is just "cast the obvious spell and attack with
## everything": none of them is offered.
const OBVIOUS := {"obvious": true}
## Positions a proof may read, and the most turns a puzzle may take.
const PROOF := 20000000
const LONGEST := 4

var profile: ELProfile
var defaults := {}

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback

## Makes the search play as `setting` says, everything else as it ships.
func _use(setting: Dictionary) -> void:
	for name: String in defaults: (ELCombatSearch as Script).set("smart_" + name, defaults[name])
	for name: String in setting:
		if name == "plain": continue
		if not defaults.has(name): defaults[name] = (ELCombatSearch as Script).get("smart_" + name)
		(ELCombatSearch as Script).set("smart_" + name, setting[name])

func _think(duel: ELDuel, setting: Dictionary) -> Dictionary:
	if setting.has("idle"): return {}
	if setting.has("blunt"): return _charge(duel)
	if setting.has("obvious"):
		# Casts and abilities as the plain player chooses them; its attacks
		# (and its ending of the attack phase) become a charge of everything.
		var plain := _think(duel, PLAIN)
		if duel.phase != ELDuel.Phase.ATTACK or String(plain.get("kind", "end_phase")) in ["cast", "ability"]: return plain
		return _charge(duel)
	_use(setting)
	var smart: Array[int] = []
	if not setting.has("plain"): smart.append(duel.active_side())
	duel.smart_sides = smart
	return ELCombatSearch.think(duel, {})

## The next creature sent forward in the attack phase, or {} when all are.
func _charge(duel: ELDuel) -> Dictionary:
	if duel.phase != ELDuel.Phase.ATTACK: return {}
	for creature: Dictionary in duel.army(duel.active_side()):
		if duel.attacks.has(int(creature.id)): continue
		var command := {"kind": "attack", "id": int(creature.id)}
		if ELCombatSearch.apply(duel.search_copy(), command): return command
	return {}

## A command in a few words: what the hint shows and what the log lists.
func _said(duel: ELDuel, command: Dictionary) -> Dictionary:
	var kind := String(command.get("kind", "end_phase"))
	var out := {"kind": kind}
	var id := int(command.get("id", -1))
	if kind == "cast": out.card = String(command.get("card", ""))
	elif duel.creatures.has(id): out.card = String(duel.creatures[id].card)
	if kind == "ability": out.key = String(command.get("key", ""))
	var target := int(command.get("target", -99))
	if kind in ["cast", "ability"]:
		if duel.creatures.has(target):
			out.target = String(duel.creatures[target].card)
			out.target_side = int(duel.creatures[target].owner)
		elif target in [0, 1]: out.target_hero = target
	return out

## Plays a copy of the position on, `side` by `attack` and the other hero by
## `defence`: how many of its own turns `side` took to win (counting the one
## the position stands in), or 0 when it did not win within `limit` of them.
## `line` receives what `side` played.
func _win_in(start: ELDuel, side: int, attack: Dictionary, defence: Dictionary, limit: int, line: Array = []) -> int:
	var duel := start.search_copy()
	var keep: Dictionary = ELCombatSearch._plans.duplicate()
	var turns := 1 if duel.attacker == side else 0
	var last := duel.turn_serial
	var guard := 0
	while duel.phase != ELDuel.Phase.FINISHED and guard < 400:
		guard += 1
		if duel.turn_serial != last:
			last = duel.turn_serial
			if duel.attacker == side:
				turns += 1
				if turns > limit: break
		var mine := duel.active_side() == side
		var command := _think(duel, attack if mine else defence)
		if mine: line.append(_said(duel, command))
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	var won := duel.phase == ELDuel.Phase.FINISHED and duel.winner == side and turns <= limit
	if duel.scripts != null and duel.scripts.search_only: duel.scripts.close()
	ELCombatSearch._plans = keep
	_use({})
	return turns if won else 0

## What the engine is told of `side` when it is asked for a proof.
func _context(side: int) -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.chosen_weights(ctx.second)
	ctx.remember = true
	ctx.foe_health = ELCombatSearch.smart_foe_health
	ctx.brain_cards = ELCombatSearch.smart_brain_cards
	return ctx

func _initialize() -> void:
	var game := _arg("game", "el1")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	profile = ELProfile.new()
	if saved is not Dictionary or not profile.mount(game, String(saved.get(game, ""))):
		printerr("Game files are required.")
		quit(1)
		return
	if not _arg("rate", "").is_empty():
		if not ELCombatBrain.available:
			printerr("The compiled engine is not loaded.")
			quit(1)
			return
		_rate(_arg("rate", ""), game, _arg("out", "ratings"), _arg("shard", "0/1"))
	elif not _arg("pack", "").is_empty():
		if not _pack(_arg("pack", ""), game, _arg("ratings", "ratings"), int(_arg("count", "30")), Array(_arg("skip", "").split(",", false)), _arg("out-pack", "")):
			quit(1)
			return
	print("DONE")
	quit(0)

func _names(folder: String, game: String) -> Array:
	var names: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.begins_with(game + "_") and name.ends_with(".json"): names.append(name)
	names.sort()
	return names

func _rate(folder: String, game: String, out: String, shard: String) -> void:
	var names := _names(folder, game)
	var file := FileAccess.open("%s.%s" % [out, shard.get_slice("/", 0)], FileAccess.WRITE)
	for i in names.size():
		if i % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(names[i])))
		if document is not Dictionary or not document.has("expect") or not document.has("format"): continue
		var side := int(document.expect.side)
		# The player sits on the first hero's side.
		if side != 0: continue
		var duel := ELDuel.new()
		if not duel.restore(profile, document): continue
		# The win must be one no defence stops, and not one of this very turn.
		var proof := ELCombatBrain.prove(_context(side), duel, LONGEST, PROOF)
		if not _completed(proof):
			print("UNRATED %s: win proof unavailable or budget exhausted" % String(names[i]))
			continue
		var turns := int(proof.turns)
		if turns < 2:
			print("PASSED %s proven=%d" % [String(names[i]), turns])
			continue
		var line: Array = []
		var row := {"id": String(names[i]).get_basename(), "turns": turns, "found_by": document.expect.get("found_by", []), "proof_complete": true}
		# The proof holds in the game itself: won in time whoever defends,
		# by the deep engine and by the computer player as it ships.
		row.against = {"deep": _win_in(duel, side, DEEP, DEEP, turns, line), "search": _win_in(duel, side, DEEP, SEARCH, turns),
			"shipped": _win_in(duel, side, DEEP, SHIPPED, turns), "plain": _win_in(duel, side, DEEP, PLAIN, turns)}
		row.shipped = _win_in(duel, side, SHIPPED, DEEP, turns)
		row.sound = int(row.shipped) > 0 and (row.against as Dictionary).values().all(func(taken: int) -> bool: return taken > 0)
		row.line = line
		row.casts = line.filter(func(step: Dictionary) -> bool: return step.kind == "cast").size()
		row.abilities = line.filter(func(step: Dictionary) -> bool: return step.kind == "ability").size()
		row.hand = duel.heroes[side].hand.size()
		row.mine = duel.army(side).size()
		row.theirs = duel.army(1 - side).size()
		# Won by the computer player without the option; by sending
		# everything forward each turn; by doing nothing.
		row.plain = bool(row.sound) and _win_in(duel, side, PLAIN, DEEP, turns) > 0
		# Against the engine and against the opponent a player will meet: a
		# position the game's own computer player loses by itself is no puzzle.
		row.blunt = bool(row.sound) and (_win_in(duel, side, BLUNT, DEEP, turns) > 0 or _win_in(duel, side, BLUNT, PLAIN, turns) > 0)
		row.idle = bool(row.sound) and (_win_in(duel, side, IDLE, DEEP, turns) > 0 or _win_in(duel, side, IDLE, PLAIN, turns) > 0)
		row.obvious = bool(row.sound) and (_win_in(duel, side, OBVIOUS, DEEP, turns) > 0 or _win_in(duel, side, OBVIOUS, PLAIN, turns) > 0)
		# How many of the first commands keep the win: each is played, and
		# the win proved again from where it leaves the duel.
		var seen := {}
		var keys := 0
		var unknown := 0
		if bool(row.sound) and not _thoughtless(row):
			for item: Dictionary in ELCombatBrain.weigh(_context(side), duel, 2, 200000, 10):
				var command: Dictionary = item.command
				if command.is_empty(): continue
				var text := JSON.stringify(_said(duel, command)) + str(command.get("id", ""))
				if seen.has(text): continue
				var after := duel.search_copy()
				var played: bool = after.end_phase() if String(command.get("kind", "end_phase")) == "end_phase" else ELCombatSearch.apply(after, command)
				if not played: continue
				seen[text] = true
				# A turn passed without an attack is one of the puzzle's turns gone.
				var left := turns if after.attacker == side else turns - 1
				if after.phase == ELDuel.Phase.FINISHED:
					if after.winner == side: keys += 1
				elif left >= 1:
					var again := ELCombatBrain.prove(_context(side), after, left, PROOF / 4)
					if not _completed(again):
						# Unknown is not losing: counting a budget cutoff as a loss
						# can turn an ordinary position into a false unique opening.
						unknown += 1
					elif int(again.turns) > 0 and int(again.turns) <= left: keys += 1
		row.moves = seen.size()
		row.keys = keys
		row.unknown_openings = unknown
		row.openings_complete = unknown == 0 and not seen.is_empty()
		file.store_line(JSON.stringify(row))
		file.flush()
		print("RATED %s turns=%d sound=%s plain=%s blunt=%s obvious=%s idle=%s casts=%d moves=%d keys=%d unknown=%d" % [row.id, turns, str(row.sound), str(row.plain), str(row.blunt), str(row.obvious), str(row.idle), int(row.casts), int(row.moves), int(row.keys), unknown])

## Missing or exhausted proofs establish neither a win nor a loss.
func _completed(proof: Dictionary) -> bool:
	return proof.has("turns") and proof.has("aborted") and not bool(proof.aborted)

## Old rating rows did not distinguish losses from exhausted opening searches.
## They must be rated again before their opening selectivity can be trusted.
func _complete_rating(row: Dictionary) -> bool:
	return bool(row.get("proof_complete", false)) and bool(row.get("openings_complete", false)) and int(row.get("unknown_openings", -1)) == 0

## Solved by a simple baseline: the plain computer player, sending everything
## forward, the plain cast and a charge, or doing nothing.
func _thoughtless(row: Dictionary) -> bool:
	return bool(row.plain) or bool(row.blunt) or bool(row.obvious) or bool(row.idle)

## Share of the first commands that keep the win.
func _key_share(row: Dictionary) -> float:
	return float(row.keys) / float(row.moves) if int(row.moves) > 0 else 1.0

## A generated candidate's opening-selectivity tier, not a human difficulty
## proof: 3 one tested command keeps the win, 1 several do in a two-turn
## position, 2 the rest. Unknown proofs have no tier and cannot be packed.
func _level(row: Dictionary) -> int:
	if not _complete_rating(row): return 0
	if int(row.keys) == 1 and int(row.moves) >= 4: return 3
	if int(row.turns) == 2 and _key_share(row) >= 0.25: return 1
	return 2

## What makes one worth playing: spells and abilities take part, and few
## first commands keep the win.
func _worth(row: Dictionary) -> float:
	var worth := 3.0
	worth += minf(float(row.casts) + float(row.abilities), 3.0)
	if int(row.moves) > 0 and int(row.keys) > 0:
		worth += 4.0 * (1.0 - float(row.keys) / float(row.moves))
	worth += 0.25 * minf(float(row.mine) + float(row.theirs), 8.0)
	return worth

func _authored_pack(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if document is not Dictionary or document.get("puzzles") is not Array: return false
	if int(document.get("version", 0)) >= 2: return true
	return (document.puzzles as Array).any(func(entry: Variant) -> bool: return entry is Dictionary and bool(entry.get("authored", false)))

func _pack(folder: String, game: String, ratings: String, count: int, skipped: Array, output_path := "") -> bool:
	var explicit_output := not output_path.is_empty()
	var target := output_path if explicit_output else "res://puzzles/generated/%s.json" % game
	if _authored_pack(target) and not explicit_output:
		printerr("Refusing to replace an authored pack at %s. Choose --out-pack=<path> explicitly." % target)
		return false
	if explicit_output and _authored_pack(target): print("Explicit --out-pack replaces authored pack: %s" % target)
	else: print("Generated puzzle output: %s" % target)
	if not explicit_output: print("The playable authored collection is unchanged; --out-pack selects a replacement destination explicitly.")
	var rows: Array = []
	var base := ratings.get_base_dir()
	for name: String in DirAccess.get_files_at(base):
		if not name.begins_with(ratings.get_file() + "."): continue
		for text: String in FileAccess.get_file_as_string(base.path_join(name)).split("\n", false):
			var row: Variant = JSON.parse_string(text)
			if row is Dictionary and String(row.get("id", "")).begins_with(game + "_"): rows.append(row)
	# Sound ones only, none won without thought (ratings from before the
	# obvious player count as won by it), and none in which every first
	# command wins.
	var incomplete := rows.filter(func(row: Dictionary) -> bool: return not _complete_rating(row)).size()
	if incomplete > 0: print("SKIPPED %d incomplete or legacy ratings; rerun --rate to finish their opening proofs." % incomplete)
	rows = rows.filter(func(row: Dictionary) -> bool:
		return _complete_rating(row) and bool(row.sound) and row.has("obvious") and not _thoughtless(row) and int(row.keys) >= 1 and int(row.keys) < int(row.moves) and not skipped.has(String(row.id)))
	# One position out of each duel: the best of its turns.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _worth(a) > _worth(b) if _worth(a) != _worth(b) else String(a.id) < String(b.id))
	var duels := {}
	var kept: Array = []
	for row: Dictionary in rows:
		var from := String(row.id).get_slice("_", 2)
		if duels.has(from): continue
		duels[from] = true
		kept.append(row)
	kept = kept.slice(0, count)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _level(a) != _level(b): return _level(a) < _level(b)
		if int(a.turns) != int(b.turns): return int(a.turns) < int(b.turns)
		return String(a.id) < String(b.id))
	var puzzles: Array = []
	for row: Dictionary in kept:
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(String(row.id) + ".json")))
		puzzles.append({"id": String(row.id), "turns": int(row.turns), "level": _level(row), "hint": (row.line as Array)[0] if not (row.line as Array).is_empty() else {}, "state": document.state})
		print("PACKED %s turns=%d level=%d worth=%.2f keys=%d of %d" % [String(row.id), int(row.turns), _level(row), _worth(row), int(row.keys), int(row.moves)])
	if puzzles.is_empty():
		printerr("No eligible puzzles with completed proofs; no output file was changed.")
		return false
	var parent := target.get_base_dir()
	if not parent.is_empty() and DirAccess.make_dir_recursive_absolute(parent) != OK:
		printerr("Cannot create puzzle output directory: %s" % parent)
		return false
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write generated puzzle pack: %s" % target)
		return false
	file.store_string(JSON.stringify({"format": "etherlords-puzzles", "version": 1, "game": game, "puzzles": puzzles}, "", true, true))
	print("PACKED %d of %d rated into %s" % [puzzles.size(), rows.size(), target])
	return true
