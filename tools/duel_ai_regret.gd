extends SceneTree
## Finds the computer opponent's mistakes by playing them out. Two computer
## players (the remake option as shipped) play duels; at a decision with more
## than one first move, the duel is finished several times from each of the
## best few moves by a quicker opponent, with the cards the mover cannot see
## dealt afresh, the same way for every move. A move the search preferred that wins less often
## than another is a suspect.
##
##   godot --headless --path game --script ../tools/duel_ai_regret.gd -- \
##       [--game=el1|el2] [--pairs=N] [--seed=N] [--shard=I/N] \
##       [--rollouts=N] [--options=N] [--every=N] [--fast=<settings>] \
##       [--books=starter|preset] [--report=<share>] [--save=<folder>]
##
## Prints one DECISION line per analysed decision:
##   DECISION <game> r<round> side<side> <phase> regret=<share> | chosen <move>
##   =<share> | best <move> =<share> | search <chosen worth> / <best's worth>
## where a share is the part of the play-outs won; and, when the regret is at
## least --report (default 0.34), the position and every move tried; --save
## also writes that position as a duel save (ELDuel.restore reads it).
## --every=N analyses every Nth decision that has a choice. --fast overrides
## ELCombatSearch's `smart_*` variables for the play-outs, as in
## duel_ai_bench.gd.
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const LETTER := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
const ROUND_CAP := 30
const PHASE_CAP := 80
## Commands a play-out may take before it counts as a draw.
const PLAYOUT_CAP := 900

var profile: ELProfile
var defaults := {}
var fast := {}
var rollouts := 6
var options := 3
var every := 3
var report := 0.34
## Folder that receives the reported positions as duel saves (--save).
var save := ""
var saved := 0

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func _initialize() -> void:
	var game := _arg("game", "el1")
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	profile = ELProfile.new()
	if folder.is_empty() or not profile.mount(game, folder):
		printerr("Game files are required: pass --%s=<folder>" % game)
		quit(1)
		return
	for line: String in (ELCombatSearch as Script).source_code.split("
"):
		if not line.begins_with("static var smart_"): continue
		var name := line.trim_prefix("static var ").get_slice(" ", 0).get_slice(":", 0)
		defaults[name] = (ELCombatSearch as Script).get(name)
	for item: String in _arg("fast", "budget=150,brain_budget=800,brain_move_budget=8000,brain_move_turns=2").split(",", false):
		var name := "smart_" + item.get_slice("=", 0)
		if not defaults.has(name):
			printerr("Unknown setting: " + name)
			quit(1)
			return
		fast[name] = str_to_var(item.get_slice("=", 1))
	rollouts = int(_arg("rollouts", "6"))
	options = int(_arg("options", "3"))
	every = maxi(1, int(_arg("every", "3")))
	report = float(_arg("report", "0.34"))
	save = _arg("save", "")
	var pairs := int(_arg("pairs", "4"))
	var seed_base := int(_arg("seed", "1"))
	var shard := _arg("shard", "0/1")
	var books := _books(_arg("books", "preset"))
	var random := RandomNumberGenerator.new()
	for pair in pairs:
		random.seed = hash([seed_base, pair])
		var first: Dictionary = books[random.randi() % books.size()]
		var matching := books.filter(func(book: Dictionary) -> bool: return book.level == first.level)
		var second: Dictionary = matching[random.randi() % matching.size()]
		var seed_value := int(random.randi() & 0x7fffffff)
		if pair % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		_play("%s-%s-%d" % [first.deck, second.deck, seed_value], [first, second], seed_value)
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

func _use(settings: Dictionary) -> void:
	for name: String in defaults: (ELCombatSearch as Script).set(name, settings.get(name, defaults[name]))

func _play(game: String, books: Array, seed_value: int) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": books}):
		printerr("Cannot start: " + duel.error)
		return
	print("GAME %s" % game)
	print(_legend(duel))
	var commands := 0
	var mark := [-1, -1, -1]
	var choices := 0
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
		commands += 1
		_use({})
		var smart: Array[int] = [side]
		duel.smart_sides = smart
		var stats := {"trace": []}
		var command := ELCombatSearch.think(duel, stats) if commands <= PHASE_CAP else {}
		var tried := _distinct(stats.get("trace", []), command)
		if tried.size() > 1:
			choices += 1
			if choices % every == 0: _judge(game, duel, side, command, tried)
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	print("END %s winner=%d rounds=%d" % [game, duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1, duel.round_number])

## The first moves tried, best first, one entry per command; the chosen one leads.
func _distinct(trace: Array, chosen: Dictionary) -> Array:
	var sorted := trace.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.value > y.value)
	var result: Array = []
	var seen := {}
	for t: Dictionary in sorted:
		var key := _key(t.command)
		if seen.has(key): continue
		seen[key] = true
		if key == _key(chosen): result.push_front(t)
		else: result.append(t)
	if result.is_empty() or _key(result[0].command) != _key(chosen): return []
	return result

func _key(command: Dictionary) -> String:
	var c := command.duplicate()
	c.erase("ids")
	c.erase("pairs")
	c.erase("plan")
	return str(c)

func _judge(game: String, duel: ELDuel, side: int, chosen: Dictionary, tried: Array) -> void:
	var count := mini(options, tried.size())
	var scores: Array[float] = []
	for i in count:
		var total := 0.0
		for r in rollouts:
			var copy := duel.search_copy()
			_reshuffle(copy, side, hash([duel.rng_state, duel.round_number, r]))
			if not ELCombatSearch.apply(copy, tried[i].command): copy.end_phase()
			total += _finish(copy, side)
		scores.append(total / float(rollouts))
	var best := 0
	for i in range(1, count):
		if scores[i] > scores[best]: best = i
	var regret := scores[best] - scores[0]
	print("DECISION %s r%d side%d %s regret=%.2f | chosen %s =%.2f | best %s =%.2f | search %.2f / %.2f" % [game, duel.round_number, side,
		"attack" if duel.phase == ELDuel.Phase.ATTACK else "block", regret, _describe(tried[0].command), scores[0],
		_describe(tried[best].command), scores[best], tried[0].value, tried[best].value])
	if regret < report: return
	if not save.is_empty():
		saved += 1
		var path := "%s/%s-%s-r%d-%d.json" % [save, profile.id, game, duel.round_number, saved]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"format": "etherlords-duel", "version": 1, "state": duel.snapshot(),
				"found": {"side": side, "chosen": tried[0].command, "better": tried[best].command, "regret": regret}}, "", true, true))
			file.close()
			print("   saved %s" % path)
	print(_board(duel))
	for i in count: print("      %s  search %.2f  won %.2f" % [_describe(tried[i].command), tried[i].value, scores[i]])

## What `side` cannot see is dealt afresh: the cards the other hero drew from
## its book go back and are drawn again, and later draws fall differently.
## Cards that came to a hand in the open (returned from play) stay.
func _reshuffle(d: ELDuel, side: int, seed_value: int) -> void:
	d.rng_state = (d.rng_state * 31 + seed_value) & 0x7fffffff
	var other := 1 - side
	var hero: Dictionary = d.heroes[other]
	var count := 0
	for index in range(hero.hand.size() - 1, -1, -1):
		var slot := int(hero.hand_slots[index])
		if slot < 0: continue
		d._take_card(other, index)
		hero.drawn.erase(slot)
		count += 1
	for i in count: d._draw(other)

## Plays the duel out with the quick opponent; 1 when `side` wins, 0.5 a draw.
func _finish(d: ELDuel, side: int) -> float:
	_use(fast)
	var steps := 0
	var commands := 0
	var mark := [-1, -1, -1]
	while d.phase != ELDuel.Phase.FINISHED and d.round_number <= ROUND_CAP and steps < PLAYOUT_CAP:
		var here := [d.round_number, d.attacker, d.phase]
		if here != mark:
			mark = here
			commands = 0
		commands += 1
		steps += 1
		var smart: Array[int] = [d.active_side()]
		d.smart_sides = smart
		var command := ELCombatSearch.think(d) if commands <= PHASE_CAP else {}
		if command.is_empty() or not ELCombatSearch.apply(d, command): d.end_phase()
	if d.phase != ELDuel.Phase.FINISHED or d.winner < 0: return 0.5
	return 1.0 if d.winner == side else 0.0

func _board(duel: ELDuel) -> String:
	var text := "   -- round %d, side %d %s" % [duel.round_number, duel.attacker, "to attack" if duel.phase == ELDuel.Phase.ATTACK else "attacks with %s, side %d to block" % [str(duel.attacks), 1 - duel.attacker]]
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		text += "
      side%d hp %d ether %d/%d hand %s" % [side, hero.health, hero.mana, hero.channels, " ".join(hero.hand)]
		var marks: Array = hero.enchantments.map(func(e: Dictionary) -> String: return String(e.card))
		if not marks.is_empty(): text += " ench " + " ".join(marks)
		text += "
         army:"
		for c: Dictionary in duel.army(side):
			var worn: Array = c.get("enchantments", []).map(func(e: Dictionary) -> String: return String(e.card))
			text += " #%d %s %d/%d%s%s%s" % [c.id, c.card, c.power, c.toughness, "r" if c.resting else "", "s" if c.sick else "", "" if worn.is_empty() else "[" + ",".join(worn) + "]"]
	return text

func _legend(duel: ELDuel) -> String:
	var codes := {}
	for hero: Dictionary in duel.heroes:
		for card: String in hero.hand + hero.deck: codes[card] = true
	var text := "cards:"
	for card: String in codes:
		var creature: Dictionary = profile.table("CombatCreatures").get(card, {})
		var stats := " %s/%s %s" % [creature.get("Power", "?"), creature.get("Toughness", "?"), " ".join(ELCatalog.flags(creature))] if not creature.is_empty() else ""
		text += "
   %s (%d)%s: %s" % [card, duel.cost(card), stats, ELCombatTooltip.spell_text(profile, card).replace("
", " | ")]
	return text

func _describe(command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s>%d/%d/x%d" % [command.card, command.target, command.grave, command.power]
		"attack": return "attack#%d" % command.id
		"block": return "block#%d<-#%d" % [command.target, command.id]
		"ability": return "ability %s@%d>%d" % [command.key, command.id, command.target]
	return "end"
