extends SceneTree
## Winning-line puzzles for the duel opponent.
##
## A puzzle is a position out of a duel's last turns in which the hero to
## move wins within a few turns whatever the other hero does, though not at
## once: the compiled engine has read every command of both heroes and found
## the fewest turns the win takes, and the deep engine has then won it in
## those turns, under the game's own rules, against its own defence and the
## shipped search's. Solving one means winning it against the deep engine's
## defence in no more turns than that.
##
##   Finding them (each shard writes its own files into the folder):
##   godot --headless --path game --script ../tools/duel_ai_puzzles.gd --
##       --mine=<folder> [--game=el1|el2] [--duels=N] [--shard=I/N]
##
##   Solving them with an opponent setting (as tools/duel_ai_bench.gd names one):
##   godot --headless --path game --script ../tools/duel_ai_puzzles.gd --
##       --solve=<folder> [--game=el1|el2] --a=smart:engine=true,engine_phases=6
##       [--shard=I/N] [--slack=N]
##   `solved` counts wins within the puzzle's turns, `won` those within N more.
##
##   Proving them (the engine reads every command of both heroes and says
##   in how many turns the win cannot be stopped):
##   godot --headless --path game --script ../tools/duel_ai_puzzles.gd --
##       --prove=<folder> [--game=el1|el2] [--budget=N] [--turns=N] [--shard=I/N]
##       [--rewrite=1]  (a proven puzzle is kept with its proven turns)

## How the engine reads when it looks for puzzles and when it defends one.
const DEEP := {"engine": true, "engine_phases": 6, "engine_steps": 24, "engine_budget": 3000000, "engine_table": true, "engine_ms": 0, "engine_prove_share": 50}
## The remake option's own search, without the compiled engine.
const SEARCH := {"engine": false}
## Own turns a puzzle may take, counting the one it starts in.
const LONGEST := 4
## Positions a proof may read while puzzles are looked for.
const PROOF := 5000000

var profile: ELProfile
var defaults := {}

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback

## "smart:name=value,..." as a dictionary of settings; "smart" alone is the
## shipped search.
func _setting(text: String) -> Dictionary:
	var out := {}
	if text.get_slice(":", 0) == "search": out["engine"] = false
	for item: String in text.get_slice(":", 1).split(",", false):
		var name := item.get_slice("=", 0)
		var now: Variant = (ELCombatSearch as Script).get("smart_" + name)
		var value := item.get_slice("=", 1)
		out[name] = (value == "true") if now is bool else (float(value) if now is float else int(value))
	return out

## Makes the search play as `setting` says, everything else as it ships.
func _use(setting: Dictionary) -> void:
	for name: String in defaults: (ELCombatSearch as Script).set("smart_" + name, defaults[name])
	for name: String in setting:
		if not defaults.has(name): defaults[name] = (ELCombatSearch as Script).get("smart_" + name)
		(ELCombatSearch as Script).set("smart_" + name, setting[name])

func _think(duel: ELDuel, setting: Dictionary, stats: Dictionary) -> Dictionary:
	_use(setting)
	var smart: Array[int] = [duel.active_side()]
	duel.smart_sides = smart
	return ELCombatSearch.think(duel, stats)

## Plays a copy of the position on, `side` by `attack` and the other hero by
## `defence`: how many of its own turns `side` took to win (counting the one
## the position stands in), or 0 when it did not win within `limit` of them.
func _win_in(start: ELDuel, side: int, attack: Dictionary, defence: Dictionary, limit: int) -> int:
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
		var command := _think(duel, attack if duel.active_side() == side else defence, {})
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	var won := duel.phase == ELDuel.Phase.FINISHED and duel.winner == side and turns <= limit
	if duel.scripts != null and duel.scripts.search_only: duel.scripts.close()
	ELCombatSearch._plans = keep
	_use({})
	return turns if won else 0

func _initialize() -> void:
	var game := _arg("game", "el1")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	profile = ELProfile.new()
	if saved is not Dictionary or not profile.mount(game, String(saved.get(game, ""))):
		printerr("Game files are required.")
		quit(1)
		return
	if not ELCombatBrain.available:
		printerr("The compiled engine is not loaded.")
		quit(1)
		return
	var shard := _arg("shard", "0/1")
	if not _arg("mine", "").is_empty(): _mine(_arg("mine", ""), game, int(_arg("duels", "16")), shard)
	elif not _arg("solve", "").is_empty(): _solve(_arg("solve", ""), game, _arg("a", "smart"), shard)
	elif not _arg("prove", "").is_empty(): _prove(_arg("prove", ""), game, shard)
	print("DONE")
	quit(0)

func _mine(folder: String, game: String, duels: int, shard: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var letters := {"Red": "R", "Green": "G", "Blue": "U", "Black": "B"}
	var books: Array = []
	for faction: String in ELCatalog.STARTERS.keys():
		books.append({"faction": faction, "deck": ELCatalog.STARTERS[faction], "level": 1})
		for level in range(2, 7):
			var name := "PR%s%d" % [String(letters.get(faction, "?")), level]
			if not ELCatalog.deck(profile, name).is_empty(): books.append({"faction": faction, "deck": name, "level": level * 2})
	var random := RandomNumberGenerator.new()
	var found := 0
	for n in duels:
		if n % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		random.seed = hash([53, n])
		var first: Dictionary = books[random.randi() % books.size()]
		var matching := books.filter(func(book: Dictionary) -> bool: return book.level == first.level)
		var duel := ELDuel.new()
		if not duel.start(profile, 9000 + n, {"players": [first, matching[random.randi() % matching.size()]]}): continue
		# The duel is played by the engine as it ships against the search, and
		# the position is kept each time a turn begins.
		var starts: Array = []
		var last := -1
		var guard := 0
		while duel.phase != ELDuel.Phase.FINISHED and guard < 900 and duel.round_number < 40:
			guard += 1
			if duel.phase == ELDuel.Phase.ATTACK and duel.turn_serial != last:
				last = duel.turn_serial
				starts.append({"side": duel.attacker, "serial": last, "state": duel.snapshot()})
			var command := _think(duel, {"engine": duel.active_side() == n % 2}, {})
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
		_use({})
		if duel.phase != ELDuel.Phase.FINISHED or duel.winner < 0: continue
		# The winner's last turns are where a win was near: each is a puzzle
		# if the win can be forced from it against the best defence.
		var near: Array = starts.filter(func(start: Dictionary) -> bool: return int(start.side) == duel.winner)
		for start: Dictionary in near.slice(maxi(0, near.size() - LONGEST)):
			var document := {"format": "etherlords-duel", "version": 1, "state": start.state}
			var puzzle := _puzzle(document, int(start.side))
			if puzzle.is_empty(): continue
			found += 1
			document.about = "a win in %d turns for side %d" % [int(puzzle.turns), int(start.side)]
			document.expect = {"kind": "win", "side": int(start.side), "turns": int(puzzle.turns), "found_by": puzzle.found_by, "proven": true}
			var path := folder.path_join("%s_win%d_%d_%d.json" % [game, int(puzzle.turns), n, int(start.serial)])
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(document, "", true, true))
			print("PUZZLE %s turns=%d found_by=%s" % [path.get_file(), int(puzzle.turns), ",".join(puzzle.found_by)])
	print("FOUND %d" % found)

## The position as a duel of its own, or null.
func _open(document: Dictionary) -> ELDuel:
	var duel := ELDuel.new()
	return duel if duel.restore(profile, document) else null

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

## Whether the hero to move wins from the position in a few turns whatever
## the other does, though not in this one: {turns, found_by} when the engine
## proves it and the deep engine then wins it in those turns against its own
## defence and against the shipped search's, else nothing. `found_by` also
## names the shipped search when it wins in time too.
func _puzzle(document: Dictionary, side: int) -> Dictionary:
	var duel := _open(document)
	if duel == null: return {}
	var turns := int(ELCombatBrain.prove(_context(side), duel, LONGEST, PROOF).get("turns", 0))
	# A win in the turn it stands in is no puzzle.
	if turns < 2: return {}
	var finders: Array[String] = []
	for attack: Dictionary in [DEEP, SEARCH]:
		if _win_in(duel, side, attack, DEEP, turns) == 0 or _win_in(duel, side, attack, SEARCH, turns) == 0: continue
		finders.append("deep" if attack == DEEP else "search")
	if not finders.has("deep"): return {}
	return {"turns": turns, "found_by": finders}

func _solve(folder: String, game: String, text: String, shard: String) -> void:
	var setting := _setting(text)
	# Turns over the puzzle's own a slower win is still followed for.
	var slack := int(_arg("slack", "0"))
	var names: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.begins_with(game + "_") and name.ends_with(".json"): names.append(name)
	names.sort()
	var solved := 0
	var won := 0
	var tried := 0
	for i in names.size():
		if i % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(names[i])))
		if document is not Dictionary or not document.has("expect"): continue
		# A bare position, as the first puzzles were kept.
		if not document.has("format"): document = {"format": "etherlords-duel", "version": 1, "state": document, "expect": document.expect}
		var duel := ELDuel.new()
		if not duel.restore(profile, document): continue
		tried += 1
		var began := Time.get_ticks_msec()
		var allowed := int(document.expect.turns)
		var turns := _win_in(duel, int(document.expect.side), setting, DEEP, allowed + slack)
		if turns > 0: won += 1
		if turns > 0 and turns <= allowed: solved += 1
		print("%s %s turns=%d allowed=%d ms=%d by=%s" % ["SOLVED" if turns > 0 and turns <= allowed else ("LATE" if turns > 0 else "MISSED"), names[i], turns, allowed,
			Time.get_ticks_msec() - began, "+".join(document.expect.get("found_by", ["deep"]))])
	print("TOTAL %s solved=%d of=%d won=%d" % [text, solved, tried, won])

## The engine's own word on each puzzle: whether its hero wins whatever the
## other does, and in how many turns.
func _prove(folder: String, game: String, shard: String) -> void:
	var budget := int(_arg("budget", str(PROOF * 4)))
	var most := int(_arg("turns", str(LONGEST)))
	var rewrite := _arg("rewrite", "") == "1"
	var names: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.begins_with(game + "_") and name.ends_with(".json"): names.append(name)
	names.sort()
	var proven := 0
	var same := 0
	var tried := 0
	for i in names.size():
		if i % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var path := folder.path_join(names[i])
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if document is not Dictionary or not document.has("expect") or not document.has("format"): continue
		var duel := ELDuel.new()
		if not duel.restore(profile, document): continue
		tried += 1
		var began := Time.get_ticks_msec()
		var found := ELCombatBrain.prove(_context(int(document.expect.side)), duel, most, budget)
		var turns := int(found.get("turns", 0))
		if turns > 0: proven += 1
		if turns == int(document.expect.turns): same += 1
		print("%s %s turns=%d kept=%d positions=%d aborted=%s ms=%d by=%s" % ["PROVEN" if turns > 0 else "UNPROVEN", names[i], turns, int(document.expect.turns),
			int(found.get("positions", 0)), str(found.get("aborted", false)), Time.get_ticks_msec() - began, "+".join(document.expect.get("found_by", []))])
		if rewrite and turns > 0:
			document.about = "a win in %d turns for side %d" % [turns, int(document.expect.side)]
			document.expect.turns = turns
			document.expect.proven = true
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(_whole(document), "", true, true))
	print("TOTAL proven=%d of=%d same_turns=%d" % [proven, tried, same])

## A document as it was read, its whole numbers whole again.
func _whole(value: Variant) -> Variant:
	if value is float and value == floorf(value) and absf(value) < 9.0e15: return int(value)
	if value is Array: return (value as Array).map(_whole)
	if value is Dictionary:
		var out := {}
		for key: Variant in value: out[key] = _whole(value[key])
		return out
	return value
