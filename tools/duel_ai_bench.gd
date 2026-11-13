extends SceneTree
## Computer-vs-computer duels for comparing combat opponent settings
## (ELCombatSearch). Every pairing of books is played twice with the same
## seed, the settings swapping sides, so luck of the draw cancels out.
##
##   godot --headless --path game --script ../tools/duel_ai_bench.gd -- \
##       [--game=el1|el2] [--a=<settings>] [--b=<settings>] [--pairs=N] \
##       [--seed=N] [--shard=I/N] [--books=starter|preset] [--verbose]
##
## Settings: "orig" (the original opponent), "smart" (the remake option as
## shipped), or "smart:name=value,..." overriding ELCombatSearch's `smart_*`
## variables (the `smart_` prefix is left out), e.g. "smart:budget=6000,phases=1".
##
## Prints one GAME line per duel, then the wins of each side and its thinking
## time. Most pairings go to the same seat whoever plays it (the cards
## decide), so compare the pairings one side won from both seats, and play a
## few hundred duels before trusting a difference. --shard=I/N plays every
## Nth pairing, for running N copies side by side.
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const LETTER := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
## Longest duel in rounds, and commands one side may send in one phase.
const ROUND_CAP := 30
const PHASE_CAP := 80
## Longest duel in seconds; a longer one (two large armies facing each other
## down) counts as a draw.
const TIME_CAP := 150.0

var profile: ELProfile
var defaults := {}
var verbose := false

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
	verbose = _arg("verbose", "") == "1"
	# Static variables are not in the script's property list; its source names them.
	for line: String in (ELCombatSearch as Script).source_code.split("
"):
		if not line.begins_with("static var smart_"): continue
		var name := line.trim_prefix("static var ").get_slice(" ", 0).get_slice(":", 0)
		defaults[name] = (ELCombatSearch as Script).get(name)
	if verbose: print("settings: ", defaults)
	var a := _settings(_arg("a", "smart"))
	var b := _settings(_arg("b", "orig"))
	var pairs := int(_arg("pairs", "16"))
	var seed_base := int(_arg("seed", "1"))
	var shard := _arg("shard", "0/1")
	var books := _books(_arg("books", "preset"))
	var tally := {"a": 0, "b": 0, "draw": 0}
	var clock := {"a": [0, 0, 0, 0], "b": [0, 0, 0, 0]}
	var random := RandomNumberGenerator.new()
	for pair in pairs:
		# The same pairings for every shard; each shard plays its share.
		random.seed = hash([seed_base, pair])
		# Both heroes are of one level, so the better play decides.
		var first: Dictionary = books[random.randi() % books.size()]
		var matching := books.filter(func(book: Dictionary) -> bool: return book.level == first.level)
		var second: Dictionary = matching[random.randi() % matching.size()]
		var seed_value := int(random.randi() & 0x7fffffff)
		if pair % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		for swap in 2:
			var sides := [a, b] if swap == 0 else [b, a]
			var names := ["a", "b"] if swap == 0 else ["b", "a"]
			var result := _play([first, second], sides, names, seed_value, clock)
			var who: String = "draw" if result.winner < 0 else names[result.winner]
			tally[who] += 1
			print("GAME pair=%d swap=%d %s(%d) vs %s(%d) seed=%d winner=%s rounds=%d" % [pair, swap, first.deck, first.level, second.deck, second.level, seed_value, who, result.rounds])
	print("RESULT a=%d b=%d draw=%d" % [tally.a, tally.b, tally.draw])
	for name: String in ["a", "b"]:
		var c: Array = clock[name]
		print("THINK %s count=%d ms=%.1f positions=%.0f worst_ms=%d" % [name, c[0], float(c[1]) / 1000.0 / maxf(1.0, float(c[0])), float(c[2]) / maxf(1.0, float(c[0])), int(c[3]) / 1000])
	quit(0)

func _settings(text: String) -> Dictionary:
	var result := {"smart": text.get_slice(":", 0) != "orig", "set": {}}
	for item: String in (text.get_slice(":", 1) if text.contains(":") else "").split(",", false):
		var name := "smart_" + item.get_slice("=", 0)
		if not defaults.has(name):
			printerr("Unknown setting: " + name)
			quit(1)
			continue
		result.set[name] = str_to_var(item.get_slice("=", 1))
	return result

## Single-colour books that the rules fully cover, with a hero level each.
func _books(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for faction: String in FACTIONS:
		var names := [[ELCatalog.STARTERS[faction], 1]]
		if kind != "starter":
			for n in range(2, 7): names.append(["PR%s%d" % [LETTER[faction], n], n * 2])
		for entry: Array in names:
			var cards := ELCatalog.deck(profile, entry[0])
			if cards.is_empty(): continue
			var probe := ELDuel.new()
			var player := {"faction": faction, "deck": entry[0], "level": entry[1]}
			if probe.start(profile, 1, {"players": [player, player]}): result.append(player)
			elif verbose: print("skipped %s: %s" % [entry[0], probe.error])
	return result

func _play(books: Array, sides: Array, names: Array, seed_value: int, clock: Dictionary) -> Dictionary:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": books}):
		printerr("Cannot start: " + duel.error)
		return {"winner": -1, "rounds": 0}
	var commands := 0
	var mark := [-1, -1, -1]
	if verbose: print(_legend(duel))
	var began := Time.get_ticks_msec()
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP and float(Time.get_ticks_msec() - began) < TIME_CAP * 1000.0:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
			if verbose: print(_board(duel))
		commands += 1
		var settings: Dictionary = sides[side]
		for name: String in defaults: (ELCombatSearch as Script).set(name, settings.set.get(name, defaults[name]))
		var smart: Array[int] = []
		if settings.smart: smart.append(side)
		duel.smart_sides = smart
		var stats := {}
		if verbose: stats.trace = []
		var started := Time.get_ticks_usec()
		var command := ELCombatSearch.think(duel, stats) if commands <= PHASE_CAP else {}
		var spent := Time.get_ticks_usec() - started
		var c: Array = clock[names[side]]
		c[0] += 1
		c[1] += spent
		c[2] += int(stats.get("positions", 0))
		c[3] = maxi(c[3], spent)
		if verbose:
			print("    side%d %s: %s" % [side, names[side], _describe(duel, command)])
			var tried: Array = stats.get("trace", [])
			tried.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.value > y.value)
			for i in mini(tried.size(), 6):
				var t: Dictionary = tried[i]
				print("         %8.2f  %s%s" % [t.value, _describe(duel, t.command), "" if t.plan == t.command else "  (%s)" % t.plan.kind])
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	return {"winner": duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1, "rounds": duel.round_number}

## The position in one block of text (--verbose).
func _board(duel: ELDuel) -> String:
	var text := "-- round %d, side %d %s" % [duel.round_number, duel.attacker, "to attack" if duel.phase == ELDuel.Phase.ATTACK else "attacks with %s, side %d to block" % [str(duel.attacks), 1 - duel.attacker]]
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		text += "
   side%d hp %d ether %d/%d hand %s" % [side, hero.health, hero.mana, hero.channels, " ".join(hero.hand)]
		var marks: Array = hero.enchantments.map(func(e: Dictionary) -> String: return String(e.card))
		if not marks.is_empty(): text += " ench " + " ".join(marks)
		text += "
      army:"
		for c: Dictionary in duel.army(side):
			text += " #%d %s %d/%d%s%s" % [c.id, c.card, c.power, c.toughness, "r" if c.resting else "", "s" if c.sick else ""]
	return text

## The cards of both books, by code (--verbose).
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

func _describe(duel: ELDuel, command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s target %d choice %d x %d" % [command.card, command.target, command.grave, command.power]
		"attack": return "attack with #%d" % command.id
		"block": return "block #%d with #%d" % [command.target, command.id]
		"ability": return "ability %s of %d target %d" % [command.key, command.id, command.target]
	return "end phase"
