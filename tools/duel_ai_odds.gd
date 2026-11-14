extends SceneTree
## How a position's worth to the computer opponent relates to winning from it.
## Plays computer-vs-computer duels and prints, for the start of every turn,
## the worth the opponent reads there and who went on to win:
##
##   ODDS <worth> <side> <round> <winner> <feature>...
##
## The features are, for the side to move and then the other: creatures,
## their power in all, their health in all, the hero's health, its ether
## channels and the cards in its hand. Fitting a win chance to those says
## what each is worth in games won, rather than taking the numbers from the
## original (see tools/duel_ai_bench.gd and `ELCombatSearch.smart_w*`).
##
##   godot --headless --path game --script ../tools/duel_ai_odds.gd -- \
##       [--game=el1|el2] [--duels=N] [--seed=N] [--shard=I/N] [--books=...]
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const LETTER := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
const ROUND_CAP := 30
const PHASE_CAP := 80

var profile: ELProfile

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func _initialize() -> void:
	var game := _arg("game", "el1")
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if stored is Dictionary: folder = String(stored.get(game, ""))
	profile = ELProfile.new()
	if folder.is_empty() or not profile.mount(game, folder):
		printerr("Game files are required: pass --%s=<folder>" % game)
		quit(1)
		return
	var books := _books(_arg("books", "preset"))
	var shard := _arg("shard", "0/1")
	var random := RandomNumberGenerator.new()
	for index in int(_arg("duels", "8")):
		random.seed = hash([int(_arg("seed", "1")), index])
		var first: Dictionary = books[random.randi() % books.size()]
		var matching := books.filter(func(book: Dictionary) -> bool: return book.level == first.level)
		var second: Dictionary = matching[random.randi() % matching.size()]
		var seed_value := int(random.randi() & 0x7fffffff)
		if index % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		_play([first, second], seed_value)
	print("DONE")
	quit(0)

func _books(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for faction: String in FACTIONS:
		var names := [[ELCatalog.STARTERS[faction], 1]]
		if kind != "starter":
			for n in range(2, 7): names.append(["PR%s%d" % [LETTER[faction], n], n * 2])
		for entry: Array in names:
			if ELCatalog.deck(profile, entry[0]).is_empty(): continue
			var probe := ELDuel.new()
			var player := {"faction": faction, "deck": entry[0], "level": entry[1]}
			if probe.start(profile, 1, {"players": [player, player]}): result.append(player)
	return result

## The worth of the position to `side`, as the search reads it.
func _worth(d: ELDuel, side: int) -> float:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.steady_weights(ctx.second)
	ctx.remember = true
	return ELCombatSearch.side_value(ctx, d, side) - ELCombatSearch.side_value(ctx, d, 1 - side)

## What the position holds, for the side to move and then the other.
func _features(d: ELDuel, side: int) -> Array:
	var row: Array = []
	for who in [side, 1 - side]:
		var creatures := 0
		var power := 0
		var toughness := 0
		for c: Dictionary in d.army(who):
			creatures += 1
			power += maxi(0, int(c.power))
			toughness += maxi(0, int(c.toughness) - int(c.get("damage", 0)))
		row.append_array([creatures, power, toughness, int(d.heroes[who].health), int(d.heroes[who].channels), d.heroes[who].hand.size()])
	return row

func _play(books: Array, seed_value: int) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": books}):
		printerr("Cannot start: " + duel.error)
		return
	var marks: Array = []
	var commands := 0
	var mark := [-1, -1, -1]
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
			if duel.phase == ELDuel.Phase.ATTACK: marks.append([_worth(duel, side), side, duel.round_number, _features(duel, side)])
		commands += 1
		var smart: Array[int] = [side]
		duel.smart_sides = smart
		var command := ELCombatSearch.think(duel) if commands <= PHASE_CAP else {}
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	var winner := duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1
	for item: Array in marks:
		var row: Array = item[3]
		print("ODDS %.2f %d %d %d %s" % [item[0], item[1], item[2], winner, " ".join(row.map(func(v: int) -> String: return str(v)))])
