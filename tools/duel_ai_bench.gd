extends SceneTree
## Computer-vs-computer duels for comparing combat opponent settings
## (ELCombatSearch). Every pairing of books is played twice with the same
## seed, the settings swapping sides, so luck of the draw cancels out.
##
##   godot --headless --path game --script ../tools/duel_ai_bench.gd -- \
##       [--game=el1|el2] [--a=<settings>] [--b=<settings>] [--pairs=N] \
##       [--seed=N] [--shard=I/N] [--books=starter|preset] [--verbose]
##       [--force=CARD,...] [--factions=Red,...] [--seconds=N] [--thinks]
##
## Settings: "orig" (the original opponent), "easy" (the original reading
## ELCombatSearch.EASY_BUDGET positions, the "Easy" duel opponent), "smart" (the remake option as
## shipped), "search" (the remake option's own search, without the compiled
## engine), or "smart:name=value,..." overriding ELCombatSearch's `smart_*`
## variables (the `smart_` prefix is left out), e.g. "smart:budget=6000,phases=1".
##
## Prints one GAME line per duel, then the wins of each side with a 95%
## confidence interval for A's share, how the other duels ended (out of
## rounds or out of time), and per side its thinking time with the 50th, 95th
## and 99th percentile of one decision (LATENCY: the think and the sending of
## the command, with any second thought the sending needed, which share one
## request and its time; a LATE line tells of each decision more than 300 ms
## past the think limit, with the stages of its think), which opponent actually made
## each decision (ELCombatSearch.think's "engine"), the commands the duel
## refused (each thought over: ELPracticeAI.send), the thinks that wanted
## the compiled engine but fell back to the search (a position the engine
## does not model), the phases cut off at PHASE_CAP commands and the commands
## that only led back to a position already played in the phase (each
## thought over as well). Most pairings go to the same seat whoever plays it (the cards
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
## Longest duel in seconds (--seconds=N for a slower setting or a busy
## machine); a longer one (two large armies facing each other down) counts
## as a draw.
const TIME_CAP := 150.0

var profile: ELProfile
var defaults := {}
## Per side: each command's think in microseconds, the opponents that made the
## decisions, refused commands, engine fall-backs and phases cut off.
var detail := {}
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
	for line: String in (ELCombatSearch as Script).source_code.split("\n"):
		line = line.strip_edges(false, true)
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
	var tally := {"a": 0, "b": 0, "draw": 0, "rounds": 0, "time": 0}
	var clock := {"a": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "b": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	for name: String in ["a", "b"]: detail[name] = {"thinks": PackedInt64Array(), "engines": {}, "refused": 0, "unsupported": 0, "capped": 0, "cycles": 0}
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
		if not _arg("only", "").is_empty() and pair != int(_arg("only", "")): continue
		for swap in 2:
			var sides := [a, b] if swap == 0 else [b, a]
			var names := ["a", "b"] if swap == 0 else ["b", "a"]
			var result := _play([first, second], sides, names, seed_value, clock)
			var who: String = "draw" if result.winner < 0 else names[result.winner]
			tally[who] += 1
			# A draw ends out of rounds, out of time, or with both heroes falling at once.
			if who == "draw": tally[result.ended] = int(tally.get(result.ended, 0)) + 1
			print("GAME pair=%d swap=%d %s(%d) vs %s(%d) seed=%d winner=%s rounds=%d%s" % [pair, swap, first.deck, first.level, second.deck, second.level, seed_value, who, result.rounds, "" if who != "draw" else " ended=" + result.ended])
	print("RESULT a=%d b=%d draw=%d" % [tally.a, tally.b, tally.draw])
	# A's share of the points (a draw is half), with a normal 95% interval.
	var n: int = tally.a + tally.b + tally.draw
	if n > 0:
		var share := (float(tally.a) + 0.5 * float(tally.draw)) / float(n)
		var margin := 1.96 * sqrt(maxf(share * (1.0 - share), 0.0) / float(n))
		print("SHARE a=%.1f%% 95%%=[%.1f%%, %.1f%%] duels=%d draws: out_of_rounds=%d out_of_time=%d" % [share * 100.0, maxf(0.0, share - margin) * 100.0, minf(1.0, share + margin) * 100.0, n, tally.rounds, tally.time])
	for name: String in ["a", "b"]:
		var c: Array = clock[name]
		print("THINK %s count=%d ms=%.1f positions=%.0f worst_ms=%d" % [name, c[0], float(c[1]) / 1000.0 / maxf(1.0, float(c[0])), float(c[2]) / maxf(1.0, float(c[0])), int(c[3]) / 1000])
		var thinks: Array = Array(detail[name].thinks)
		thinks.sort()
		# --thinks prints every think, for pooling the percentiles of shards.
		if _arg("thinks", "") == "1": print("THINKS %s %s" % [name, ",".join(thinks.map(func(t: int) -> String: return str(t / 1000)))])
		if not thinks.is_empty(): print("LATENCY %s p50=%d ms p95=%d ms p99=%d ms max=%d ms" % [name, _percentile(thinks, 0.5) / 1000, _percentile(thinks, 0.95) / 1000, _percentile(thinks, 0.99) / 1000, int(thinks[-1]) / 1000])
		print("ENGINE %s %s refused=%d unsupported=%d phase_cap=%d led_back=%d" % [name, str(detail[name].engines), detail[name].refused, detail[name].unsupported, detail[name].capped, detail[name].cycles])
		print("MODEL %s decisions=%d incomplete=%d reasons=%s" % [name, c[0], int(detail[name].get("incomplete", 0)), str(detail[name].get("reasons", {}))])
		if c[4] > 0: print("REACH %s engine=%d phases=%.2f cut=%d proven=%d commands_to_3=%d to_6=%d to_10=%d more=%d guarded=%d doomed=%d" % [name, c[4], float(c[5]) / float(c[4]), c[6], c[7], c[8], c[9], c[10], c[11], c[12], c[13]])
	quit(0)

## The stages of a think with the milliseconds each took (ELCombatSearch.think's "stages").
func _stages(stats: Dictionary) -> String:
	var parts: Array = []
	var stages: Dictionary = stats.get("stages", {})
	for name: String in stages: parts.append("%s:%d" % [name, int(stages[name]) / 1000])
	return ",".join(parts)

## The value below which a share `q` of the sorted values lie.
func _percentile(sorted: Array, q: float) -> int:
	return int(sorted[clampi(int(ceil(q * float(sorted.size()))) - 1, 0, sorted.size() - 1)])

func _settings(text: String) -> Dictionary:
	var kind := text.get_slice(":", 0)
	var result := {"smart": kind not in ["orig", "easy"], "easy": kind == "easy", "set": {}}
	if text.get_slice(":", 0) == "search": result.set["smart_engine"] = false
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
			# --force adds the cards to the books whose colour allows them;
			# --factions keeps only those factions' books.
			if not _arg("factions", "").is_empty() and faction not in _arg("factions", "").split(","): continue
			var forced := player.duplicate()
			var extended: Array = []
			extended.append_array(cards)
			extended.append_array(Array(_arg("force", "").split(",", false)))
			forced.cards = extended
			var trial := ELDuel.new()
			if verbose: print("book %s: %d cards, %d with --force" % [entry[0], cards.size(), extended.size()])
			if extended.size() > cards.size():
				if trial.start(profile, 1, {"players": [forced, forced]}): player = forced
				elif verbose: print("not forced in %s: %s" % [entry[0], trial.error])
			if probe.start(profile, 1, {"players": [player, player]}): result.append(player)
			elif verbose: print("skipped %s: %s" % [entry[0], probe.error])
	return result

func _play(books: Array, sides: Array, names: Array, seed_value: int, clock: Dictionary) -> Dictionary:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": books}):
		printerr("Cannot start: " + duel.error)
		return {"winner": -1, "rounds": 0, "ended": "rounds"}
	var commands := 0
	var mark := [-1, -1, -1]
	if verbose: print(_legend(duel))
	var began := Time.get_ticks_msec()
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP and float(Time.get_ticks_msec() - began) < float(_arg("seconds", str(TIME_CAP))) * 1000.0:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
			if verbose: print(_board(duel))
		commands += 1
		var settings: Dictionary = sides[side]
		for name: String in defaults: (ELCombatSearch as Script).set(name, settings.set.get(name, defaults[name]))
		ELCombatSearch.original_budget = ELCombatSearch.EASY_BUDGET if settings.easy else ELCombatSearch.BUDGET
		var smart: Array[int] = []
		if settings.smart: smart.append(side)
		duel.smart_sides = smart
		var stats := {}
		if verbose: stats.trace = []
		var own: Dictionary = detail[names[side]]
		if commands > PHASE_CAP:
			own.capped += 1
			duel.end_phase()
			continue
		# One decision, as in play: the think and whatever second thought the
		# command needs as it is sent share one request and its time.
		var started := Time.get_ticks_usec()
		var asked := ELCombatSearch.request(duel)
		var command := ELCombatSearch.think(duel, stats, false, asked)
		var spent := Time.get_ticks_usec() - started
		var engine := String(stats.get("engine", "?"))
		own.engines[engine] = int(own.engines.get(engine, 0)) + 1
		if settings.smart and bool(settings.set.get("smart_engine", defaults.smart_engine)) and ELCombatBrain.available and engine == "search": own.unsupported += 1
		# What the model left out of the position decided on, by reason.
		var left_out: Array = stats.get("crowding", [])
		if not left_out.is_empty(): own.incomplete = int(own.get("incomplete", 0)) + 1
		if not own.has("reasons"): own.reasons = {}
		for reason: String in left_out: own.reasons[reason.rstrip("01")] = int(own.reasons.get(reason.rstrip("01"), 0)) + 1
		var c: Array = clock[names[side]]
		c[0] += 1
		c[1] += spent
		c[2] += int(stats.get("positions", 0))
		c[3] = maxi(c[3], spent)
		if stats.has("far"):
			c[4] += 1
			c[5] += int(stats.far)
			c[6] += 1 if stats.cut else 0
			c[7] += 1 if int(stats.get("proven", 0)) > 0 else 0
			if int(stats.get("guarded", 0)) == 15: c[13] += 1
			elif int(stats.get("guarded", 0)) > 0: c[12] += 1
			var deep := int(stats.get("depth", 0))
			c[8 + (0 if deep <= 3 else 1 if deep <= 6 else 2 if deep <= 10 else 3)] += 1
		if verbose:
			print("    side%d %s: %s" % [side, names[side], _describe(duel, command)])
			var tried: Array = stats.get("trace", [])
			tried.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.value > y.value)
			for i in mini(tried.size(), 6):
				var t: Dictionary = tried[i]
				print("         %8.2f  %s%s" % [t.value, _describe(duel, t.command), "" if t.plan == t.command else "  (%s)" % t.plan.kind])
		# As in play: a refused command is reported and thought over.
		var refused := ELPracticeAI.refused
		var cycles := ELPracticeAI.cycles
		var sending := Time.get_ticks_usec()
		ELPracticeAI.send(duel, command, false, asked)
		# The decision's whole time: the think and the sending, with any
		# second thought.
		var whole := spent + Time.get_ticks_usec() - sending
		own.thinks.append(whole)
		var limit := int(asked.get("ms", 0))
		if limit > 0 and whole > (limit + 300) * 1000:
			print("LATE %s round=%d phase=%d decision=%d ms think=%d ms limit=%d ms engine=%s status=%s positions=%d stages=%s refused=%d led_back=%d creatures=%d" % [names[side], duel.round_number, duel.phase,
				whole / 1000, spent / 1000, limit, engine, str(stats.get("status", "")), int(stats.get("positions", 0)), _stages(stats), ELPracticeAI.refused - refused, ELPracticeAI.cycles - cycles, duel.creatures.size()])
		own.refused += ELPracticeAI.refused - refused
		own.cycles += ELPracticeAI.cycles - cycles
	var ended := "won" if duel.phase == ELDuel.Phase.FINISHED else ("rounds" if duel.round_number > ROUND_CAP else "time")
	return {"winner": duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1, "rounds": duel.round_number, "ended": ended}

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
