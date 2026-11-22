extends SceneTree
## Holds the battle rules of the compiled lookahead against the game's own.
## Random armies are put on the board, random attacks declared and random
## blocks assigned, and the same fight is then played twice: once by ELDuel,
## once by the compiled model. Every difference in who died, the damage each
## creature took, whether it rests afterwards and both heroes' health and
## ether is reported.
##
##   godot --headless --path game --script ../tools/duel_rules_check.gd -- \
##       [--game=el1|el2] [--cases=N] [--seed=N] [--shard=I/N] [--army=N]
##       [--cards=<code>,...] [--turn] [--play] [--verbose] [--quiet]
##
## With --turn the turn's end is held up instead of a fight, and with
## --play a short run of commands (cards cast, creatures sent, phases
## ended) is played through both sets of rules instead.
##
## Prints one DIFF line per case that differs, naming the creatures involved,
## then a tally by card and the totals. Heroes are left without skills, so no
## mastery of theirs can roll and the fight is the plain rules alone. Beside
## damage, rest, health and ether, a library that tells them is held to each
## creature's power, health, spent ability and worn enchantments, the cards of
## each hand by name, and what each hero wears and has used this turn.
##
## With --parity a fixed set of hand-made positions is played instead, each
## for a rule the model once got wrong (tools/duel_fixtures.gd).
##
## With --puzzles every reference solution of the authored puzzles
## (game/puzzles/<game>.json) is replayed: before each of its commands the
## engine's own list of commands at that position, as its plain reading and
## as a proof list them, must hold the command, and the position the model
## reaches by it must be the one the game reaches ([--only=<puzzle id>]).
## The refutations are replayed too (their commands need only be in the
## proof's list: the plain reading leaves out casts that only spend their
## card), and every line goes on for --onward=N (24) commands of the
## engine's own, each held to the game's rules the same way.
##
## Exits 1 when any case differed, and when no case was compared at all.
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const Fixtures := preload("res://../tools/duel_fixtures.gd")

const ARMY := 4
const MAX_UNITS := 32

var profile: ELProfile
var verbose := false
var quiet := false
var blamed := {}
var cases := 0
var turn := false
var play := false
var differed := 0
var fights := 0

var spells: Array[String] = []
var cast_total := {}
var standing_blame := {}
var cast_blame := {}
var line_blame := {}
## --line=1: lines whose only fault is a card the game turned down after
## chance had a hand in what was there to cast (see _line_case).
var line_chance := 0
## Whether the run being compared dealt hands again or threw cards out at
## random: which cards those were is the duel's chance, which the model
## does not follow card by card.
var dealt_again := false

## A name the game gives a thing a hero carries, by the spell it works.
var artifact_names := {}
## Set by tools/duel_model_coverage.gd: the run is the coverage of the model.
var coverage_only := false
## --coverage=1: what was tried of each thing, by its kind and name.
var cover := {}

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
	if not ELCombatBrain.available:
		printerr("The compiled lookahead is not loaded.")
		quit(1)
		return
	verbose = _arg("verbose", "") == "1"
	turn = _arg("turn", "") == "1"
	play = _arg("play", "") == "1"
	quiet = _arg("quiet", "") == "1"
	var army := int(_arg("army", str(ARMY)))
	var wanted := Array(_arg("cards", "").split(",", false))
	var pool: Array[String] = []
	for card: String in profile.table("CombatCreatures"):
		if ELCatalog.rule(profile, card).get("effect", "") != "summon": continue
		if wanted.is_empty() or card in wanted: pool.append(card)
	if pool.is_empty():
		printerr("No creature cards to try.")
		quit(1)
		return
	# --spells=1 (with --play=1): every spell the model holds a rule for; or
	# --spells=A,B for those alone.
	var asked := _arg("spells", "")
	if not asked.is_empty():
		var probe := ELDuel.new()
		var starter := {"faction": "Red", "deck": ELCatalog.STARTERS.Red, "level": 6}
		probe.start(profile, 1, {"players": [starter, starter]})
		for card: String in profile.table("CombatSpells"):
			if asked != "1" and not card in asked.split(","): continue
			var effect := String(ELCatalog.rule(profile, card).get("effect", ""))
			if effect == "summon" or not ELCombatBrain.EFFECTS.has(effect): continue
			if ELCombatBrain._card(_context(0), probe, card).is_empty(): continue
			spells.append(card)
	# --artifacts=1 (with --play=1): the heroes carry things too, of every
	# kind the game has; or --artifacts=A,B for those spells alone.
	var carried := _arg("artifacts", "")
	if not carried.is_empty():
		for name: String in profile.table("Artefacts"):
			var entry := ELDuel.artifact_entry(profile, {"name": name})
			if entry.is_empty() or not ELCatalog.ARTIFACT_EFFECTS.has(String(entry.spell)): continue
			if carried != "1" and not String(entry.spell) in carried.split(","): continue
			if not artifact_names.has(String(entry.spell)): artifact_names[String(entry.spell)] = name
	var shard := _arg("shard", "0/1")
	var random := RandomNumberGenerator.new()
	# --set=name=value,...: the search's own settings, as the benchmark names them.
	for item: String in _arg("set", "").split(",", false):
		var name := "smart_" + item.get_slice("=", 0)
		var now: Variant = (ELCombatSearch as Script).get(name)
		var text := item.get_slice("=", 1)
		(ELCombatSearch as Script).set(name, (text == "true") if now is bool else (float(text) if now is float else int(text)))
	if coverage_only or _arg("coverage", "") == "1":
		_coverage(shard)
		return
	if _arg("line", "") == "1":
		_lines(int(_arg("cases", "20")), shard)
		for what: String in line_blame: print("PARTS %s %d" % [what, line_blame[what]])
		print("CHANCE lines=%d" % line_chance)
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, cases, differed])
		_finish(cases)
		return
	if _arg("real", "") == "1":
		_real(random, int(_arg("cases", "20")), shard)
		for card: String in blamed: print("BLAME %s %d" % [card, blamed[card]])
		for card: String in standing_blame: print("STANDING %s %d" % [card, standing_blame[card]])
		for card: String in cast_blame: print("CAST %s %d" % [card, cast_blame[card]])
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, fights, differed])
		_finish(fights)
		return
	if _arg("puzzles", "") == "1":
		_puzzles()
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, fights, differed])
		_finish(fights)
		return
	if _arg("parity", "") == "1":
		_parity()
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, fights, differed])
		_finish(fights)
		return
	for index in int(_arg("cases", "200")):
		if index % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		# --only=N: that one case alone, for a closer look.
		if not _arg("only", "").is_empty() and index != int(_arg("only", "")): continue
		random.seed = hash([int(_arg("seed", "1")), index])
		_case(index, random, pool, army)
	var names := blamed.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return blamed[a] > blamed[b])
	for card: String in names: print("BLAME %s %d" % [card, blamed[card]])
	# With --play=1: how often each card was played, and how often in a run
	# that came out differently.
	for card: String in cast_total: print("PLAYED %s %d %d" % [card, cast_total[card], int(cast_blame.get(card, 0))])
	print("TOTAL cases=%d fights=%d differed=%d" % [cases, fights, differed])
	_finish(fights)

## Exits 1 when any case differed, or when nothing was compared at all (a run
## that held nothing against anything shows nothing).
func _finish(compared: int) -> void:
	if compared == 0: print("INCOMPLETE: no case was compared")
	quit(1 if differed > 0 or compared == 0 else 0)

## --real=1: positions out of duels the opponents actually play, with the
## enchantments, abilities and hero skills that stand in them, instead of
## boards put together for the purpose. At the start of each turn a short run
## of commands goes through both sets of rules from a copy of the position.
## This is the measure of how much of the game the model holds: a board made
## up of creatures alone says nothing of the rest.
func _real(random: RandomNumberGenerator, duels: int, shard: String) -> void:
	var factions: Array = ELCatalog.STARTERS.keys()
	for n in duels:
		if n % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var duel := ELDuel.new()
		var fa: String = factions[n % factions.size()]
		var fb: String = factions[(n / factions.size() + n + 1) % factions.size()]
		if not duel.start(profile, 7000 + n, {"players": [{"faction": fa, "deck": ELCatalog.STARTERS[fa], "level": 6}, {"faction": fb, "deck": ELCatalog.STARTERS[fb], "level": 6}]}): continue
		var last := -1
		var guard := 0
		while duel.phase != ELDuel.Phase.FINISHED and guard < 700 and duel.round_number < 30:
			guard += 1
			if duel.phase == ELDuel.Phase.ATTACK and duel.turn_serial != last:
				last = duel.turn_serial
				cases += 1
				random.seed = hash([n, last])
				for attempt in 3: _play_case(n * 1000 + last, duel.search_copy(), random, duel.attacker)
			var smart: Array[int] = [duel.active_side()]
			duel.smart_sides = smart
			var command := ELCombatSearch.think(duel, {})
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()

## One random board, fought by both sets of rules.
func _case(index: int, random: RandomNumberGenerator, pool: Array[String], army: int) -> void:
	var duel := ELDuel.new()
	var player := {"faction": "Red", "deck": ELCatalog.STARTERS.Red, "level": 6}
	if not duel.start(profile, int(random.randi() & 0x7fffffff), {"players": [player, player]}): return
	# No skills: no mastery of a hero's can roll inside the fight.
	for side in 2:
		duel.heroes[side].skills = {}
		duel.heroes[side].mana = random.randi_range(6, 20) if play else random.randi_range(0, 12)
		duel.heroes[side].health = random.randi_range(8, int(duel.heroes[side].health))
		# Several turns in, past the openings both sets of rules treat apart.
		duel.heroes[side].turns = random.randi_range(3, 8)
		duel.heroes[side].channels = random.randi_range(4, 12)
	var attacker := int(random.randi() & 1)
	duel.attacker = attacker
	duel.phase = ELDuel.Phase.ATTACK
	for side in 2:
		for i in random.randi_range(1, army):
			var card: String = pool[random.randi() % pool.size()]
			var known := duel.creatures.keys()
			duel._summon(side, card)
			for id: int in duel.creatures:
				if known.has(id): continue
				var c: Dictionary = duel.creatures[id]
				c.sick = false
				c.resting = side != attacker and random.randi() % 5 == 0
				if int(c.toughness) > 1 and random.randi() % 3 == 0: c.damage = random.randi_range(1, int(c.toughness) - 1)
	cases += 1
	if play:
		# The attacker holds spells of every kind the model has a rule for,
		# not only what a starting deck deals, and both graveyards hold a few
		# creatures for the spells that reach into them.
		if not spells.is_empty():
			for dealt in [attacker, 1 - attacker]:
				var hero: Dictionary = duel.heroes[dealt]
				hero.hand.clear()
				hero.hand_slots.clear()
				if hero.has("hand_ids"): hero.hand_ids.clear()
				for i in 6: duel._give_card(dealt, spells[random.randi() % spells.size()] if random.randi() % 2 > 0 else pool[random.randi() % pool.size()])
		# --artifacts=1: each hero carries a few things, some used up and
		# some still waiting, and may use more than one of them.
		if not artifact_names.is_empty():
			for side in 2:
				var bearer: Dictionary = duel.heroes[side]
				if random.randi() % 3 > 0: bearer.skills = {"ARTF": int(random.randi() % 3)}
				bearer.artifacts = []
				bearer.artifact_uses = 0
				for i in random.randi_range(0, 4):
					var entry := {}
					if profile.id == "el2" and not spells.is_empty() and random.randi() % 3 == 0:
						var made: String = spells[random.randi() % spells.size()]
						entry = ELDuel.artifact_entry(profile, {"name": "made", "custom": {"elk_name": "", "spell": made, "first": 0, "gap": int(random.randi() % 3), "max": 3}})
					else:
						var works: String = artifact_names.keys()[random.randi() % artifact_names.size()]
						entry = ELDuel.artifact_entry(profile, {"name": String(artifact_names[works])})
					if entry.is_empty(): continue
					entry.charges = random.randi_range(0, 3)
					entry.ready_round = maxi(0, duel.artifact_round() + random.randi_range(-1, 1))
					bearer.artifacts.append(entry)
				# And now and then a war banner already flies.
				if artifact_names.has("WRBN") and random.randi() % 5 == 0:
					duel._enchant("WRBN", side, side, ELCatalog.ARTIFACT_EFFECTS["WRBN"])
					duel._refresh_armies()
		# --graves=1: the graveyards are filled without any spells in hand.
		if not spells.is_empty() or _arg("graves", "") == "1":
			for side in 2:
				for i in random.randi_range(0, 3): duel.heroes[side].grave.append(pool[random.randi() % pool.size()])
		if not spells.is_empty():
			# --standing=1: some of the enchantments a hero lays on itself
			# already stand, so that the model is told them, not only casts them.
			if _arg("standing", "") == "1":
				for side in 2:
					for i in random.randi_range(0, 2):
						var standing_card: String = spells[random.randi() % spells.size()]
						var standing_rule := ELCatalog.rule(profile, standing_card)
						if String(standing_rule.get("effect", "")) != "enchant" or String(standing_rule.get("target", "")) != "none" or not standing_rule.get("self", false): continue
						duel._enchant(standing_card, side, side, standing_rule)
				duel._refresh_armies()
			# --worn=1: so do some of the enchantments laid on creatures.
			if _arg("worn", "") == "1":
				for i in random.randi_range(0, 3):
					var worn_card: String = spells[random.randi() % spells.size()]
					var worn_rule := ELCatalog.rule(profile, worn_card)
					if String(worn_rule.get("effect", "")) != "enchant" or not String(worn_rule.get("target", "")) in ["creature", "any"]: continue
					if ELCombatBrain._card(_context(attacker), duel, worn_card).is_empty() or duel.creatures.is_empty(): continue
					var wearer: int = duel.creatures.keys()[random.randi() % duel.creatures.size()]
					var layer := int(random.randi() & 1)
					if worn_card in ELCatalog.CONTROL and (layer == int(duel.creatures[wearer].owner) or duel.army(layer).size() >= 10): continue
					duel._enchant(worn_card, layer, wearer, worn_rule)
				duel._refresh_armies()
		_play_case(index, duel, random, attacker)
		return
	if not turn:
		for c: Dictionary in duel.army(attacker):
			if random.randi() % 4 > 0: duel.toggle_attack(int(c.id))
		if duel.attacks.is_empty(): return
		if not duel.end_phase(): return
		if duel.phase != ELDuel.Phase.DEFENCE: return
		for c: Dictionary in duel.army(1 - attacker):
			if random.randi() % 3 == 0: continue
			var choice: Array = duel.attacks.duplicate()
			# Shuffled from the case's own generator, so a case is the same
			# board on every run (Array.shuffle draws from the global one).
			for i in range(choice.size() - 1, 0, -1):
				var j := random.randi_range(0, i)
				var held: Variant = choice[i]
				choice[i] = choice[j]
				choice[j] = held
			for target: int in choice:
				if duel.assign_block(int(c.id), target): break
	# The board as both sets of rules will find it.
	var before := _board(duel)
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = attacker
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.steady_weights(ctx.second)
	ctx.remember = true
	var model := ELCombatBrain.fight(ctx, duel, 3 if turn else 2)
	if model.is_empty(): return
	fights += 1
	if turn:
		# The attacker's turn ends and the other hero's begins.
		# Only the one turn under test: a creature that must attack would carry
		# it into a fight.
		for c: Dictionary in duel.army(attacker):
			if duel.has_flag(int(c.id), "Berserk"): return
		var guard := 0
		while duel.attacker == attacker and duel.phase != ELDuel.Phase.FINISHED and guard < 3:
			guard += 1
			if not duel.end_phase(): break
		if duel.attacker == attacker or duel.phase == ELDuel.Phase.FINISHED: return
	else:
		duel._resolve_attacks()
	var said := _compare(duel, model, before, turn)
	if said.is_empty():
		if verbose: print("SAME case %d" % index)
		return
	differed += 1
	if quiet: return
	print("DIFF case %d: %s" % [index, " | ".join(said)])
	print("   " + before.text)

## --line=1: the lines the engine itself chooses, in duels it plays against
## the search, each played through both sets of rules. A search picks the
## lines on which its rules come out best, so it finds whatever the model
## gets wrong in its own favour far more often than chance would.
func _lines(duels: int, shard: String) -> void:
	var letters := {"Red": "R", "Green": "G", "Blue": "U", "Black": "B"}
	var books: Array = []
	for faction: String in ELCatalog.STARTERS.keys():
		books.append({"faction": faction, "deck": ELCatalog.STARTERS[faction], "level": 1})
		for level in range(2, 7):
			var name := "PR%s%d" % [String(letters.get(faction, "?")), level]
			if not ELCatalog.deck(profile, name).is_empty(): books.append({"faction": faction, "deck": name, "level": level * 2})
	var random := RandomNumberGenerator.new()
	# The replay draws what the engine counted on drawing.
	ELCombatBrain.fight_blind = ELCombatSearch.smart_engine_blind
	for n in duels:
		if n % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		random.seed = hash([91, n / 2])
		var first: Dictionary = books[random.randi() % books.size()]
		var matching := books.filter(func(book: Dictionary) -> bool: return book.level == first.level)
		var players := [first, matching[random.randi() % matching.size()]]
		var engine_side := n % 2
		var duel := ELDuel.new()
		if not duel.start(profile, 3000 + n / 2, {"players": players}): continue
		var guard := 0
		while duel.phase != ELDuel.Phase.FINISHED and guard < 900 and duel.round_number < 40:
			guard += 1
			var side := duel.active_side()
			ELCombatSearch.smart_engine = side == engine_side
			var smart: Array[int] = [side]
			duel.smart_sides = smart
			var stats := {}
			if side == engine_side: stats.line = PackedInt32Array()
			var command := ELCombatSearch.think(duel, stats)
			if side == engine_side and (stats.line as PackedInt32Array).size() > 12:
				cases += 1
				_line_case(n * 1000 + guard, duel, stats.line)
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	ELCombatSearch.smart_engine = false
	ELCombatBrain.fight_blind = true

## One line of the engine's, as it gave it, through both sets of rules.
func _line_case(index: int, duel: ELDuel, raw: PackedInt32Array) -> void:
	var start := duel.search_copy()
	var copy := duel.search_copy()
	var before := _board(copy)
	var ctx := _context(copy.active_side())
	var ids: Array = copy.creatures.keys()
	# The engine's place for each card now in a hand, and the draws it has named.
	var places: Array = [[], []]
	var drawn := [0, 0]
	# What each hero will draw, as the engine was told it: a draw that fails
	# keeps its place there.
	var coming: Array = ELCombatBrain.foreseen(copy)
	for side in 2:
		for i in copy.heroes[side].hand.size(): places[side].append(i if i < ELCombatBrain.HAND else -1)
	var commands: Array = []
	var said: Array[String] = []
	var after: Array = []
	var trouble: Array[String] = []
	var walked: Array[String] = []
	var refused := ""
	var refused_side := -1
	# Per hero: whether a card came that was not the next one the engine was
	# told of (the deal went its own way: the duel's chance, or a second-game
	# book that deals by the uses left, which what was cast since changes).
	var deal_parted := [false, false]
	# Whether the deal had parted for either hero after each command.
	var parted_at: Array[bool] = []
	for i in int(raw[8]):
		var at := 9 + i * 4
		if at + 3 >= raw.size() or copy.phase == ELDuel.Phase.FINISHED: break
		var cmd := [int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3])]
		var side := copy.active_side()
		var ok := true
		var what := ""
		var held := [copy.heroes[0].hand.duplicate(), copy.heroes[1].hand.duplicate()]
		match int(cmd[0]):
			0:
				what = "end the phase"
				ok = copy.end_phase()
			5:
				var mask := (int(cmd[1]) & 0xffff) | (int(cmd[2]) << 16)
				what = "attack with"
				# The guards last, as the engine sends them.
				for late in 2:
					for k in ids.size():
						if not (mask & (1 << k)) or copy.attacks.has(int(ids[k])) or copy.has_flag(int(ids[k]), "TeamAttack") != (late == 1): continue
						what += " #%d" % int(ids[k])
						if not ELCombatSearch.apply(copy, {"kind": "attack", "id": int(ids[k])}): ok = false
			6:
				what = "block as advised"
				var part := ELCombatBrain.fight(ctx, start, 4, commands + [cmd], 200000)
				for blocker: int in part.get("blocks", {}):
					if copy.blocks.has(blocker): continue
					what += " #%d>#%d" % [blocker, int(part.blocks[blocker])]
					if not ELCombatSearch.apply(copy, {"kind": "block", "id": blocker, "target": int(part.blocks[blocker])}): ok = false
			3:
				var place: int = (places[side] as Array).find(int(cmd[1]))
				if place < 0 and int(cmd[1]) >= ELCombatBrain.SLOTS:
					# A card that came back from the board or a graveyard: the
					# engine holds those apart, in the order they came.
					var back: Array = []
					for k in (places[side] as Array).size():
						if int(places[side][k]) == -1 and String(copy.profile.table("CombatSpells").get(String(copy.heroes[side].hand[k]), {}).get("Class", "")) == "Creature": back.append(k)
					# (Or the card of an enchantment that came back off a creature.)
					if back.is_empty():
						for k in (places[side] as Array).size():
							if int(places[side][k]) == -1: back.append(k)
					if not back.is_empty(): place = int(back[mini(int(cmd[1]) - ELCombatBrain.SLOTS, back.size() - 1)])
				if place < 0:
					# Two cards alike may have been taken one for the other.
					var slot := int(cmd[1])
					var wanted := ""
					if slot >= 0 and slot < ELCombatBrain.HAND and slot < start.heroes[side].hand.size(): wanted = String(start.heroes[side].hand[slot])
					elif slot >= ELCombatBrain.HAND and slot - ELCombatBrain.HAND < (coming[side] as Array).size(): wanted = String(coming[side][slot - ELCombatBrain.HAND])
					if not wanted.is_empty(): place = copy.heroes[side].hand.find(wanted)
				if place < 0:
					# A card the engine was told the hero would draw: what was
					# played since may have changed what the book deals, and
					# that is chance, not a rule the model has wrong.
					var later := int(cmd[1]) >= ELCombatBrain.HAND and int(cmd[1]) < ELCombatBrain.SLOTS
					what = "cast a card %s (place %d of %s, hand %s, to come %s)" % ["foreseen but not drawn" if later else "the hand does not hold", int(cmd[1]), str(places[side]), ",".join(copy.heroes[side].hand), ",".join(coming[side])]
					ok = false
				else:
					var step := ELCombatBrain._command_of(copy, ids, 3, place, int(cmd[2]), int(cmd[3]))
					what = "cast %s" % String(step.get("card", "?"))
					ok = String(step.kind) == "cast" and ELCombatSearch.apply(copy, step)
					if ok:
						# The card played is the one that left the hand.
						(held[side] as Array).remove_at(place)
						(places[side] as Array).remove_at(place)
			_:
				var step := ELCombatBrain._command_of(copy, ids, int(cmd[0]), int(cmd[1]), int(cmd[2]), int(cmd[3]))
				what = "%s %s" % [String(step.kind), String(step.get("key", "#%d" % int(step.get("id", -1))))]
				if int(cmd[0]) == 7: what = "use %s" % String(copy.creatures.get(int(step.get("id", -1)), {}).get("card", "?"))
				ok = String(step.kind) != "end_phase" and ELCombatSearch.apply(copy, step)
		if not ok:
			refused = what
			refused_side = side
			break
		# A hand keeps its cards in the order they came: what has left it is
		# struck out, and what has come into it are the next cards the engine
		# was told of. New creatures stand after the ones it knew.
		for hero in 2:
			var now: Array = copy.heroes[hero].hand
			var before_cards: Array = held[hero]
			var slots: Array = []
			var at_now := 0
			for k in before_cards.size():
				if at_now < now.size() and String(now[at_now]) == String(before_cards[k]):
					slots.append(int((places[hero] as Array)[k]))
					at_now += 1
			for extra in now.size() - at_now:
				# A card that came to the far end of the row was not drawn (a
				# drawn one comes to the near end): it came back from the board
				# or a graveyard, and the engine holds it apart.
				var keys: Array = ELDuel._hand_view(copy.heroes[hero])
				var came_back := false
				for earlier in at_now + extra:
					if int(keys[earlier]) < int(keys[at_now + extra]): came_back = true
				# (A first-game revival comes to the near end like a draw, but
				# a card from the book is the only kind with a place in it.)
				var book_slots: Array = copy.heroes[hero].get("hand_slots", [])
				if what == "cast JRRG" and at_now + extra < book_slots.size() and int(book_slots[at_now + extra]) < 0: came_back = true
				if came_back:
					# The engine holds it in its first free place for cards that
					# came back (a place frees when its card leaves the hand).
					var free := -1
					for j in ELCombatBrain.BACK:
						if not slots.has(ELCombatBrain.SLOTS + j):
							free = ELCombatBrain.SLOTS + j
							break
					slots.append(free)
					continue
				# The next card the engine was told of that is this one.
				var named := -1
				var listed: Array = coming[hero]
				for k in range(int(drawn[hero]), listed.size()):
					if String(listed[k]) == String(now[at_now + extra]):
						named = k
						break
				slots.append(ELCombatBrain.HAND + named if named >= 0 else -1)
				if named != int(drawn[hero]): deal_parted[hero] = true
				if named >= 0: drawn[hero] = named + 1
			places[hero] = slots
		for id: int in copy.creatures:
			if not ids.has(id): ids.append(id)
		commands.append(cmd)
		said.append(what)
		after.append(copy.search_copy())
		parted_at.append(bool(deal_parted[0]) or bool(deal_parted[1]))
	if commands.is_empty() and refused.is_empty(): return
	# The first command after which the two no longer agree: a command the
	# game turns down later is often only what that parting led to.
	for i in said.size():
		var part := ELCombatBrain.fight(ctx, start, 4, commands.slice(0, i + 1), 200000)
		if part.is_empty(): return
		# Whether the game drew on chance along the line so far (which card
		# a robber took, a hand dealt again): the engine reads on with the
		# cards it was told of, and says which lines those are when asked to
		# tell. The hands are then held by number, not by name.
		var reading := ELCombatBrain.fight_blind
		ELCombatBrain.fight_blind = true
		dealt_again = int(ELCombatBrain.fight(ctx, start, 4, commands.slice(0, i + 1), 200000).get("blind", 0)) != 0
		ELCombatBrain.fight_blind = reading
		var parting := _compare(after[i], part, before, true)
		dealt_again = false
		var phase_now := 0 if (after[i] as ELDuel).phase == ELDuel.Phase.ATTACK else 1
		if (after[i] as ELDuel).phase != ELDuel.Phase.FINISHED and int(part.phase) != phase_now:
			parting.append("the game stands in phase %d, the model in %d" % [phase_now, int(part.phase)])
		if int(part.played) != i + 1: parting.append("the model turned down one of its own commands")
		var game: ELDuel = after[i]
		walked.append("%s: game %d/%d health %d/%d ether, model %d/%d health %d/%d ether" % [said[i],
			int(game.heroes[0].health), int(game.heroes[1].health), int(game.heroes[0].mana), int(game.heroes[1].mana),
			int(part.health[0]), int(part.health[1]), int(part.ether[0]), int(part.ether[1])])
		if parting.is_empty(): continue
		if parted_at[i]:
			# The cards dealt since are not the ones the engine was told of:
			# what it cast by its places is then another card, by chance.
			line_chance += 1
			if not quiet: print("CHANCE case %d (%s): %s | first after \"%s\" (the deal parted)" % [index, ", ".join(said), " | ".join(parting), said[i]])
			return
		trouble = parting
		var name: String = String(said[i]).get_slice(" #", 0)
		line_blame[name] = int(line_blame.get(name, 0)) + 1
		trouble.append("first after \"%s\"" % said[i])
		break
	if trouble.is_empty() and not refused.is_empty() and refused.begins_with("cast"):
		# A card cast that the game does not have where the engine counted on
		# it, after the deal parted from what the engine was told or after a
		# card was taken or dealt by chance (the engine marks such lines blind):
		# chance, which the model is not to follow card by card.
		var reading := ELCombatBrain.fight_blind
		ELCombatBrain.fight_blind = true
		var blind_now := not commands.is_empty() and int(ELCombatBrain.fight(ctx, start, 4, commands, 200000).get("blind", 0)) != 0
		ELCombatBrain.fight_blind = reading
		if blind_now or bool(deal_parted[refused_side]):
			line_chance += 1
			if not quiet: print("CHANCE case %d (%s): the game turned down \"%s\" (%s)" % [index, ", ".join(said), refused, "blind line" if blind_now else "the deal parted"])
			return
	if trouble.is_empty() and not refused.is_empty():
		trouble.append("the game turned down \"%s\"" % refused)
		var blamed_for := "refused: " + refused.get_slice(" #", 0).get_slice(" (", 0)
		line_blame[blamed_for] = int(line_blame.get(blamed_for, 0)) + 1
	if trouble.is_empty():
		if verbose: print("SAME case %d: %s" % [index, ", ".join(said)])
		return
	differed += 1
	if quiet: return
	print("DIFF case %d (%s): %s" % [index, ", ".join(said), " | ".join(trouble)])
	print("   " + before.text)
	if verbose:
		var whole: Array = []
		for i in int(raw[8]): whole.append([int(raw[9 + i * 4]), int(raw[10 + i * 4]), int(raw[11 + i * 4]), int(raw[12 + i * 4])])
		print("   line: %s" % str(whole))
		for step: String in walked: print("      " + step)
	var standing: Array[String] = []
	for side in 2:
		for e: Dictionary in start.heroes[side].get("enchantments", []): standing.append("hero %d %s" % [side, String(e.card)])
		standing.append("hand %d %s" % [side, ",".join(start.heroes[side].hand)])
	for id: int in start.creatures:
		for e: Dictionary in start.creatures[id].get("enchantments", []): standing.append("#%d %s" % [id, String(e.card)])
	print("   standing: " + ", ".join(standing))

## Where the two boards disagree, in words.
func _compare(duel: ELDuel, model: Dictionary, before: Dictionary, whole_turn: bool) -> Array[String]:
	var said: Array[String] = []
	for id: int in before.units:
		var card: String = before.units[id].card
		var theirs: int = int(model.units.get(id, -2))
		var ours := -1 if not duel.creatures.has(id) else int(duel.creatures[id].damage)
		if theirs != ours:
			said.append("#%d %s %s: the game says %s, the model %s" % [id, card, before.units[id].stats, _damage(ours), _damage(theirs)])
			blamed[card] = int(blamed.get(card, 0)) + 1
		elif ours >= 0 and duel.phase != ELDuel.Phase.FINISHED and bool(model.resting.get(id, false)) != bool(duel.creatures[id].resting):
			said.append("#%d %s %s: the game leaves it %s, the model %s" % [id, card, before.units[id].stats, "resting" if duel.creatures[id].resting else "ready", "resting" if model.resting.get(id, false) else "ready"])
			blamed[card] = int(blamed.get(card, 0)) + 1
	if whole_turn:
		for side in 2:
			if int(duel.heroes[side].channels) != int(model.channels[side]):
				said.append("hero %d: the game leaves %d channels, the model %d" % [side, int(duel.heroes[side].channels), int(model.channels[side])])
		if duel.attacker != int(model.attacker):
			said.append("the game gives the turn to side %d, the model to %d" % [duel.attacker, int(model.attacker)])
		# What the two count beside: cards held, cards buried, creatures in play.
		var counts: Dictionary = model.get("counts", {})
		if not counts.is_empty() and duel.phase != ELDuel.Phase.FINISHED:
			for side in 2:
				if int(duel.heroes[side].hand.size()) != int(counts.hands[side]):
					said.append("hero %d: the game leaves %d cards in hand, the model %d" % [side, duel.heroes[side].hand.size(), int(counts.hands[side])])
				if int(duel.heroes[side].grave.size()) != int(counts.graves[side]):
					said.append("hero %d: the game leaves %d cards buried, the model %d" % [side, duel.heroes[side].grave.size(), int(counts.graves[side])])
				if duel.army(side).size() != int(counts.armies[side]):
					said.append("hero %d: the game leaves %d creatures, the model %d" % [side, duel.army(side).size(), int(counts.armies[side])])
	for side in 2:
		if int(duel.heroes[side].health) != int(model.health[side]):
			said.append("hero %d: the game leaves %d health, the model %d" % [side, int(duel.heroes[side].health), int(model.health[side])])
		if int(duel.heroes[side].mana) != int(model.ether[side]):
			said.append("hero %d: the game leaves %d ether, the model %d" % [side, int(duel.heroes[side].mana), int(model.ether[side])])
	if model.has("stats") and duel.phase != ELDuel.Phase.FINISHED: said.append_array(_compare_rest(duel, model, before, whole_turn))
	return said

## The rest of what the two sets of rules leave, where the library tells it.
func _compare_rest(duel: ELDuel, model: Dictionary, before: Dictionary, whole_turn: bool) -> Array[String]:
	var said: Array[String] = []
	var stats: Dictionary = model.stats
	for id: int in before.units:
		if not duel.creatures.has(id) or int(model.units.get(id, -2)) < 0 or not stats.has(id): continue
		var c: Dictionary = duel.creatures[id]
		var told: Dictionary = stats[id]
		var card: String = before.units[id].card
		if int(c.power) != int(told.power) or int(c.toughness) != int(told.toughness):
			said.append("#%d %s: the game makes it %d/%d, the model %d/%d" % [id, card, int(c.power), int(c.toughness), int(told.power), int(told.toughness)])
			blamed[card] = int(blamed.get(card, 0)) + 1
		var done: Dictionary = c.get("ability_used", {})
		var spent: bool = done.get("rouse", false) or done.get("illusion", false)
		if spent != bool(told.spent):
			said.append("#%d %s: the game has its ability %s, the model %s" % [id, card, "spent" if spent else "ready", "spent" if told.spent else "ready"])
			blamed[card] = int(blamed.get(card, 0)) + 1
		# Marks fixed for good (a snake's bite) the model folds into the
		# creature's points, which are held above; the rest it keeps as laid.
		var laid := 0
		for e: Dictionary in c.enchantments:
			if not e.get("fixed", false): laid += 1
		var told_laid := int(told.worn)
		if laid != told_laid and not (laid < told_laid and (c.enchantments as Array).size() == told_laid):
			said.append("#%d %s: the game has it wear %d enchantments, the model %d" % [id, card, laid, told_laid])
			blamed[card] = int(blamed.get(card, 0)) + 1
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		# Cards by name, where the model names every card it counts.
		var counts: Dictionary = model.get("counts", {})
		var named: Array = model.named[side]
		if whole_turn and not dealt_again and not counts.is_empty() and named.size() == int(counts.hands[side]) and hero.hand.size() <= ELCombatBrain.HAND:
			var ours: Array = []
			for card: String in hero.hand: ours.append(ELCombatBrain._code(profile, card))
			ours.sort()
			var theirs := named.duplicate()
			theirs.sort()
			if ours != theirs: said.append("hero %d: the game's hand is %s, the model's %s" % [side, ",".join(hero.hand), _card_names(theirs)])
		var worn: Array = model.hero_worn[side]
		var used: Array = model.hero_used[side]
		for k in ELCombatBrain.CHARMS.size():
			var charm: String = ELCombatBrain.CHARMS[k]
			var count := 0
			var spent := 0
			for e: Dictionary in hero.enchantments:
				# Twins are told as the one they work like.
				if String(ELCombatBrain.CHARM_TWINS.get(String(e.card), String(e.card))) != charm: continue
				count += 1
				if e.get("used", false): spent += 1
			if k < worn.size() and count != int(worn[k]):
				said.append("hero %d: the game has it wear %d %s, the model %d" % [side, count, charm, int(worn[k])])
			if k < used.size() and k < ELCombatBrain.HERO_KEYS.size() and spent != int(used[k]):
				said.append("hero %d: the game has %d %s used, the model %d" % [side, spent, charm, int(used[k])])
	return said

func _card_names(codes: Array) -> String:
	var names: Array = []
	for code: int in codes:
		var name := "?"
		for card: String in profile.table("CombatSpells"):
			if ELCombatBrain._code(profile, card) == code:
				name = card
				break
		names.append(name)
	return ",".join(names)

## A short run of commands through both sets of rules. The model is handed the
## board as it stood, then the same commands, and must arrive where the game
## arrived.
func _play_case(index: int, duel: ELDuel, random: RandomNumberGenerator, attacker: int) -> void:
	var start := duel.search_copy()
	var before := _board(duel)
	# Where each card of a hand stood when the model was told the board.
	var hands: Array = [[], []]
	for side in 2:
		for i in mini(duel.heroes[side].hand.size(), ELCombatBrain.HAND): hands[side].append(i)
	var spots := {}
	var order: Array = duel.creatures.keys()
	for i in order.size(): spots[int(order[i])] = i
	var commands: Array = []
	var said: Array[String] = []
	var holds: Array = [duel.heroes[0].hand.size(), duel.heroes[1].hand.size()]
	for step in random.randi_range(1, 5):
		if duel.phase == ELDuel.Phase.FINISHED: break
		# A hand that lost or gained a card by anything but its own cast no
		# longer lies as the model was told it.
		if duel.heroes[0].hand.size() != int(holds[0]) or duel.heroes[1].hand.size() != int(holds[1]): break
		var kind := random.randi() % 4
		if not artifact_names.is_empty() and random.randi() % 3 == 0:
			# The hero to move uses a thing it carries.
			var bearer := duel.active_side()
			var things: Array = duel.heroes[bearer].get("artifacts", [])
			var usable: Array = []
			for k in mini(things.size(), ELCombatBrain.MAX_ART):
				if duel.artifact_error(bearer, k).is_empty() and not ELCombatBrain.artifact_card(_context(bearer), duel, things[k]).is_empty(): usable.append(k)
			if usable.is_empty(): continue
			var which: int = usable[random.randi() % usable.size()]
			var thing: Dictionary = things[which]
			var works := String(thing.spell)
			var made: bool = thing.has("custom")
			var thing_rule: Dictionary = ELCatalog.rule(profile, works) if made else ELCatalog.ARTIFACT_EFFECTS[works]
			var wanted := String(duel.artifact_rule(thing).get("target", "none"))
			var choosing := int(ELCombatBrain.CHOICES.get(String(thing_rule.get("effect", "")), 0))
			if choosing in [2, 3, 5, 6]: continue
			var open: Array = []
			if wanted in ["any", "hero", "grave", "enchantment"]: open = [0, 1]
			if wanted in ["any", "creature", "enchantment"]:
				for id: int in duel.creatures:
					if spots.has(id): open.append(id)
			if wanted != "none" and open.is_empty(): continue
			var aim: int = -1 if wanted == "none" else open[random.randi() % open.size()]
			var second := -1
			var told := 0
			if choosing == 1:
				# A creature card of a graveyard, by its place among the newest.
				if not made: aim = bearer
				var lying: Array = duel.heroes[aim].grave
				var found: Array = []
				for place in lying.size():
					if profile.table("CombatCreatures").has(lying[place]): found.append(place)
				if found.is_empty(): continue
				second = found[random.randi() % found.size()]
				told = second - (lying.size() - mini(lying.size(), ELCombatBrain.GRAVES))
				if told < 0: continue
			elif choosing == 4:
				# An enchantment on what it is aimed at, as the engine names it.
				var names: Array = []
				for e: Dictionary in duel.entity(aim).get("enchantments", []):
					var what := ELCombatBrain.enchantment_name(duel, aim, e)
					if what >= 0 and duel.dispellable(aim, e) and not names.has(what): names.append(what)
				if names.is_empty(): continue
				told = names[random.randi() % names.size()]
				second = ELCombatBrain.enchantment_named(duel, aim, told)
				if second < 0: continue
			if not duel.use_artifact(bearer, which, aim, second): continue
			commands.append([3, ELCombatBrain.ART_BASE + which, -99 if aim < 0 else (-1 - aim if aim < 2 else int(spots[aim])), told])
			said.append("cast %s%s" % ["made-" if made else "art-", works])
			if String(thing_rule.get("effect", "")) in ["redraw", "amnesia", "pale_theft", "pale_calamity"]: break
			continue
		if kind == 3:
			# A creature of the hero to move uses an ability the model plays.
			var able: Array = []
			for c: Dictionary in duel.army(duel.active_side()):
				var named_key := ELCombatBrain.ability_key(profile, String(c.card))
				if spots.has(int(c.id)) and not named_key.is_empty() and duel.can_use_ability(int(c.id), named_key): able.append(int(c.id))
			# A creature held down is freed.
			var held: Array = []
			for c: Dictionary in duel.army(duel.active_side()):
				for freeing: String in ["wake", "awaken", "unparalyze"]:
					if spots.has(int(c.id)) and duel.can_use_ability(int(c.id), freeing): held.append([int(c.id), freeing])
			if not held.is_empty() and random.randi() % 2 == 0:
				var freed: Array = held[random.randi() % held.size()]
				if not duel.use_ability(int(freed[0]), String(freed[1])): continue
				commands.append([4, int(spots[int(freed[0])]), 0, 0])
				said.append("free #%d" % int(freed[0]))
				continue
			# A pale creature of the second game does one of the things it may.
			var shades: Array = []
			if profile.id == "el2":
				for c: Dictionary in duel.army(duel.active_side()):
					if not spots.has(int(c.id)) or not duel.pale(int(c.id)): continue
					for ability: Dictionary in duel.abilities(int(c.id)):
						if ability.get("pale", false): shades.append([int(c.id), ability])
			if not shades.is_empty() and random.randi() % 2 == 0:
				var shade: Array = shades[random.randi() % shades.size()]
				var shade_id: int = shade[0]
				var does := String(shade[1].key)
				var shade_card := String(duel.creatures[shade_id].card)
				var aim := -1
				var chosen := -1
				var named := 0
				match String(shade[1].get("target", "none")):
					"grave":
						aim = int(random.randi() & 1)
						var size: int = duel.heroes[aim].grave.size()
						if size == 0: continue
						chosen = random.randi_range(maxi(0, size - ELCombatBrain.GRAVES), size - 1)
						named = chosen - (size - mini(size, ELCombatBrain.GRAVES))
					"creature", "any":
						var open: Array = [0, 1] if String(shade[1].target) == "any" else []
						for id: int in duel.creatures:
							if spots.has(id): open.append(id)
						if open.is_empty(): continue
						aim = open[random.randi() % open.size()]
					"enchantment":
						var holders: Array = [0, 1]
						for id: int in duel.creatures:
							if spots.has(id): holders.append(id)
						aim = holders[random.randi() % holders.size()]
						var names: Array = []
						for e: Dictionary in duel.entity(aim).get("enchantments", []):
							var what := ELCombatBrain.enchantment_name(duel, aim, e)
							if what >= 0 and not names.has(what): names.append(what)
						if names.is_empty(): continue
						named = names[random.randi() % names.size()]
						chosen = ELCombatBrain.enchantment_named(duel, aim, named, 2 if does == "weave" else 0, duel.active_side() if does == "mystic" else -1)
						if chosen < 0: continue
				if not duel.use_ability(shade_id, does, aim, chosen): continue
				commands.append([11, int(spots[shade_id]), -99 if aim < 0 else (-1 - aim if aim < 2 else int(spots[aim])), (ELCombatBrain.PALE_KEYS.find(does) << 16) | named])
				said.append("cast %s:%s" % [shade_card, does])
				continue
			# And what the hero itself may do through its enchantments.
			var gifts: Array = []
			for ability: Dictionary in duel.abilities(duel.active_side()):
				if ELCombatBrain.HERO_KEYS.has(String(ability.get("effect", ""))) and duel.can_use_ability(duel.active_side(), String(ability.key)): gifts.append(ability)
			if not gifts.is_empty() and (able.is_empty() or random.randi() % 2 == 0):
				var gift: Dictionary = gifts[random.randi() % gifts.size()]
				var hero_side := duel.active_side()
				var which: int = ELCombatBrain.HERO_KEYS.find(String(gift.effect))
				var wanted := String(gift.get("target", "none"))
				var choices: Array = [-1] if wanted in ["none", "grave"] else ([0, 1] if wanted == "any" else [])
				if wanted in ["any", "creature"]:
					for id: int in duel.creatures:
						if spots.has(id): choices.append(id)
				if choices.is_empty(): continue
				var chosen: int = choices[random.randi() % choices.size()]
				var grave_choice := -1
				var told := 0
				if wanted == "grave":
					var buried: Array = duel.grave_ability_targets(hero_side, String(gift.key), hero_side)
					if buried.is_empty(): continue
					chosen = hero_side
					grave_choice = buried[random.randi() % buried.size()]
					# By its place among the newest, which the model is told.
					var size: int = duel.heroes[hero_side].grave.size()
					told = grave_choice - (size - mini(size, ELCombatBrain.GRAVES))
					if told < 0: continue
				elif String(gift.effect) in ["combine", "burnout", "recycle"]:
					# The second thing it names: another creature, or a hero.
					var others: Array = [0, 1] if String(gift.effect) == "burnout" else []
					for id: int in duel.creatures:
						if spots.has(id): others.append(id)
					if others.is_empty(): continue
					grave_choice = others[random.randi() % others.size()]
					told = -1 - grave_choice if grave_choice < 2 else int(spots[grave_choice])
				if not duel.use_ability(hero_side, String(gift.key), chosen, grave_choice): continue
				commands.append([8, which, -99 if chosen < 0 or wanted == "grave" else (-1 - chosen if chosen < 2 else int(spots[chosen])), told])
				said.append("cast %s" % ELCombatBrain.CHARMS[which])
				continue
			if able.is_empty(): continue
			var user: int = able[random.randi() % able.size()]
			var user_card := String(duel.creatures[user].card)
			var key := ELCombatBrain.ability_key(profile, user_card)
			var able_rule := ELCatalog.first_ability(profile, user_card)
			var wants := "any" if key == "spores" else ("enchantment" if key == "disenchant" else String(able_rule.get("target", "none")))
			var aims: Array = [-1] if wants == "none" else ([0, 1] if wants in ["any", "grave", "hero", "enchantment"] else [])
			if wants in ["any", "creature", "enchantment"]:
				for id: int in duel.creatures:
					if spots.has(id): aims.append(id)
			if aims.is_empty(): continue
			var aim: int = aims[random.randi() % aims.size()]
			# A card of a graveyard is named by its place among the newest,
			# and an X is the ether poured in.
			var buried_choice := -1
			var poured := -1
			var extra := 0
			if wants == "grave":
				var open: Array = duel.grave_ability_targets(user, key, aim)
				if open.is_empty(): continue
				buried_choice = open[random.randi() % open.size()]
				var size: int = duel.heroes[aim].grave.size()
				extra = buried_choice - (size - mini(size, ELCombatBrain.GRAVES))
				if extra < 0: continue
			elif wants == "enchantment":
				# One of those on what it is aimed at, as the engine names it.
				var open: Array = []
				for e: Dictionary in duel.entity(aim).get("enchantments", []):
					var what := ELCombatBrain.enchantment_name(duel, aim, e)
					if what >= 0 and not open.has(what): open.append(what)
				if open.is_empty(): continue
				extra = open[random.randi() % open.size()]
				buried_choice = ELCombatBrain.enchantment_named(duel, aim, extra, 1 if key == "disenchant" else 0)
				if buried_choice < 0: continue
			elif key != "spores" and able_rule.get("variable", false):
				poured = random.randi_range(int(able_rule.get("minimum", 0)), 3)
				extra = poured
			if not duel.use_ability(user, key, aim, buried_choice, poured): continue
			commands.append([7, int(spots[user]), -99 if aim < 0 else (-1 - aim if aim < 2 else int(spots[aim])), extra])
			said.append("cast %s" % user_card)
		elif kind == 1 and duel.phase == ELDuel.Phase.DEFENCE:
			var guards := duel.army(1 - duel.attacker)
			if guards.is_empty() or duel.attacks.is_empty(): continue
			var blocker: Dictionary = guards[random.randi() % guards.size()]
			var against: int = duel.attacks[random.randi() % duel.attacks.size()]
			# The model takes each blocker's choice once; the game lets it be changed.
			if duel.blocks.has(int(blocker.id)): continue
			if not spots.has(int(blocker.id)) or not spots.has(against) or not duel.assign_block(int(blocker.id), against): continue
			commands.append([2, int(spots[int(blocker.id)]), int(spots[against]), 0])
			said.append("block #%d with #%d" % [against, int(blocker.id)])
		elif kind == 0 and not hands[duel.active_side()].is_empty():
			# The hero to move plays a card: the defender has only a few it may.
			var caster := duel.active_side()
			var places: Array = hands[caster]
			var at := random.randi() % places.size()
			if at >= duel.heroes[caster].hand.size(): continue
			var card: String = duel.heroes[caster].hand[at]
			if duel.phase != ELDuel.Phase.ATTACK and not card in ELDuel.DEFENCE_SPELLS.get(profile.id, []): continue
			if not ELCombatBrain.EFFECTS.has(String(ELCatalog.rule(profile, card).get("effect", ""))): continue
			# Only the cards the model holds a rule for are put to it.
			if ELCombatBrain._card(_context(caster), duel, card).is_empty(): continue
			var targets: Array = duel.valid_targets(card) if duel.target_kind(card) != "none" else [-1]
			if targets.is_empty(): continue
			var target: int = targets[random.randi() % targets.size()]
			var named := -99 if target < 0 else (-1 - target if target < 2 else int(spots.get(target, -1000)))
			if named == -1000: continue
			var power := 0
			if duel.variable_power(card): power = random.randi_range(0, maxi(0, mini(3, duel.maximum_power(card))))
			# What the card names beside its target: a card of a graveyard, by
			# its place among the newest, or another creature.
			var second := -1
			var told := power
			var choosing := int(ELCombatBrain.CHOICES.get(String(ELCatalog.rule(profile, card).get("effect", "")), 0))
			if choosing in [1, 2]:
				var open: Array = duel.valid_grave_targets(card, target) if choosing == 1 else duel.valid_grave_targets(card)
				if open.is_empty(): continue
				second = open[random.randi() % open.size()]
				var size: int = duel.heroes[target if choosing == 1 else caster].grave.size()
				told = second - (size - mini(size, ELCombatBrain.GRAVES))
				if told < 0: continue
			elif choosing == 3:
				var open: Array = duel.swap_targets(card, target)
				if open.is_empty(): continue
				second = open[random.randi() % open.size()]
				if not spots.has(second): continue
				told = int(spots[second])
			elif choosing == 6:
				# A card of either graveyard, by its place among the newest.
				var open: Array = duel.valid_grave_targets(card)
				if open.is_empty(): continue
				second = open[random.randi() % open.size()]
				var whose: int = second / ELDuel.GRAVE_SIDE
				var size: int = duel.heroes[whose].grave.size()
				var place: int = second % ELDuel.GRAVE_SIDE - (size - mini(size, ELCombatBrain.GRAVES))
				if place < 0: continue
				told = whose * 64 + place
			elif choosing in [4, 5]:
				# An enchantment: on what the card is aimed at, or anywhere.
				var open: Array = duel.valid_enchantment_targets(card, target)
				if open.is_empty(): continue
				var holder: int = duel.find_enchantment(open[random.randi() % open.size()])
				if holder < 0 or (holder >= 2 and not spots.has(holder)): continue
				var what := -1
				for e: Dictionary in duel.entity(holder).enchantments:
					if open.has(int(e.id)) and what < 0: what = ELCombatBrain.enchantment_name(duel, holder, e)
				if what < 0: continue
				second = ELCombatBrain.enchantment_named(duel, holder, what)
				if second < 0: continue
				told = what if choosing == 4 else (holder if holder < 2 else int(spots[holder]) + 2) * 4096 + what
			var holding: int = duel.heroes[caster].hand.size()
			if not duel.cast(at, target, second, power): continue
			commands.append([3, places[at], named, told])
			holds[caster] = int(holds[caster]) - 1
			said.append("cast %s" % card)
			places.remove_at(at)
			# A spell that took cards out of the caster's own hand leaves the
			# places the model was told pointing at other cards.
			if duel.heroes[caster].hand.size() < holding - 1: break
			# And one that dealt a hand again leaves no card where it was.
			if String(ELCatalog.rule(profile, card).get("effect", "")) in ["redraw", "amnesia", "pale_theft", "pale_calamity"]: break
		elif kind == 1 and duel.phase == ELDuel.Phase.ATTACK:
			var army := duel.army(attacker)
			if army.is_empty(): continue
			var c: Dictionary = army[random.randi() % army.size()]
			if not spots.has(int(c.id)) or not duel.toggle_attack(int(c.id)): continue
			commands.append([1, int(spots[int(c.id)]), 0, 0])
			said.append("attack with #%d" % int(c.id))
		else:
			var was := duel.phase
			if not duel.end_phase(): continue
			commands.append([0, 0, 0, 0])
			said.append("end the phase")
			# A new turn draws a card and shifts the hand, so the places the
			# model was told would no longer be the game's.
			if was == ELDuel.Phase.DEFENCE or duel.attacker != attacker: break
	if commands.is_empty(): return
	fights += 1
	var ctx := _context(attacker)
	var model := ELCombatBrain.fight(ctx, start, 4, commands)
	if model.is_empty(): return
	dealt_again = false
	for line: String in said:
		if line.begins_with("cast "): cast_total[line.substr(5)] = int(cast_total.get(line.substr(5), 0)) + 1
		if line.begins_with("cast ") and String(ELCatalog.rule(profile, line.substr(5)).get("effect", "")) in ["redraw", "amnesia", "pale_theft", "pale_calamity", "ban"]: dealt_again = true
	# So is any card taken or dealt by the duel's chance, which the model says
	# of its own line (it holds the cards by number from there, not by name).
	if int(model.get("blind", 0)) != 0: dealt_again = true
	var trouble := _compare(duel, model, before, true)
	dealt_again = false
	if int(model.played) != commands.size():
		# Which command the model turned down.
		var refused := commands.size()
		for i in range(1, commands.size() + 1):
			var part := ELCombatBrain.fight(ctx, start, 4, commands.slice(0, i))
			if int(part.get("played", i)) < i:
				refused = i - 1
				break
		trouble.append("the model turned down \"%s\"" % (said[refused] if refused < said.size() else "?"))
	if trouble.is_empty():
		if verbose: print("SAME case %d: %s" % [index, ", ".join(said)])
		return
	differed += 1
	for line: String in said:
		if line.begins_with("cast "): cast_blame[line.substr(5)] = int(cast_blame.get(line.substr(5), 0)) + 1
	if quiet: return
	print("DIFF case %d (%s): %s" % [index, ", ".join(said), " | ".join(trouble)])
	print("   " + before.text)
	# --trace=1: the model's board after each command, to see where it parts.
	if _arg("trace", "") == "1":
		for i in range(1, commands.size() + 1):
			var part := ELCombatBrain.fight(ctx, start, 4, commands.slice(0, i))
			print("   after \"%s\" %s: health %s ether %s units %s resting %s" % [said[i - 1] if i - 1 < said.size() else "?", str(commands[i - 1]), str(part.get("health")), str(part.get("ether")), str(part.get("units")), str(part.get("resting"))])
	# What else stood in the position: the usual reason the model is wrong.
	var standing: Array[String] = []
	for side in 2:
		for e: Dictionary in start.heroes[side].get("enchantments", []): standing.append("hero %d %s" % [side, String(e.card)])
	for id: int in start.creatures:
		for e: Dictionary in start.creatures[id].get("enchantments", []): standing.append("#%d %s" % [id, String(e.card)])
	if not standing.is_empty(): print("   standing: " + ", ".join(standing))
	for item: String in standing:
		var card := item.get_slice(" ", item.get_slice_count(" ") - 1)
		standing_blame[card] = int(standing_blame.get(card, 0)) + 1

func _context(side: int) -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.steady_weights(ctx.second)
	ctx.remember = true
	return ctx

func _damage(amount: int) -> String:
	return "it died" if amount < 0 else "%d damage" % amount

## What stood on the board before the fight, for the report.
func _board(duel: ELDuel) -> Dictionary:
	var units := {}
	var text := "side %d attacks with %s, blocks %s" % [duel.attacker, str(duel.attacks), str(duel.blocks)]
	for side in 2:
		text += "\n      hero %d: %d health, %d ether" % [side, int(duel.heroes[side].health), int(duel.heroes[side].mana)]
		for c: Dictionary in duel.army(side):
			var flags: Array = ELCatalog.flags(profile.table("CombatCreatures").get(c.card, {}))
			var stats := "%d/%d%s%s" % [int(c.power), int(c.toughness), "" if int(c.get("damage", 0)) == 0 else " dmg%d" % int(c.damage), "" if flags.is_empty() else " " + " ".join(flags)]
			units[int(c.id)] = {"card": String(c.card), "stats": stats}
			text += "\n         #%d %s %s%s" % [int(c.id), c.card, stats, "r" if c.resting else ""]
	return {"units": units, "text": text}

# --- Hand-made positions -----------------------------------------------------------

## --parity=1: each position below is one where the model once parted from
## the game's rules. The game plays `steps` (each [kind, ...] as the model is
## told commands), the model is handed the position as it stood and the same
## commands, and the two must agree on everything compared, and on `expect`
## (a value read off the game's duel after the steps).
func _parity() -> void:
	var game := profile.id
	var level := _surest_level("RKBC")
	var surest := ELSpecs.chance(profile, "RKBC", level)
	var many: Array = []
	for i in 3: many.append("MGHT" if game == "el1" else "PRFY")
	_discard_pick()
	_won_in_the_fight()
	_wounded_blockers()
	_revised_block()
	# A lamia warlord in play makes every lamia two cheaper, to no less than 1.
	_fixture("lamia discount", {"heroes": [{"health": 20, "mana": 50, "hand": ["LMWD", "LMMN"]}, {"health": 20, "mana": 0}], "creatures": []},
		[["cast", 0], ["cast", 1]], func(d: ELDuel) -> bool: return int(d.heroes[0].mana) == 38)
	# #166: an orc warrior makes every orc aggressive. A guard summoned before
	# the warrior goes too as the turn begins: the warrior is sent first and is
	# then the guard's partner.
	for order: Array in [["ORGD", "ORWR"], ["ORWR", "ORGD"], ["ORGD", "ORGD", "ORWR"]]:
		var orcs: Array = []
		for card: String in order: orcs.append({"card": card, "owner": 0})
		_fixture("aggressive guards %s" % "+".join(PackedStringArray(order)), {"attacker": 1, "heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}], "creatures": orcs,
			"after": func(d: ELDuel) -> void: d._refresh_armies()}, [["end"]], func(d: ELDuel) -> bool: return d.attacker == 0 and d.phase == ELDuel.Phase.ATTACK and d.attacks.size() == order.size())
	# Kobold mastery that nearly always works (and here, by the duel's chance,
	# does) doubles a kobold's blow; the model counts on one that sure.
	if roundi(surest * 100.0) >= 90:
		_fixture("kobold mastery at %d%%" % roundi(surest * 100.0), {"rng": 0, "heroes": [{"health": 20, "mana": 0, "spec": "RKBC", "spec_level": level}, {"health": 10, "mana": 0}],
			"creatures": [{"card": "KBEL", "owner": 0, "power": 3, "toughness": 2}]},
			[["attack", 0], ["end"], ["end"]], func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 4)
	else:
		_missing("kobold mastery: no hero level makes the mastery nine times in ten sure (%.2f)" % surest)
	# A robber's lent discards go with the enchantment a stripping blow takes
	# off it: blocking the disenchanter strips the Thief, so the 6/5 then takes
	# no card from the hand it reaches.
	if game == "el1":
		_fixture("stripped robber", {"heroes": [{"health": 20, "mana": 0, "hand": many}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "IRAB", "owner": 0, "power": 3, "toughness": 5, "flags": ["Disenchant"]},
				{"card": "GROG", "owner": 1, "power": 6, "toughness": 5, "enchantments": ["THIF"]}]},
			[["attack", 0], ["end"], ["block", 1, 0], ["end"], ["attack", 1], ["end"], ["end"]], func(d: ELDuel) -> bool: return d.heroes[0].hand.size() == 3)
	# A hero with Regeneration that survives its ether disturbance heals after it.
	_fixture("regeneration after disturbance", {"attacker": 1, "heroes": [{"health": 2, "mana": 0, "maximum": 20, "turns": 15, "level": 4, "skills": {"REGN": 2}},
		{"health": 20, "mana": 0, "turns": 15, "level": 4}], "creatures": []},
		[["end"]], func(d: ELDuel) -> bool: return d.attacker == 0 and int(d.heroes[0].health) == 2)
	# One the disturbance kills is not saved by its Regeneration.
	_fixture("disturbance kills before regeneration", {"attacker": 1, "heroes": [{"health": 1, "mana": 0, "maximum": 20, "turns": 15, "level": 4, "skills": {"REGN": 2}},
		{"health": 20, "mana": 0, "turns": 15, "level": 4}], "creatures": []},
		[["end"]], func(d: ELDuel) -> bool: return d.phase == ELDuel.Phase.FINISHED and d.winner == 1)
	# The ether disturbance keeps growing past the turns the model is told
	# of (it once stood still at the sixth).
	var long_ends: Array = []
	for i in 18: long_ends.append(["end"])
	_fixture("disturbance past the told turns", {"heroes": [{"health": 300, "maximum": 300, "mana": 0, "turns": 15, "level": 4},
		{"health": 300, "maximum": 300, "mana": 0, "turns": 15, "level": 4}], "creatures": []},
		long_ends, func(d: ELDuel) -> bool: return int(d.heroes[0].health) < 300 - 40)
	# A puzzle's fixed hands draw nothing at the turn's start.
	_fixture("fixed hands draw nothing", {"attacker": 1, "heroes": [{"health": 20, "mana": 0, "hand": ["PRFY" if game == "el2" else "MGHT"]},
		{"health": 20, "mana": 0}], "creatures": []},
		[["end"]], func(d: ELDuel) -> bool: return d.attacker == 0 and d.heroes[0].hand.size() == 1)
	# A hero's Concentration at its best draws a card more every second turn
	# of its own: two cards as its sixteenth begins (the first game's book of
	# these positions has the cards for it).
	if game == "el1":
		_fixture("concentration draws two", {"attacker": 1, "fixed": false, "heroes": [{"health": 20, "mana": 0, "turns": 15, "level": 4, "skills": {"CONC": 2}},
			{"health": 20, "mana": 0, "turns": 15, "level": 4}], "creatures": []},
			[["end"]], func(d: ELDuel) -> bool: return d.attacker == 0 and d.heroes[0].hand.size() == 2)
	# A grass snake grows a point of each for good with each blow on a hero.
	_fixture("grass snake grows", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}], "creatures": [{"card": "GRSN", "owner": 0}]},
		[["attack", 0], ["end"], ["end"]], func(d: ELDuel) -> bool: return int(d.creatures[2].power) == int(Fixtures.build(profile, {"creatures": [{"card": "GRSN", "owner": 0}]}).creatures[2].power) + 1)
	# A destroying blow does not destroy a creature nothing may affect: it lives
	# through the fight (the model once killed it).
	_fixture("destroy against no-affect", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 6, "toughness": 5, "flags": ["NoAffect"]},
			{"card": "GROG", "owner": 1, "power": 2, "toughness": 2, "flags": ["Destroy", "FS"]}]},
		[["attack", 0], ["end"], ["block", 1, 0], ["end"]], func(d: ELDuel) -> bool: return d.creatures.has(2))
	# Blows that destroy kill in the order they landed, and the one ether of
	# regeneration goes to the first: the steam machine's victim (the Iron
	# Golem, met first) regenerates, the destroying warrior's (the Stone
	# Golem) dies. The model once took them in board order.
	if game == "el2":
		# (A position taken from an authored puzzle: {"puzzle": id}. There the
		# creatures are #2, #3, ... in order, so a creature's place is its id
		# less two.)
		_fixture("destroyed in the order struck", {"puzzle": "el2_tactical_v2_behind_magic_screen"},
			[["cast", 0], ["end"], ["end"], ["block", 0, 3], ["block", 1, 2], ["end"]],
			func(d: ELDuel) -> bool: return not d.creatures.has(2) and d.creatures.has(3))
		# A mother bee's death sends its hero's bees into a frenzy: berserk,
		# they go into the attack beside the fire fighter and hurt the hero by
		# four while the fighter is blocked (Cannibalism took two).
		_fixture("mother bee's frenzy", {"puzzle": "el2_tactical_v2_queens_shadow"},
			[["cast", 1, 2], ["attack", 3], ["end"], ["block", 4, 3], ["end"]],
			func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 4)
		# A beacon brings its bearer's race out of the plane with it: the
		# Spellshifter comes out beside the Spellbinder, and the Flux that
		# follows keeps all five allies (the model once left it in the plane).
		_fixture("beacon out of the plane", {"puzzle": "el2_tactical_v2_airlock_census"},
			[["cast", 0], ["do", {"choice": 3, "id": 2, "key": "mystic", "kind": "ability", "target": 4}], ["cast", 1]],
			func(d: ELDuel) -> bool: return d.army(0).size() == 5)
		# A creature given away waits for its new hero's turn, and is ready
		# then: the ogre attacks its old hero at once (the model once kept it
		# waiting a whole turn more).
		_fixture("gift ready on the new hero's turn", {"heroes": [{"health": 20, "mana": 10, "hand": ["GIFT"]}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "GROG", "owner": 0}]},
			[["cast", 0, 2], ["end"], ["attack", 0], ["end"], ["end"]],
			func(d: ELDuel) -> bool: return int(d.heroes[0].health) < 20)
		# A gray ogre the other hero's blow throws out of a hand comes into
		# play, whichever of three alike is taken (the model once had a
		# partial discard answer nothing).
		_fixture("ogre thrown out of a hand", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0, "hand": ["GROG", "GROG", "GROG"]}],
			"creatures": [{"card": "ORWR", "owner": 0, "flags": ["Discard(1)"]}]},
			[["attack", 0], ["end"], ["end"]], func(d: ELDuel) -> bool: return d.army(1).size() == 1 and d.heroes[1].hand.size() == 2)
		# A creature that changes sides keeps the army enchantments that
		# covered it as it went: the Cutter, freed of the other hero's
		# Change of Command, still has that hero's Strength of Woods, and
		# loses its two power when that is taken off the other hero (the
		# model once left it 9/6, as if no longer under it).
		_fixture("army enchantments kept across sides", {"puzzle": "el2_tactical_v2_chain_of_custody"},
			[["do", {"choice": 1, "id": 2, "key": "absorb", "kind": "ability", "target": 4}],
				["do", {"choice": 3, "id": 3, "key": "transpose", "kind": "ability", "target": 1}]],
			func(d: ELDuel) -> bool: return d.creatures.has(4) and int(d.creatures[4].owner) == 0 and int(d.creatures[4].power) == 7 and int(d.creatures[4].toughness) == 6)
		# The ether disturbance hurts a hero as a spell does: an energy barrier
		# takes three off it (the model once took it off the health directly).
		_fixture("disturbance against a barrier", {"puzzle": "el2_tactical_v2_behind_magic_screen"},
			[["cast", 2, 0], ["end"], ["end"], ["block", 1, 2], ["block", 0, 3], ["end"]],
			func(d: ELDuel) -> bool: return d.attacker == 0 and int(d.heroes[0].health) == 4)
	var spells: Dictionary = profile.table("CombatSpells")
	# Bloodlessness goes back to its caster's hand as its creature leaves
	# play, and is cast again on the next one (the model once held the card
	# without a name, and could not play it).
	if spells.has("RIOT") and spells.has("CLIG"):
		_fixture("bloodlessness comes back and is cast again", {"heroes": [{"health": 20, "mana": 10, "hand": ["RIOT", "CLIG"]}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "STRT", "owner": 1}, {"card": "STRT", "owner": 1}]},
			[["cast", 0, 2], ["cast", 1, 2], ["back", 0, 0, 3]],
			func(d: ELDuel) -> bool: return not d.creatures.has(2) and d.creatures.has(3) and d._enchantment_count(3, "RIOT") == 1 and d.heroes[0].hand.is_empty())
	# A water link an older position keeps on the creature itself works as
	# one its caster holds: the dead rat heals its hero and comes back.
	if spells.has("WTLK") and spells.has("CLIG"):
		_fixture("water link kept on the creature", {"heroes": [{"health": 10, "mana": 10, "hand": ["CLIG"]}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "STRT", "owner": 0, "enchantments": ["WTLK"]}]},
			[["cast", 0, 2]], func(d: ELDuel) -> bool: return d.army(0).size() == 1 and int(d.heroes[0].health) > 10 and d.heroes[0].grave.is_empty())
	# A lifeguard turns the blow away, not the destroying strike's mark: the
	# guarded blocker is destroyed after the fight all the same.
	if spells.has("LFGR"):
		_fixture("destroying strike through a lifeguard", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "GROG", "owner": 0, "power": 2, "toughness": 9, "flags": ["Destroy"]},
				{"card": "GROG", "owner": 1, "power": 1, "toughness": 9, "flags": [], "enchantments": ["LFGR"]}]},
			[["attack", 0], ["end"], ["block", 1, 0], ["end"]], func(d: ELDuel) -> bool: return not d.creatures.has(3))
	if game == "el2":
		# A lifeguard laid on the other hero's creature in defence turns the
		# first snake's blow away and its bite with it (the original, #269):
		# the second snake's bite and blow then leave the treant 1/1 to
		# regenerate with its hero's one ether. The puzzle's line counted on
		# the bite getting through the lifeguard, and no longer wins.
		_fixture("lifeguard on the attacker turns the bite away", {"puzzle": "el2_tactical_v2_crossroads_last_reprieve"},
			[["cast", 0, 4], ["block", 0, 2], ["block", 1, 2], ["end"]],
			func(d: ELDuel) -> bool: return d.creatures.has(4) and int(d.heroes[1].mana) == 0 and d._enchantment_count(4, "LFGR") == 0)
		# #269: a Lake Snake's blow that a lifeguard turns away leaves the
		# blocker's power and health as they were, and no venom on it.
		var guarded := {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
			"creatures": [{"card": "LASN", "owner": 0}, {"card": "GBAT", "owner": 1, "enchantments": ["LFGR"]}]}
		var bare_bat: Dictionary = Fixtures.build(profile, {"creatures": [{"card": "GBAT", "owner": 1}]}).creatures[2]
		_fixture("lake snake on a lifeguarded blocker", guarded, [["attack", 0], ["end"], ["block", 1, 0], ["end"]],
			func(d: ELDuel) -> bool: return d.creatures.has(3) and d._enchantment_count(3, "LASN") == 0 and d._enchantment_count(3, "LFGR") == 0 \
				and int(d.creatures[3].power) == int(bare_bat.power) and int(d.creatures[3].toughness) == int(bare_bat.toughness))
		# #268: the second game's Ash Storm is removed by Purify like any hero enchantment.
		_fixture("purify removes ash storm", {"heroes": [{"health": 20, "mana": 20, "hand": ["PRFY"], "enchantments": ["ASST"]}, {"health": 20, "mana": 0}], "creatures": []},
			[["do", {"kind": "cast", "card": "PRFY", "target": 0, "grave": 1}]],
			func(d: ELDuel) -> bool: return d.global_enchantment_count("ASST") == 0)
	# #268: Cleanse removes the second game's Ash Storm; the first game's stays (the original).
	_fixture("cleanse and ash storm", {"heroes": [{"health": 20, "mana": 20, "hand": ["ASST", "CLSN"]}, {"health": 20, "mana": 0}], "creatures": []},
		[["cast", 0], ["cast", 1]], func(d: ELDuel) -> bool: return d.global_enchantment_count("ASST") == (1 if game == "el1" else 0))
	if game == "el2":
		# #281: the second game's sweeping rest and rally pass over a creature in the Colourless Plane (a
		# pale creature that has not manifested), Ice Storm as well as Glade; a manifested one is reached.
		var planar := func(d: ELDuel) -> void: d.creatures[3].plane = true
		for pair: Array in [["ICST", "ice storm"], ["GLDT", "glade"]]:
			_fixture("%s spares the plane" % pair[1], {"heroes": [{"health": 20, "mana": 20, "hand": [pair[0]]}, {"health": 20, "mana": 0}], "after": planar,
				"creatures": [{"card": "TIWR", "owner": 1}, {"card": "OUD3", "owner": 1}]}, [["cast", 0]],
				func(d: ELDuel) -> bool: return bool(d.creatures[2].resting) and not bool(d.creatures[3].resting) and d.in_plane(3))
			_fixture("%s reaches a manifested pale creature" % pair[1], {"heroes": [{"health": 20, "mana": 20, "hand": [pair[0]]}, {"health": 20, "mana": 0}],
				"creatures": [{"card": "TIWR", "owner": 1}, {"card": "OUD3", "owner": 1}]}, [["cast", 0]],
				func(d: ELDuel) -> bool: return bool(d.creatures[2].resting) and bool(d.creatures[3].resting))
		_fixture("rally passes over the plane", {"heroes": [{"health": 20, "mana": 20, "hand": ["ENAL"]}, {"health": 20, "mana": 0}], "after": planar,
			"creatures": [{"card": "TIWR", "owner": 0, "resting": true}, {"card": "OUD3", "owner": 0, "resting": true}]}, [["cast", 0]],
			func(d: ELDuel) -> bool: return not bool(d.creatures[2].resting) and bool(d.creatures[3].resting))
		# Weaving gives its hero the enchantment's card by name, to be laid
		# again: the other creature's Energy Barrier on the weaver's own hero.
		_fixture("weaving gives a card to cast", {"puzzle": "el2_tactical_v2_curiosity_glass"},
			[["do", {"choice": 2, "id": 2, "key": "weave", "kind": "ability", "target": 3}], ["back", 0, 2, 0]],
			func(d: ELDuel) -> bool: return d._enchantment_count(0, "ENBR") == 1 and d.heroes[0].hand.size() == 2)
	_specs()
	_specs_cast()
	_swapped()
	# The Wall of Unreality's phantasm may be bought again: two uses, +4.
	_fixture("phantasm twice", {"heroes": [{"health": 20, "mana": 10}, {"health": 20, "mana": 0}], "creatures": [{"card": "PHWL", "owner": 0}]},
		[["use", 0, "phantasm"], ["use", 0, "phantasm"]], func(d: ELDuel) -> bool: return int(d.creatures[2].power) == int(Fixtures.build(profile, {"creatures": [{"card": "PHWL", "owner": 0}]}).creatures[2].power) + 4)

## What a delusion does to gains that come and go while it is worn, and an
## enchantment on a hero that was laid before the position and ends in it.
func _swapped() -> void:
	var spells: Dictionary = profile.table("CombatSpells")
	var beasts: Dictionary = profile.table("CombatCreatures")
	var fresh := func(d: ELDuel) -> void:
		for c: Dictionary in d.creatures.values(): d._refresh_stats(c)
	var rich := [{"health": 20, "mana": 20}, {"health": 20, "mana": 0}]
	if spells.has("DELS") and beasts.has("KBWR"):
		# The other kobold's gift of power shows as health; it goes with the kobold.
		_fixture("delusion: a leader's gift lost", {"heroes": rich, "after": fresh,
			"creatures": [{"card": "KBWR", "owner": 0, "enchantments": ["DELS"]}, {"card": "KBWR", "owner": 1}, {"card": "STRT", "owner": 0}]},
			[["attack", 2], ["end"], ["block", 1, 2], ["end"]],
			func(d: ELDuel) -> bool: return not d.creatures.has(3) and int(d.creatures[2].power) == 1 and int(d.creatures[2].toughness) == 2)
		if spells.has("STWO"):
			_fixture("delusion: an army's gift of power", {"heroes": [{"health": 20, "mana": 20, "hand": ["STWO"]}, {"health": 20, "mana": 0}], "after": fresh,
				"creatures": [{"card": "KBWR", "owner": 0, "enchantments": ["DELS"]}]}, [["cast", 0]],
				func(d: ELDuel) -> bool: return int(d.creatures[2].power) == 1 and int(d.creatures[2].toughness) == 4)
		if spells.has("BLSS"):
			_fixture("delusion: a blessing", {"heroes": [{"health": 20, "mana": 20, "hand": ["BLSS"]}, {"health": 20, "mana": 0}], "after": fresh,
				"creatures": [{"card": "KBWR", "owner": 0, "enchantments": ["DELS"]}]}, [["cast", 0, 2], ["end"], ["end"]],
				func(d: ELDuel) -> bool: return int(d.creatures[2].power) == 1 and int(d.creatures[2].toughness) == 2)
	if profile.id == "el2" and beasts.has("OUS1") and spells.has("STWO") and beasts.has("GROG"):
		# What stands on its hero covers a pale creature no longer once a
		# blow has sent it into the plane.
		_fixture("a pale creature dissipates from under its army's gift", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0, "enchantments": ["STWO"]}],
			"after": fresh, "creatures": [{"card": "GROG", "owner": 0}, {"card": "OUS1", "owner": 1}]}, [["attack", 0], ["end"], ["block", 1, 0], ["end"]],
			func(d: ELDuel) -> bool: return d.creatures.has(3) and d.in_plane(3) and int(d.creatures[3].power) == int(beasts.OUS1.Power))
	if spells.has("FURY"):
		# The artificer's mastery: a thing with one charge left works twice.
		var made := ELDuel.artifact_entry(profile, {"name": "made", "custom": {"elk_name": "", "spell": "FURY", "first": 0, "gap": 0, "max": 3}})
		var wait := 0
		# The first game has only the things of its table: the one aimed at
		# nothing that works again soonest.
		if made.is_empty():
			var probe := Fixtures.build(profile, {})
			for name: String in profile.table("Artefacts"):
				var entry := ELDuel.artifact_entry(profile, {"name": name})
				if entry.is_empty() or String(probe.artifact_rule(entry).get("target", "none")) != "none": continue
				# (And that works in a turn of its hero's own.)
				var trial := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 20}, {"health": 20, "mana": 0}]})
				var held := entry.duplicate(true)
				held.charges = 1
				held.ready_round = 0
				trial.heroes[0].artifacts = [held]
				trial.heroes[0].artifact_uses = 0
				if not trial.artifact_error(0, 0).is_empty(): continue
				if made.is_empty() or probe._artifact_gap(entry) < wait:
					made = entry
					wait = probe._artifact_gap(entry)
		var carry := func(d: ELDuel) -> void:
			var thing := made.duplicate(true)
			if thing.is_empty(): return
			thing.charges = 1
			thing.ready_round = 0
			d.heroes[0].artifacts = [thing]
			d.heroes[0].artifact_uses = 0
			# (Skilled enough to use two things in a turn.)
			d.heroes[0].skills = {"ARTF": 0}
		var work := {"kind": "ability", "id": 0, "key": "artifact:0"}
		_spec("ARTF", 0, "spares the charge", {"heroes": [{"health": 20, "mana": 20}, {"health": 20, "mana": 0}], "after": carry,
			"creatures": [{"card": "STRT", "owner": 1, "resting": true}]}, [["do", work]] + range(2 * wait).map(func(_i: int) -> Array: return ["end"]) + [["do", work]],
			func(d: ELDuel) -> bool: return int(d.heroes[0].artifacts[0].charges) == 1)
	if spells.has("CURS") and beasts.has("WLBR") and beasts.has("KBWR"):
		# A curse takes the creature cards from the near end of the row.
		_fixture("a curse takes the first creature cards of the row", {"heroes": [{"health": 20, "mana": 20, "hand": ["CURS"]},
			{"health": 20, "mana": 0, "hand": ["STRT", "MGHT", "KBWR", "GROG", "WLBR"]}], "creatures": [{"card": "STRT", "owner": 0}]}, [["cast", 0, 1]],
			func(d: ELDuel) -> bool: return d.heroes[1].hand == ["MGHT", "WLBR"])
	if profile.id == "el2" and beasts.has("GROG"):
		# A battle script that shapes its own hero's creatures as they are
		# summoned: the model is told what it gives each kind.
		ELBattleScripts.fixtures[ELBattleScripts.chunk_path("rules_shape")] = ("function CHook_OnLogicSummon(side, card, id)\n  if side == exMe then\n" \
			+ "    ExSetNewCreatureBaseStat(0, ExGetNewCreatureBaseStat(0) + 2)\n    ExSetNewCreatureBaseStat(1, ExGetNewCreatureBaseStat(1) + 1)\n  end\nend\n").to_utf8_buffer()
		ELBattleScripts.fixtures[ELBattleScripts.chunk_path("rules_count")] = "counter = 0\nfunction CHook_OnLogicSummon(side, card, id)\n  counter = counter + 1\n  ExSetNewCreatureBaseStat(0, counter)\nend\n".to_utf8_buffer()
		var scripted := func(name: String) -> Callable:
			return func(d: ELDuel) -> void:
				d.scripts = ELBattleScripts.new(d)
				d.scripts.load_all([{"name": name, "side": 0}])
				d.scripts.in_combat = true
		var summons := {"heroes": [{"health": 20, "mana": 20, "hand": ["GROG"]}, {"health": 20, "mana": 20, "hand": ["GROG"]}], "creatures": [{"card": "STRT", "owner": 1}]}
		var mine := summons.duplicate(true)
		mine.after = scripted.call("rules_shape")
		_fixture("a battle script shapes its hero's summons", mine, [["cast", 0]],
			func(d: ELDuel) -> bool: return int(d.creatures[3].power) == int(beasts.GROG.Power) + 2 and int(d.creatures[3].toughness) == int(beasts.GROG.Toughness) + 1)
		var theirs := summons.duplicate(true)
		theirs.after = scripted.call("rules_shape")
		theirs.attacker = 1
		_fixture("a battle script leaves the other hero's summons alone", theirs, [["cast", 0]],
			func(d: ELDuel) -> bool: return int(d.creatures[3].power) == int(beasts.GROG.Power))
		# The game's own battlegrounds that shape a summons (where its files
		# have them): the aviaks' place makes its hero's aviaks stronger,
		# restless and bound to attack; the gravity anomaly grounds a flyer.
		if beasts.has("AVAS") and not profile.script_bytes("AviakPlace").is_empty() and not profile.script_bytes("GravityAnomaly").is_empty():
			var flyer := {"heroes": [{"health": 20, "mana": 20, "hand": ["AVAS"]}, {"health": 20, "mana": 20}], "creatures": [{"card": "STRT", "owner": 1}]}
			var place := flyer.duplicate(true)
			place.after = scripted.call("AviakPlace")
			_fixture("the aviaks' place: stronger, and it must attack", place, [["cast", 0], ["end"], ["end"], ["end"], ["end"]],
				func(d: ELDuel) -> bool: return d.has_flag(3, "Berserk") and d.has_flag(3, "Restless") and int(d.heroes[1].health) == 20 - int(beasts.AVAS.Power) - 2)
			var anomaly := flyer.duplicate(true)
			anomaly.after = scripted.call("GravityAnomaly")
			_fixture("the gravity anomaly grounds a flyer", anomaly, [["cast", 0], ["end"], ["end"]],
				func(d: ELDuel) -> bool: return not d.has_flag(3, "Fly") and int(d.creatures[3].power) == int(beasts.AVAS.Power) - 1)
		# One that counts its summons is past what the model holds: the
		# position is told crowded, by name.
		var counted := Fixtures.build(profile, summons)
		cases += 1
		if counted == null: _missing("a counting battle script: the position does not restore")
		else:
			(scripted.call("rules_count") as Callable).call(counted)
			ELCombatBrain.fight(_context(0), counted, 4, [])
			if ELCombatBrain.last_crowding.has("scripts"): print("SAME parity a counting battle script is told as left out")
			else:
				differed += 1
				print("DIFF parity a counting battle script is told as left out: %s" % str(ELCombatBrain.last_crowding))
		ELBattleScripts.fixtures.clear()
	if spells.has("FURY") and beasts.has("GROG"):
		# Laid in its hero's turn before: the other hero's creatures must
		# attack this turn, and need not the next.
		var power := int(beasts.GROG.Power)
		_fixture("fury laid before ends with the turn", {"attacker": 1, "heroes": [{"health": 30, "mana": 0, "enchantments": ["FURY"]}, {"health": 20, "mana": 0}],
			"after": fresh, "creatures": [{"card": "GROG", "owner": 1}]}, [["end"], ["end"], ["end"], ["end"]],
			func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 30 - power and d.attacker == 0)

## A creature of a fixture, with nothing of its card's own but its race.
func _cr(card: String, owner: int, power: int, toughness: int, flags: Array = [], worn: Array = []) -> Dictionary:
	return {"card": card, "owner": owner, "power": power, "toughness": toughness, "flags": flags, "enchantments": worn}

## One specialisation at work: the hero `side` holds `code` as surely as a
## hero can (level 20 and all the luck there is), and both sets of rules
## count on what is to be expected of it.
func _spec(code: String, side: int, name: String, spec: Dictionary, steps: Array, expect: Callable, level := 20, luck := 3) -> void:
	if not profile.table("HeroesSpecs").has(code): return
	for c: Dictionary in spec.get("creatures", []):
		if not profile.table("CombatCreatures").has(String(c.card)):
			_missing("%s %s: no card %s" % [code, name, String(c.card)])
			return
	for hero: Dictionary in spec.heroes:
		for card: String in hero.get("hand", []) + hero.get("enchantments", []):
			if not profile.table("CombatSpells").has(card):
				_missing("%s %s: no card %s" % [code, name, card])
				return
	var told := spec.duplicate(true)
	told.fair = true
	told.heroes[side].spec = code
	told.heroes[side].spec_level = level
	told.heroes[side].luck = luck
	_fixture("%s %s" % [code, name], told, steps, expect)

## The heroes' specialisations, each in the smallest position that shows it.
func _specs() -> void:
	var fight := [["attack", 0], ["end"], ["end"]]
	var blocked := [["attack", 0], ["end"], ["block", 1, 0], ["end"]]
	var plain := func(a: int, b: int) -> Array: return [{"health": a, "mana": 0, "maximum": 20}, {"health": b, "mana": 0, "maximum": 20}]
	# The masteries that double a blow.
	for pair: Array in [["RKBC", "KBEL"], ["UAVC", "AVEL"]]:
		_spec(pair[0], 0, "doubles an attacker's blow", {"heroes": plain.call(20, 20), "creatures": [_cr(pair[1], 0, 3, 2)]}, fight,
			func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 14)
		_spec(pair[0], 1, "doubles a blocker's blow", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 2, 5), _cr(pair[1], 1, 3, 9)]}, blocked,
			func(d: ELDuel) -> bool: return not d.creatures.has(2))
		# At odds of one in six to one in two, one blow in three is doubled.
		var level := 0
		for l in range(1, 21):
			var p := ELSpecs.chance(profile, String(pair[0]), l)
			if p >= 1.0 / 6.0 and p < 0.5: level = l
		if level > 0:
			_spec(pair[0], 0, "doubles one blow in three at level %d" % level, {"heroes": plain.call(20, 20),
				"creatures": [_cr(pair[1], 0, 3, 2), _cr(pair[1], 0, 3, 2), _cr(pair[1], 0, 3, 2)]},
				[["attack", 0], ["attack", 1], ["attack", 2], ["end"], ["end"]], func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 8, level, 0)
		else: _missing("%s: no level gives odds between one in six and one in two" % String(pair[0]))
	# A beholder's gaze, attacking and blocking.
	_spec("GBHD", 0, "destroys the blocker and reaches the hero", {"heroes": plain.call(20, 20), "creatures": [_cr("BEHD", 0, 3, 3), _cr("GROG", 1, 1, 9)]}, blocked,
		func(d: ELDuel) -> bool: return not d.creatures.has(3) and int(d.heroes[1].health) == 17)
	_spec("GBHD", 1, "destroys the attacker", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 3, 9), _cr("BEHD", 1, 1, 3)]}, blocked,
		func(d: ELDuel) -> bool: return not d.creatures.has(2) and d.creatures.has(3))
	# The walls that doom what they block.
	_spec("RWSW", 1, "dooms a ground attacker", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 1, 9), {"card": "WLBR", "owner": 1}]}, blocked,
		func(d: ELDuel) -> bool: return not d.creatures.has(2))
	_spec("UWAW", 1, "dooms a flying attacker", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 1, 9, ["Fly"]), {"card": "WLAR", "owner": 1}]}, blocked,
		func(d: ELDuel) -> bool: return not d.creatures.has(2))
	# A hornet takes the first strike from its blocker, and wins one when it blocks.
	_spec("GHRI", 0, "takes the blocker's first strike", {"heroes": plain.call(20, 20), "creatures": [_cr("MYHO", 0, 3, 1), _cr("GROG", 1, 3, 3, ["FS"])]}, blocked,
		func(d: ELDuel) -> bool: return d.creatures.has(2) and not d.creatures.has(3))
	_spec("GHRI", 1, "strikes first as a blocker", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 3, 3), _cr("MYHO", 1, 3, 1)]}, blocked,
		func(d: ELDuel) -> bool: return not d.creatures.has(2) and d.creatures.has(3))
	# A shadow wall lays its attacker low.
	_spec("BWIT", 1, "holds the attacker down", {"heroes": plain.call(20, 20), "creatures": [{"card": "TIWR", "owner": 0}, {"card": "WLIL", "owner": 1}]},
		blocked + [["end"], ["end"]], func(d: ELDuel) -> bool: return d.creatures.has(2) and bool(d.creatures[2].resting))
	# Cutters and gibberlings stay ready.
	for pair: Array in [["BCTR", "RZMN"], ["UOCR", "GBBR"]]:
		_spec(pair[0], 0, "leaves the attacker ready", {"heroes": plain.call(20, 20), "creatures": [_cr(pair[1], 0, 2, 2)]}, fight,
			func(d: ELDuel) -> bool: return not bool(d.creatures[2].resting) and int(d.heroes[1].health) == 18)
	# Lamias and orcs rob a card.
	for pair: Array in [["UMTD", "LMMN"], ["RORT", "ORWR"]]:
		_spec(pair[0], 0, "robs a card", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0, "hand": ["GROG", "GROG"]}], "creatures": [_cr(pair[1], 0, 2, 2)]},
			fight, func(d: ELDuel) -> bool: return d.heroes[1].hand.size() == 1)
	# A snake envenoms the hero, and the venom bites as that hero's turn ends.
	_spec("GSNV", 0, "envenoms the hero", {"heroes": plain.call(20, 20), "creatures": [_cr("LASN", 0, 2, 2)]}, fight + [["end"]],
		func(d: ELDuel) -> bool: return d._enchantment_count(1, "ENVM") == 1 and int(d.heroes[1].health) == 16)
	# Fighters, treants and bats heal their hero.
	for pair: Array in [["BFGL", "MLFI"], ["GTRL", "TNSA"], ["RBTD", "BATT"]]:
		_spec(pair[0], 0, "heals its hero", {"heroes": plain.call(10, 20), "creatures": [_cr(pair[1], 0, 3, 3)]}, fight,
			func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 13)
	# A pteros strips what the other hero laid on its own.
	_spec("BPTD", 0, "strips a creature", {"heroes": plain.call(20, 20), "creatures": [_cr("PTRS", 0, 1, 9), {"card": "TIWK", "owner": 1, "enchantments": ["STRG"]}]}, blocked,
		func(d: ELDuel) -> bool: return d.creatures.has(3) and (d.creatures[3].enchantments as Array).is_empty())
	_spec("BPTD", 0, "strips a hero", {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0, "enchantments": ["STWO"]}], "creatures": [{"card": "PTRS", "owner": 0}]},
		fight, func(d: ELDuel) -> bool: return d._enchantment_count(1, "STWO") == 0 and int(d.heroes[1].health) < 20)
	# Rats and fingi regenerate for nothing.
	for pair: Array in [["RRTR", "STRT"], ["GFNR", "SPFG"]]:
		_spec(pair[0], 1, "regenerates for nothing", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 3, 9), _cr(pair[1], 1, 1, 1)]}, blocked,
			func(d: ELDuel) -> bool: return d.creatures.has(3))
	# The skins: a blow, and a spell, turned aside whole.
	for code: String in ["IRSK", "DRSK", "DRSL"]:
		_spec(code, 1, "turns a blow aside", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 3, 3)]}, fight,
			func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 20)
	for code: String in ["ATMF", "DRSK", "DRSL"]:
		_spec(code, 1, "turns a spell aside", {"heroes": [{"health": 20, "mana": 10, "hand": ["ZAPP"]}, {"health": 20, "mana": 0}], "creatures": []}, [["cast", 0, 1]],
			func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 20)
	# The backlashes: one to the other hero and to each of its creatures.
	_spec("FRBD", 1, "answers a blow", {"heroes": plain.call(20, 20), "creatures": [_cr("GROG", 0, 3, 1), _cr("GROG", 0, 1, 2)]}, fight,
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 19 and int(d.heroes[1].health) == 17 and not d.creatures.has(2) and d.creatures.has(3))
	_spec("WRBD", 1, "answers a spell", {"heroes": [{"health": 20, "mana": 10, "hand": ["ZAPP"]}, {"health": 20, "mana": 0}], "creatures": [_cr("GROG", 0, 3, 1)]}, [["cast", 0, 1]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 19 and int(d.heroes[1].health) == 19 and not d.creatures.has(2))
	# A revival: the deadly blow halves the hero's health and fills it.
	_spec("RVVE", 1, "comes back from a deadly blow", {"heroes": plain.call(20, 2), "creatures": [_cr("GROG", 0, 3, 3)]}, fight,
		func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 10 and d.phase != ELDuel.Phase.FINISHED)

## The specialisations of spells, of abilities and of the turn.
func _specs_cast() -> void:
	var game := profile.id
	var zap := func(extra: Dictionary = {}) -> Dictionary:
		var hero := {"health": 20, "mana": 10, "maximum": 20, "hand": ["ZAPP"]}
		hero.merge(extra, true)
		return hero
	var bare := {"health": 20, "mana": 0, "maximum": 20}
	# A book for the hero `side` once the position stands: its cards, the uses
	# each has left, and the place in it of each card of the hand.
	var book := func(d: ELDuel, side: int, deck: Array, uses: Array, pages: Array) -> void:
		d.heroes[side].deck = deck.duplicate()
		d.heroes[side].spell_uses = uses.duplicate()
		d.heroes[side].hand_slots = pages.duplicate()
	# The thorns' mastery spares the ether a spell costs.
	_spec("GMTM", 0, "spares the thorns", {"heroes": [zap.call(), {"health": 20, "mana": 0, "enchantments": ["MNTH"]}], "creatures": []}, [["cast", 0, 1]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 20 and int(d.heroes[1].health) == 19)
	# The book's: a use spared, a card kept, a cast for nothing.
	_spec("RSFN", 0, "spares the use", {"heroes": [zap.call(), bare], "creatures": [], "after": book.bind(0, ["ZAPP"], [2], [0])}, [["cast", 0, 1]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].spell_uses[0]) == 2)
	_spec("STHN", 0, "keeps the second card in the hand", {"heroes": [zap.call({"mana": 20, "hand": ["ZAPP", "ZAPP"]}), bare],
		"creatures": [], "after": book.bind(0, ["ZAPP"], [9], [0, 0])}, [["cast", 0, 1], ["cast", 1, 1]], func(d: ELDuel) -> bool: return d.heroes[0].hand.size() == 1 and int(d.heroes[1].health) == 18)
	_spec("STHN", 0, "keeps no card past its uses", {"heroes": [zap.call({"mana": 20, "hand": ["ZAPP", "ZAPP"]}), bare],
		"creatures": [], "after": book.bind(0, ["ZAPP"], [2], [0, 0])}, [["cast", 0, 1], ["cast", 1, 1]], func(d: ELDuel) -> bool: return d.heroes[0].hand.is_empty())
	_spec("MNCH", 0, "casts for nothing", {"heroes": [zap.call(), bare], "creatures": []}, [["cast", 0, 1]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].mana) == 10 and int(d.heroes[1].health) == 19)
	# A second creature of the card.
	for pair: Array in [["BVLD", "SMVL"], ["GHLD", "SWHL"]]:
		_spec(pair[0], 0, "summons a second", {"heroes": [zap.call({"mana": 20, "hand": [pair[1]]}), bare], "creatures": []}, [["cast", 0]],
			func(d: ELDuel) -> bool: return d.army(0).size() == 2)
	# The elixir's card, with books that deal: the second cast draws.
	_spec("CEXC", 0, "draws a card", {"fixed": false, "rng": 77, "heroes": [zap.call({"mana": 20, "hand": ["ZAPP", "ZAPP"]}), bare],
		"creatures": [], "after": book.bind(0, ["GROG", "ZAPP"], [9, 9], [1, 1])}, [["cast", 0, 1], ["cast", 1, 1]],
		func(d: ELDuel) -> bool: return d.heroes[0].hand.size() == 1)
	# The storm's mastery blesses the caster's own where the storm would strike.
	_spec("RLSS", 0, "blesses its own in the storm", {"heroes": [zap.call({"mana": 20, "hand": ["LGST"]}), bare], "creatures": [{"card": "STRT", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["cast", 0]], func(d: ELDuel) -> bool: return d.creatures.has(2) and int(d.creatures[2].power) == 4 and not d.creatures.has(3))
	_spec("RLSS", 0, "and the blessing ends", {"heroes": [zap.call({"mana": 20, "hand": ["LGST"]}), bare], "creatures": [{"card": "STRT", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["cast", 0], ["end"], ["end"]], func(d: ELDuel) -> bool: return d.creatures.has(2) and int(d.creatures[2].power) == 1)
	# Three for each card wiped.
	_spec("BMWM", 0, "hurts for each card wiped", {"heroes": [zap.call({"mana": 20, "hand": ["MDWP"]}), {"health": 20, "mana": 0, "hand": ["GROG", "GROG"]}], "creatures": []},
		[["cast", 0, 1]], func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 14 and d.heroes[1].hand.is_empty())
	# A resistance to the burn, of a spell and of the enchantment.
	_spec("RMBD", 1, "spares the burnt ether", {"heroes": [zap.call({"mana": 20, "hand": ["BRRL"]}), {"health": 20, "mana": 5}], "creatures": []}, [["cast", 0, 1]],
		func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 20 and int(d.heroes[1].mana) == 0)
	_spec("RMBD", 0, "spares the ether burn", {"heroes": [{"health": 20, "mana": 5, "enchantments": ["MNBN"]}, bare], "creatures": []}, [["end"]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 20 and d.attacker == 1)
	# Nothing regenerates from the hunger.
	_spec("UHGW", 0, "starves past regeneration", {"heroes": [zap.call({"hand": ["HUNG"]}), {"health": 20, "mana": 5}], "creatures": [_cr("GROG", 1, 2, 2, ["Regen(1)"])]},
		[["cast", 0, 2]], func(d: ELDuel) -> bool: return not d.creatures.has(2))
	# The purification takes everything off.
	_spec("BPRC", 0, "purifies the creature whole", {"heroes": [zap.call({"mana": 20, "hand": ["PRFY"]}), bare], "creatures": [{"card": "STRT", "owner": 1, "enchantments": ["STRG", "STRG"]}]},
		[["do", {"kind": "cast", "card": "PRFY", "target": 2, "grave": 1}]], func(d: ELDuel) -> bool: return d.creatures.has(2) and (d.creatures[2].enchantments as Array).is_empty())
	# The cannibal keeps its meal.
	_spec("RPLO", 0, "spares the sacrifice", {"heroes": [zap.call({"hand": ["CNBL"]}), bare], "creatures": [{"card": "KBWR", "owner": 0}]}, [["cast", 0, 2]],
		func(d: ELDuel) -> bool: return d.creatures.has(2) and int(d.heroes[0].health) == 21)
	# Nature's friend, and the unsummoning's mastery, keep their hero's own.
	_spec("GFNS", 0, "spares its own from the fury", {"heroes": [zap.call({"mana": 30, "hand": ["FRNT"]}), bare], "creatures": [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["cast", 0]], func(d: ELDuel) -> bool: return d.creatures.has(2) and not d.creatures.has(3))
	_spec("UGUS", 0, "keeps its own in play", {"heroes": [zap.call({"mana": 30, "hand": ["GRUN"]}), bare], "creatures": [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["cast", 0]], func(d: ELDuel) -> bool: return d.creatures.has(2) and not d.creatures.has(3) and d.heroes[1].hand.size() == 1)
	# A mind shield.
	_spec("UMBD", 1, "shields the mind", {"heroes": [zap.call({"mana": 30, "hand": ["MDBL"]}), {"health": 20, "mana": 0, "hand": ["GROG", "GROG", "GROG", "GROG", "GROG", "GROG", "GROG"]}],
		"creatures": []}, [["cast", 0]], func(d: ELDuel) -> bool: return int(d.heroes[1].health) == 20)
	# The heroes' own abilities.
	_spec("RBNO", 0, "spares what burns out", {"heroes": [{"health": 20, "mana": 5, "enchantments": ["BROT"]}, bare], "creatures": [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["do", {"kind": "ability", "id": 0, "key": "burnout:1", "target": 2, "choice": 3}]], func(d: ELDuel) -> bool: return d.creatures.has(2) and not d.creatures.has(3))
	_spec("GSLO", 0, "spares what is locked", {"heroes": [{"health": 20, "mana": 5, "enchantments": ["SPLK"]}, bare], "creatures": [{"card": "KBWR", "owner": 0}]},
		[["do", {"kind": "ability", "id": 0, "key": "spirit_lock:1", "target": 2}]], func(d: ELDuel) -> bool: return d.creatures.has(2))
	_spec("BENG", 0, "leaves the energy unused", {"heroes": [{"health": 20, "mana": 5, "enchantments": ["ENRG"]}, bare], "creatures": [{"card": "KBWR", "owner": 0, "resting": true}]},
		[["do", {"kind": "ability", "id": 0, "key": "energize:1", "target": 2}]],
		func(d: ELDuel) -> bool: return not bool(d.creatures[2].resting) and not bool(d.heroes[0].enchantments[0].get("used", false)))
	_spec("BRST", 0, "leaves the repair unused", {"heroes": [{"health": 20, "mana": 5, "enchantments": ["RPST"], "grave": ["TIWR"]}, bare], "creatures": []},
		[["do", {"kind": "ability", "id": 0, "key": "repair:1", "target": 0, "choice": 0}]],
		func(d: ELDuel) -> bool: return d.heroes[0].hand == ["TIWR"] and not bool(d.heroes[0].enchantments[0].get("used", false)))
	# A fingus lives through its own spores.
	_spec("GFNR", 0, "lives through its spores", {"heroes": [bare, bare], "creatures": [{"card": "SPFG", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["do", {"kind": "ability", "id": 2, "key": "spores", "target": 3}]], func(d: ELDuel) -> bool: return d.creatures.has(2))
	# The first game's: an enchantment kept, and one that comes back as a card.
	_spec("MSEN", 1, "keeps its enchantment", {"heroes": [zap.call({"mana": 20, "hand": ["PRFY"]}), bare], "creatures": [{"card": "STRT", "owner": 1, "enchantments": ["STRG"]}]},
		[["do", {"kind": "cast", "card": "PRFY", "target": 2, "grave": 1}]], func(d: ELDuel) -> bool: return d._enchantment_count(2, "STRG") == 1)
	_spec("ETEN", 1, "takes its enchantment back", {"heroes": [zap.call({"mana": 20, "hand": ["PRFY"]}), bare], "creatures": [{"card": "STRT", "owner": 1, "enchantments": ["STRG"]}]},
		[["do", {"kind": "cast", "card": "PRFY", "target": 2, "grave": 1}]], func(d: ELDuel) -> bool: return d._enchantment_count(2, "STRG") == 0 and d.heroes[1].hand == ["STRG"])
	# The turn's: a parasite, the gas, a blessing kept, the tide, the flood, the smoke, the intuition.
	if not ELCatalog.PARASITES.is_empty():
		_spec("BMZP", 0, "spares the drain", {"heroes": [bare, bare], "creatures": [{"card": String(ELCatalog.PARASITES.keys()[0]), "owner": 0}]}, [["end"]],
			func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 20 and d.attacker == 1)
	_spec("BSGP", 0, "spares its side from the gas", {"heroes": [{"health": 20, "mana": 0, "enchantments": ["SFGS"]}, bare], "creatures": [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 1}]},
		[["end"]], func(d: ELDuel) -> bool: return d.creatures.has(2) and not d.creatures.has(3) and int(d.heroes[0].health) == 20 and int(d.heroes[1].health) == 18)
	_spec("GBLP", 0, "keeps a blessing a turn more", {"heroes": [bare, bare], "creatures": [{"card": "KBWR", "owner": 0, "enchantments": ["BLSS"]}]}, [["end"], ["end"]],
		func(d: ELDuel) -> bool: return d._enchantment_count(2, "BLSS") == 1 and d.attacker == 0)
	_spec("ETTI", 1, "brings a card back", {"heroes": [bare, {"health": 20, "mana": 0, "grave": ["TIWR"]}], "creatures": []}, [["end"]],
		func(d: ELDuel) -> bool: return d.heroes[1].hand == ["TIWR"] and d.heroes[1].grave.is_empty())
	_spec("UFLP", 1, "recovers through the flood", {"heroes": [{"health": 20, "mana": 0, "enchantments": ["FLOD"]}, bare], "creatures": [{"card": "STRT", "owner": 1, "resting": true}]}, [["end"]],
		func(d: ELDuel) -> bool: return not bool(d.creatures[2].resting))
	_spec("RSMP", 1, "recovers through the smoke", {"heroes": [{"health": 20, "mana": 0, "enchantments": ["SMOK"]}, bare], "creatures": [{"card": "STRT", "owner": 1, "resting": true}]}, [["end"]],
		func(d: ELDuel) -> bool: return not bool(d.creatures[2].resting))
	_spec("QIHN", 1, "draws one more", {"fixed": false, "rng": 78, "heroes": [bare, bare], "creatures": [],
		"after": book.bind(1, ["GROG", "KBWR"], [9, 9], [])}, [["end"]],
		func(d: ELDuel) -> bool: return d.heroes[1].hand.size() == 2)
	# What a death gives: the web's two, and the link's power.
	_spec("GSWS", 0, "heals two by the web", {"heroes": [zap.call({"enchantments": ["SPWB"]}), bare], "creatures": [{"card": "STRT", "owner": 1}]}, [["cast", 0, 2]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 22)
	_spec("UWLS", 0, "heals by the power too", {"heroes": [zap.call({"hand": ["CLIG"]}), bare], "creatures": [{"card": "KBWR", "owner": 0, "enchantments": ["WTLK"]}]}, [["cast", 0, 2]],
		func(d: ELDuel) -> bool: return int(d.heroes[0].health) == 22)

## The lowest hero level at which a mastery works most surely.
func _surest_level(code: String) -> int:
	var best := 1
	for level in range(1, 21):
		if ELSpecs.chance(profile, code, level) > ELSpecs.chance(profile, code, best): best = level
	return best

## Which card a random discard takes is the duel's chance, which the model is
## not told; it must not take it by the heroes' health or ether, or a line
## could choose the discard by the damage it deals first. The same hand hit
## by the same robber, the hero at 20 health or at 19, must lose the same card
## in the model.
func _discard_pick() -> void:
	var probe := Fixtures.build(profile, {})
	var cards: Array = []
	for card: String in profile.table("CombatSpells"):
		if cards.size() >= 3: break
		if String(profile.table("CombatSpells")[card].get("Class", "")) == "Creature" or card in ELCatalog.DISCARD_RETORTS: continue
		if probe == null or ELCombatBrain._card(_context(0), probe, card).is_empty(): continue
		cards.append(card)
	var kept: Array = []
	for health: int in [20, 19]:
		var spec := {"heroes": [{"health": 20, "mana": 0}, {"health": health, "mana": 0, "hand": cards}],
			"creatures": [{"card": "GROG", "owner": 0, "power": 2, "toughness": 2, "flags": ["Discard(1)"]}]}
		var start := Fixtures.build(profile, spec)
		if start == null or cards.size() < 3:
			_missing("random discard pick: the position does not restore")
			return
		fights += 1
		cases += 1
		var model := ELCombatBrain.fight(_context(0), start, 4, [[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
		var named: Array = (model.get("named", [[], []]) as Array)[1]
		named.sort()
		kept.append(named)
	if kept[0].size() != 2 or kept[0] != kept[1]:
		_missing("random discard pick: the model keeps %s at 20 health and %s at 19" % [_card_names(kept[0]), _card_names(kept[1])])
	else: print("SAME parity random discard pick")

## A fight that kills the other hero wins the duel, though the turn's end
## would then have drained the attacker's own last health too: the model's
## weighing of a whole defence once played the turn's end regardless and
## called it a draw. The attacker's parasite is sent against a hero with no
## blocker and one health; the engine, reading the defence for the attacker,
## must call it won.
func _won_in_the_fight() -> void:
	var card := ""
	for name: String in ELCatalog.PARASITES:
		if profile.table("CombatCreatures").has(name) and int(ELCatalog.PARASITES[name]) > 0:
			card = name
			break
	if card.is_empty():
		_missing("won in the fight: no parasite in this game")
		return
	var drain := int(ELCatalog.PARASITES[card])
	var duel := Fixtures.build(profile, {"phase": "defence", "attacks": [2], "heroes": [{"health": drain, "mana": 0}, {"health": 1, "mana": 0}],
		"creatures": [{"card": card, "owner": 0, "flags": []}]})
	if duel == null:
		_missing("won in the fight: the position does not restore")
		return
	var real := duel.search_copy()
	real.end_phase()
	cases += 1
	fights += 1
	var answer := ELCombatBrain.ask(_context(0), duel, 1, 100000, false)
	if real.phase != ELDuel.Phase.FINISHED or real.winner != 0: _missing("won in the fight: the game itself does not come out as expected")
	elif int(answer.get("status", 0)) != 1: _missing("won in the fight: the engine reads the defence as %s, not a win" % str(answer))
	else: print("SAME parity won in the fight %s" % str(answer))

## Two blockers alike but for their wounds are not one choice: the hero at
## one health lives only if the whole 0/4 takes the trampling 3 and the
## wounded one (one health left) the trampling 1. The engine once took the
## two for interchangeable and lost the only safe defence.
func _wounded_blockers() -> void:
	var duel := Fixtures.build(profile, {"phase": "defence", "attacks": [2, 3], "heroes": [{"health": 20, "mana": 0}, {"health": 1, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 1, "toughness": 4, "flags": ["Trample"]},
			{"card": "GROG", "owner": 0, "power": 3, "toughness": 4, "flags": ["Trample"]},
			{"card": "GROG", "owner": 1, "power": 0, "toughness": 4, "flags": []},
			{"card": "GROG", "owner": 1, "power": 0, "toughness": 4, "flags": [], "damage": 3}]})
	if duel == null:
		_missing("wounded blockers: the position does not restore")
		return
	cases += 1
	fights += 1
	var answer := ELCombatBrain.ask(_context(1), duel, 1, 100000, false)
	if int(answer.get("status", -1)) == -1: _missing("wounded blockers: the engine finds no defence (%s)" % str(answer))
	else: print("SAME parity wounded blockers")

## A block already set may be set again elsewhere: the hero at five health,
## its 1/1 set against the other 1/1 while a 5/5 attacks, lives only by
## moving the block onto the 5/5. The engine once never went back on a block.
## The rules side too: setting a blocker against the attacker it blocks takes
## the block back, against another moves it, in both sets of rules.
func _revised_block() -> void:
	var spec := {"phase": "defence", "attacks": [2, 3], "heroes": [{"health": 20, "mana": 0}, {"health": 5, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 1, "toughness": 1, "flags": []},
			{"card": "GROG", "owner": 0, "power": 5, "toughness": 5, "flags": []},
			{"card": "GROG", "owner": 1, "power": 1, "toughness": 1, "flags": []}]}
	var duel := Fixtures.build(profile, spec)
	if duel == null or not duel.assign_block(4, 2):
		_missing("revised block: the position does not restore")
		return
	cases += 1
	fights += 1
	var smart: Array[int] = [1]
	duel.smart_sides = smart
	var command := ELCombatSearch.think(duel.search_copy())
	if String(command.get("kind", "")) != "block" or int(command.get("id", -1)) != 4 or int(command.get("target", -1)) != 3:
		_missing("revised block: the engine plays %s, not the block of the 5/5" % str(command))
	else: print("SAME parity revised block")
	# Taken back, then set against the 5/5, by commands to both rules.
	var start := duel.search_copy()
	var before := _board(start)
	var played := duel.assign_block(4, 2) and not duel.blocks.has(4) and duel.assign_block(4, 3) and duel.end_phase()
	fights += 1
	var model := ELCombatBrain.fight(_context(1), start, 4, [[2, 2, 0, 0], [2, 2, 1, 0], [0, 0, 0, 0]])
	var trouble := _compare(duel, model, before, true) if not model.is_empty() else ["the model gave no answer"]
	if not played: trouble.append("the game refused the commands (%s)" % duel.error)
	if int(model.get("played", 0)) != 3: trouble.append("the model played %d of 3 commands" % int(model.get("played", 0)))
	if trouble.is_empty(): print("SAME parity block taken back and moved")
	else: _missing("block taken back and moved: " + " | ".join(trouble))

## An authored puzzle's position, as its runner sets it up (objective and all).
## A puzzle withdrawn from the packs keeps its position in tools/duel_rules_puzzles.
func _puzzle_position(id: String) -> ELDuel:
	var entries := ELPuzzles.list(profile.id)
	for at in entries.size():
		if String(entries[at].id) != id: continue
		var run := ELPuzzles.Run.new()
		if run.begin(profile, at): return run.duel
	var path := ProjectSettings.globalize_path("res://").path_join("../tools/duel_rules_puzzles/%s.json" % id).simplify_path()
	var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if kept is Dictionary:
		var run := ELPuzzles.Run.new()
		if run.begin_entry(profile, kept): return run.duel
	return null

func _missing(what: String) -> void:
	print("DIFF parity %s" % what)
	differed += 1

func _fixture(name: String, spec: Dictionary, steps: Array, expect: Callable) -> void:
	var duel := _puzzle_position(String(spec.puzzle)) if spec.has("puzzle") else Fixtures.build(profile, spec)
	var start := _puzzle_position(String(spec.puzzle)) if spec.has("puzzle") else Fixtures.build(profile, spec)
	if duel == null or start == null:
		_missing(name + ": the position does not restore")
		return
	cases += 1
	# Specialisations as a reading counts on them: what is to be expected of
	# each roll, with nothing drawn (the model is told no more than the odds).
	if spec.get("fair", false):
		duel.expected_specs = true
		duel.fair_specs = true
	# "after": what a fixture changes in the position once it stands.
	if spec.has("after"):
		(spec.after as Callable).call(duel)
		(spec.after as Callable).call(start)
	var before := _board(duel)
	var attacker := duel.attacker
	var ids: Array = duel.creatures.keys()
	var commands: Array = []
	for step: Array in steps:
		var done := false
		match String(step[0]):
			"cast":
				# Places as the model was told them; the game's hand closes up.
				var place := int(step[1])
				var earlier := 0
				for command: Array in commands:
					if int(command[0]) == 3 and int(command[1]) < place: earlier += 1
				# And what it is aimed at, by the game's id: a hero or a creature.
				var aim := -99
				if step.size() > 2: aim = -1 - int(step[2]) if int(step[2]) < 2 else ids.find(int(step[2]))
				done = duel.cast(place - earlier, int(step[2]) if step.size() > 2 else -1)
				commands.append([3, place, aim, 0])
			"back":
				# A card that came back into the hand in the middle of the line:
				# ["back", its place among those that came back, its place in
				# the game's hand now, what it is aimed at].
				var aim := -99
				if step.size() > 3: aim = -1 - int(step[3]) if int(step[3]) < 2 else ids.find(int(step[3]))
				done = duel.cast(int(step[2]), int(step[3]) if step.size() > 3 else -1)
				commands.append([3, ELCombatBrain.SLOTS + int(step[1]), aim, 0])
			"attack":
				done = duel.toggle_attack(int(ids[int(step[1])]))
				commands.append([1, int(step[1]), 0, 0])
			"block":
				done = duel.assign_block(int(ids[int(step[1])]), int(ids[int(step[2])]))
				commands.append([2, int(step[1]), int(step[2]), 0])
			"use":
				done = duel.use_ability(int(ids[int(step[1])]), String(step[2]))
				commands.append([7, int(step[1]), -99, 0])
			"end":
				done = duel.end_phase()
				commands.append([0, 0, 0, 0])
			"do":
				# Any other command, as a puzzle's solution writes it, in the
				# form the engine itself lists it (no card or creature may have
				# left before it, or the places it names have moved).
				var command := _reference_command(duel, step[1])
				var named: Array = []
				# (As its plain reading lists them, or else as a proof does.)
				for move: Array in _native_moves(duel, duel.active_side(), false) + _native_moves(duel, duel.active_side(), true):
					if _same_command(duel, ELCombatBrain._command_of(duel, duel.creatures.keys(), int(move[0]), int(move[1]), int(move[2]), int(move[3])), command):
						named = move
						break
				if named.is_empty():
					_missing("%s: the engine does not list %s at command %d (the game: %s)" % [name, str(step[1]), commands.size() + 1,
						"allows it" if ELCombatSearch.apply(duel, command) else duel.error])
					return
				done = ELCombatSearch.apply(duel, command)
				commands.append(named)
		if not done:
			_missing("%s: the game refused %s (%s)" % [name, str(step), duel.error])
			return
	fights += 1
	var model := ELCombatBrain.fight(_context(attacker), start, 4, commands)
	if model.is_empty():
		_missing(name + ": the model gave no answer")
		return
	var trouble := _compare(duel, model, before, true)
	if int(model.played) != commands.size(): trouble.append("the model played %d of %d commands" % [int(model.played), commands.size()])
	if not expect.call(duel): trouble.append("the game itself does not come out as expected")
	if trouble.is_empty():
		print("SAME parity %s" % name)
		return
	differed += 1
	print("DIFF parity %s: %s" % [name, " | ".join(trouble)])
	print("   " + before.text)

# --- The authored puzzles' reference solutions -------------------------------------

## --puzzles=1: each authored puzzle's reference line, a command at a time.
## Before each command the engine lists what it would weigh there (as its
## plain reading and as a proof), and the command must be among them; the
## model then plays its own copy of that command from the same position, and
## must leave what the game leaves.
func _puzzles() -> void:
	var entries := ELPuzzles.list(profile.id)
	# The lines go on past their authored end as the engine plays both sides,
	# so that what follows a refutation is held too.
	var onward := int(_arg("onward", "24"))
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_budget = int(_arg("budget", "100000"))
	var tally := {"actions": 0, "plain": 0, "proof": 0}
	for at in entries.size():
		var entry: Dictionary = entries[at]
		if not _arg("only", "").is_empty() and String(entry.id) != _arg("only", ""): continue
		var lines: Array = [["solution", entry.get("solution", [])]]
		for refutation: Dictionary in entry.get("refutations", []): lines.append(["refutation \"%s\"" % String(refutation.get("label", "")), refutation.get("commands", [])])
		for line: Array in lines: _puzzle_line(at, entry, String(line[0]), line[1], onward, tally)
	print("PUZZLES actions=%d missing plain=%d proof=%d" % [int(tally.actions), int(tally.plain), int(tally.proof)])

## One authored line of a puzzle and `onward` commands of the engine's after
## it. Only the authored commands must be in the engine's lists; every
## command, the engine's too, must leave the same position in both rules.
func _puzzle_line(at: int, entry: Dictionary, label: String, solution: Array, onward: int, tally: Dictionary) -> ELDuel:
	var run := ELPuzzles.Run.new()
	if not run.begin(profile, at):
		_missing("%s: the puzzle does not begin (%s)" % [entry.id, run.error])
		return null
	var duel: ELDuel = run.duel
	for step in solution.size() + onward:
		if duel.phase == ELDuel.Phase.FINISHED: break
		var authored := step < solution.size()
		var side := duel.active_side()
		var command := {}
		if authored: command = _reference_command(duel, solution[step])
		else:
			var smart: Array[int] = [side]
			duel.smart_sides = smart
			command = ELCombatSearch.think(duel.search_copy())
			if command.is_empty(): command = {"kind": "end_phase"}
		var said := "%s %s step %d%s (%s)" % [entry.id, label, step + 1, "" if authored else " (engine)", _said(duel, command)]
		var found: Array = []
		var lists := [_native_moves(duel, side, false), _native_moves(duel, side, true)]
		# A library that lists nothing (one built before it could) is still
		# held to the rules, by the command as the model would be told it.
		if (lists[0] as Array).is_empty() and (lists[1] as Array).is_empty():
			found = _native_command(duel, command)
			if not found.is_empty(): lists = [[found], [found]]
		for proof in 2:
			var hit: Array = []
			for move: Array in lists[proof]:
				# A command of its own kind (a whole attack) or one the game
				# cannot name reads as an end of the phase: only the end is one.
				if String(command.kind) == "end_phase" and int(move[0]) != 0: continue
				if _same_command(duel, ELCombatBrain._command_of(duel, duel.creatures.keys(), int(move[0]), int(move[1]), int(move[2]), int(move[3])), command):
					hit = move
					break
			# The plain reading leaves out casts that only spend their card;
			# a refutation may play one, so it must be in the proof's list,
			# and the solutions' commands in both.
			if hit.is_empty() and authored and (proof == 1 or label == "solution" or label.begins_with("(")):
				tally[("proof" if proof == 1 else "plain")] += 1
				_missing("%s: the engine's %s list does not hold it" % [said, "proof" if proof == 1 else "plain"])
			elif found.is_empty(): found = hit
		if authored: tally.actions += 1
		var before := _board(duel)
		var start := duel.search_copy()
		if not ELCombatSearch.apply(duel, command):
			if authored: _missing("%s: the game refused it (%s)" % [said, duel.error])
			break
		run.watch()
		if found.is_empty(): continue
		cases += 1
		fights += 1
		var model := ELCombatBrain.fight(_context(side), start, 4, [found])
		if model.is_empty():
			_missing(said + ": the model gave no answer")
			continue
		var trouble := _compare(duel, model, before, true)
		if int(model.played) != 1: trouble.append("the model turned the command down")
		var phase_now := 0 if duel.phase == ELDuel.Phase.ATTACK else 1
		if duel.phase != ELDuel.Phase.FINISHED and int(model.phase) != phase_now:
			trouble.append("the game stands in phase %d, the model in %d" % [phase_now, int(model.phase)])
		if trouble.is_empty():
			if verbose: print("SAME puzzle %s" % said)
			continue
		differed += 1
		print("DIFF puzzle %s: %s" % [said, " | ".join(trouble)])
		if verbose: print("   %s\n   the model played %s and leaves blocks %s, units %s, stats %s" % [before.text, str(found), str(model.blocks), str(model.units), str(model.get("stats", {}))])
		# What follows a parting is the parting's own doing.
		break
	return duel

## The model's own form of a plain command (an end, a creature sent or set
## to block, a card cast with no further choice); empty for the rest.
func _native_command(duel: ELDuel, command: Dictionary) -> Array:
	var ids: Array = duel.creatures.keys()
	match String(command.get("kind", "")):
		"end_phase": return [0, 0, 0, 0]
		"attack": return [1, ids.find(int(command.id)), 0, 0]
		"block": return [2, ids.find(int(command.id)), ids.find(int(command.target)), 0]
		"cast":
			if int(command.get("grave", -1)) >= 0: return []
			var target := int(command.get("target", -1))
			var card := String(duel.heroes[duel.active_side()].hand[int(command.index)])
			var aim := -99 if duel.target_kind(card) == "none" or target < 0 else (-1 - target if target < 2 else ids.find(target))
			return [3, int(command.index), aim, int(command.get("power", 0))]
	return []

## A reference command as ELCombatSearch.apply takes it.
func _reference_command(duel: ELDuel, raw: Dictionary) -> Dictionary:
	var command := {}
	for key: String in raw: command[key] = int(raw[key]) if raw[key] is float else raw[key]
	match String(command.get("kind", "")):
		"cast":
			if command.has("card"): command.index = duel.heroes[duel.active_side()].hand.find(String(command.card))
			command.target = int(command.get("target", -1))
			command.grave = int(command.get("grave", -1))
			command.power = int(command.get("power", 0))
		"ability":
			command.target = int(command.get("target", -1))
			command.choice = int(command.get("choice", -1))
			command.amount = int(command.get("amount", -1))
	return command

func _said(duel: ELDuel, command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s at %d grave %d power %d" % [String(command.get("card", "?")), int(command.target), int(command.grave), int(command.power)]
		"ability": return "#%d %s at %d choice %d amount %d" % [int(command.id), String(command.key), int(command.target), int(command.choice), int(command.amount)]
		"attack": return "attack #%d" % int(command.id)
		"block": return "block #%d with #%d" % [int(command.target), int(command.id)]
	return String(command.get("kind", "?"))

# --- Coverage of the model -------------------------------------------------------------

## --coverage=1 (or tools/duel_model_coverage.gd): every card with a rule,
## every creature, every enchantment that stands and every thing a hero may
## carry, each on its own in a few small positions. Whatever the engine lists
## for it there is played through both sets of rules, alone and followed by
## three turn ends, and the two must leave the same. Each is then told as
##   agrees      every line came out the same;
##   differs     a line came out differently, or the game refused what the engine listed;
##   chance      the only differences are in lines where the game drew on chance
##               the model cannot be told (which card a discard takes);
##   unlisted    the game allows a use the engine lists none of;
##   incomplete  the lines agree, but in some the model went past what it has room for;
##   unexercised nothing could be done with it in any of the positions.
## `--shard=k/n` takes every n-th thing; `--kinds=card,creature,...` those kinds alone.
func _coverage(shard: String) -> void:
	var kinds := Array(_arg("kinds", "card,creature,worn,laid,carried").split(",", false))
	var only := Array(_arg("names", "").split(",", false))
	var part := int(shard.get_slice("/", 0))
	var parts := maxi(1, int(shard.get_slice("/", 1)))
	var index := 0
	var spell_table: Dictionary = profile.table("CombatSpells")
	for card: String in spell_table:
		var rule := ELCatalog.rule(profile, card)
		if rule.is_empty(): continue
		index += 1
		if index % parts != part or (not only.is_empty() and not only.has(card)): continue
		var effect := String(rule.get("effect", ""))
		if kinds.has("card"): _cover_card(card)
		if kinds.has("creature") and effect == "summon" and profile.table("CombatCreatures").has(card): _cover_creature(card)
		if effect == "enchant":
			var aim := String(rule.get("target", "none"))
			if kinds.has("worn") and aim in ["creature", "any"]: _cover_worn(card)
			if kinds.has("laid") and aim in ["none", "hero", "any"]: _cover_laid(card)
	if kinds.has("carried"):
		var seen := {}
		for name: String in profile.table("Artefacts"):
			var entry := ELDuel.artifact_entry(profile, {"name": name})
			if entry.is_empty() or seen.has(String(entry.spell)): continue
			seen[String(entry.spell)] = true
			index += 1
			if index % parts != part or (not only.is_empty() and not only.has(String(entry.spell))): continue
			_cover_carried(String(entry.spell), entry)
	var totals := {}
	for key: String in cover:
		var t: Dictionary = cover[key]
		var status := "agrees"
		if int(t.differ) > 0: status = "differs"
		elif int(t.unlisted) > 0 and int(t.agree) == 0: status = "unlisted"
		elif int(t.lines) == 0: status = "unexercised"
		elif int(t.chance) > 0: status = "chance"
		elif int(t.incomplete) > 0: status = "incomplete"
		totals["%s %s" % [String(t.kind), status]] = int(totals.get("%s %s" % [String(t.kind), status], 0)) + 1
		print("COVER %s %s %s lines=%d agree=%d differ=%d chance=%d unlisted=%d incomplete=%d reasons=%s%s" % [String(t.kind), String(t.code), status, int(t.lines), int(t.agree),
			int(t.differ), int(t.chance), int(t.unlisted), int(t.incomplete), str(t.reasons), "" if (t.notes as Array).is_empty() else " | " + " || ".join(t.notes)])
	# And each one's name, for the table.
	var named := {}
	for t: Dictionary in cover.values():
		if named.has(t.code): continue
		named[t.code] = true
		print("NAMED %s %s" % [String(t.code), profile.text(String(profile.table("CombatSpells").get(t.code, {}).get("Name", t.code)))])
	for key: String in totals: print("COVERED %s %d" % [key, int(totals[key])])
	print("TOTAL cases=%d fights=%d differed=%d" % [cover.size(), fights, differed])
	quit(0)

func _tally(kind: String, code: String) -> Dictionary:
	var key := kind + " " + code
	if not cover.has(key): cover[key] = {"kind": kind, "code": code, "lines": 0, "agree": 0, "differ": 0, "chance": 0, "unlisted": 0, "incomplete": 0, "notes": [], "reasons": {}}
	return cover[key]

const END := [0, 0, 0, 0]

## A small position for hero 0 to act in: its own creatures are `own` (ids
## from 2), then the other hero's - a kobold, an ogre wearing a Strength of
## its hero's, a rat at rest, a wall and a flyer. `variant` 0: hero 0's
## attack; 1: its defence against the kobold; 2: its attack, with books that
## deal and channels that grow. `change` then alters the position, and every
## creature's points are settled as the game settles them.
func _cover_board(variant: int, hand: Array, own: Array, change: Callable, other: Array = ["STWO"]) -> ELDuel:
	var creatures: Array = own.duplicate(true)
	creatures.append_array([{"card": "KBWR", "owner": 1}, {"card": "GROG", "owner": 1, "enchantments": ["STRG"]}, {"card": "STRT", "owner": 1, "resting": true},
		{"card": "WLBR", "owner": 1}, {"card": "AVEL", "owner": 1}])
	# The second game: a pale creature of each hero's too, hero 0's in the
	# Colourless Plane.
	var pale := profile.id == "el2" and profile.table("CombatCreatures").has("OUS1")
	if pale: creatures.append_array([{"card": "OUS1", "owner": 1}, {"card": "OUS1", "owner": 0}])
	var spec := {"fixed": variant != 2, "rng": 5,
		"heroes": [{"health": 15, "maximum": 20, "mana": 40, "channels": 8, "hand": hand, "grave": ["STRT", "KBWR", "GROG"]},
			{"health": 15, "maximum": 20, "mana": 6, "channels": 5, "hand": ["GROG", "GROG"], "grave": ["KBWR", "STRT", "GROG"], "enchantments": other}],
		"creatures": creatures}
	if variant == 1:
		spec.attacker = 1
		spec.phase = "defence"
		spec.attacks = [2 + own.size()]
	var duel := Fixtures.build(profile, spec)
	if duel == null: return null
	if variant == 2:
		for side in 2:
			duel.heroes[side].deck = ["GROG", "KBWR", "STRT"]
			duel.heroes[side].spell_uses = [9, 9, 9]
	if pale: duel.creatures[duel.creatures.keys()[-1]].plane = true
	if change.is_valid(): change.call(duel)
	for c: Dictionary in duel.creatures.values(): duel._refresh_stats(c)
	return duel

## The commands the engine lists for the hero to move, each with what it
## means to the game: [[kind, a, b, c], command].
func _cover_moves(duel: ELDuel) -> Array:
	var out: Array = []
	var ids: Array = duel.creatures.keys()
	for move: Array in _native_moves(duel, duel.active_side(), true):
		out.append([move, ELCombatBrain._command_of(duel, ids, int(move[0]), int(move[1]), int(move[2]), int(move[3]))])
	return out

## No more than `most` of `moves`, spread over them all.
func _spread(moves: Array, most: int) -> Array:
	if moves.size() <= most: return moves
	var out: Array = []
	for k in most: out.append(moves[k * moves.size() / most])
	return out

## One line through both sets of rules, from the position `build` makes.
func _cover_line(tally: Dictionary, build: Callable, commands: Array, label: String) -> void:
	var duel: ELDuel = build.call()
	var start: ELDuel = build.call()
	if duel == null or start == null: return
	var before := _board(duel)
	var side := duel.active_side()
	var ids: Array = duel.creatures.keys()
	var played: Array = []
	for command: Array in commands:
		if duel.phase == ELDuel.Phase.FINISHED: break
		var done := false
		if int(command[0]) == 0: done = duel.end_phase()
		else:
			var said := ELCombatBrain._command_of(duel, ids, int(command[0]), int(command[1]), int(command[2]), int(command[3]))
			done = String(said.get("kind", "")) != "end_phase" and ELCombatSearch.apply(duel, said)
		if not done:
			if played.is_empty():
				# What the engine lists but will not play itself is no line at
				# all (it lists some casts without trying them); what the model
				# plays and the game refuses is a difference.
				if int(ELCombatBrain.fight(_context(side), start, 4, [command]).get("played", 0)) == 0: return
				tally.lines += 1
				tally.differ += 1
				differed += 1
				if (tally.notes as Array).size() < 3: tally.notes.append("%s: the game refuses %s (%s)" % [label, str(command), duel.error])
				return
			break
		played.append(command)
	tally.lines += 1
	fights += 1
	var model := ELCombatBrain.fight(_context(side), start, 4, played)
	var reasons: Array = ELCombatBrain.last_crowding.duplicate()
	if model.is_empty():
		tally.differ += 1
		differed += 1
		if (tally.notes as Array).size() < 3: tally.notes.append("%s: the model gave no answer to %s" % [label, str(played)])
		return
	var trouble := _compare(duel, model, before, true)
	if int(model.played) != played.size(): trouble.append("the model played %d of %d commands" % [int(model.played), played.size()])
	if int(model.get("limit", 0)) != 0: reasons.append("room")
	var chance := int(model.get("blind", 0)) != 0
	if not reasons.is_empty():
		tally.incomplete += 1
		for reason: String in reasons: tally.reasons[reason] = int(tally.reasons.get(reason, 0)) + 1
	if trouble.is_empty(): tally.agree += 1
	elif chance: tally.chance += 1
	else:
		tally.differ += 1
		differed += 1
		if (tally.notes as Array).size() < 3: tally.notes.append("%s %s: %s" % [label, str(played), " | ".join(trouble)])
		# --trace=1: where along the line the two part, a command at a time.
		if _arg("trace", "") == "1":
			print("TRACE %s %s %s\n   %s" % [String(tally.kind), String(tally.code), label, before.text])
			for upto in range(1, played.size() + 1):
				var again: ELDuel = build.call()
				for command: Array in played.slice(0, upto):
					if int(command[0]) == 0: again.end_phase()
					else: ELCombatSearch.apply(again, ELCombatBrain._command_of(again, ids, int(command[0]), int(command[1]), int(command[2]), int(command[3])))
				var told := ELCombatBrain.fight(_context(side), start, 4, played.slice(0, upto))
				print("   after %d %s: %s\n   %s" % [upto, str(played[upto - 1]), " | ".join(_compare(again, told, before, true)), _board(again).text])

## A line alone, and the same followed by three turn ends.
func _cover_both(tally: Dictionary, build: Callable, commands: Array, label: String) -> void:
	_cover_line(tally, build, commands, label)
	_cover_line(tally, build, commands + [END, END, END], label + "+turns")

## Whether the game lets the hero to move cast the first card of its hand at anything.
func _cover_castable(duel: ELDuel) -> bool:
	var aims: Array = [-1, 0, 1]
	aims.append_array(duel.creatures.keys())
	var names: Array = [-1, 0, 1, 2]
	for holder: int in [0, 1] + duel.creatures.keys():
		for e: Dictionary in duel.entity(holder).enchantments: names.append(int(e.id))
	names.append_array(duel.creatures.keys())
	var card := String(duel.heroes[duel.active_side()].hand[0])
	for aim: int in aims:
		for named: int in names:
			var copy := duel.search_copy()
			if copy.cast(0, aim, named, 1 if copy.variable_power(card) else 0): return true
	return false

const OWN := [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 0, "resting": true}]

## A card cast out of the hand.
func _cover_card(card: String) -> void:
	var tally := _tally("card", card)
	var allowed := false
	for variant in 4:
		# 3: the caster has the fewer channels, for what evens them out.
		var behind := func(d: ELDuel) -> void:
			d.heroes[0].channels = 3
			d.heroes[1].channels = 6
		var build := func() -> ELDuel: return _cover_board(variant % 3, [card, "GROG"], OWN, behind if variant == 3 else Callable())
		var probe: ELDuel = build.call()
		if probe == null: continue
		var mine: Array = []
		for pair: Array in _cover_moves(probe):
			if String(pair[1].get("kind", "")) == "cast" and int(pair[1].get("index", -1)) == 0: mine.append(pair[0])
		if mine.is_empty():
			if not allowed and _cover_castable(probe):
				allowed = true
				tally.unlisted += 1
				if (tally.notes as Array).size() < 3: tally.notes.append("v%d: the game allows a cast the engine does not list" % variant)
			continue
		for move: Array in _spread(mine, 6): _cover_both(tally, build, [move], "v%d" % variant)

## The commands the engine lists for the creature or the hero `id`: its abilities.
func _cover_abilities(probe: ELDuel, id: int, carried := false) -> Array:
	var mine: Array = []
	for pair: Array in _cover_moves(probe):
		if String(pair[1].get("kind", "")) != "ability" or int(pair[1].get("id", -1)) != id: continue
		if String(pair[1].get("key", "")).begins_with("artifact:") != carried: continue
		mine.append(pair[0])
	return mine

## A creature in play: its fights, its abilities and its turns.
func _cover_creature(card: String) -> void:
	var tally := _tally("creature", card)
	for variant in 4:
		# 3: the creature at rest, for what it does resting.
		var own := [{"card": card, "owner": 0, "resting": variant == 3}, {"card": "STRT", "owner": 0}]
		# One whose card gives it no health of its own was made with some.
		if int(profile.table("CombatCreatures")[card].Toughness) <= 0: own[0].merge({"base": [2, 2], "power": 2, "toughness": 2})
		var build := func() -> ELDuel: return _cover_board(variant % 3, ["GROG"], own, Callable())
		var probe: ELDuel = build.call()
		if probe == null: continue
		var moves := _cover_moves(probe)
		var listed := moves.map(func(pair: Array) -> Array: return pair[0])
		if variant == 0 and listed.has([1, 0, 0, 0]):
			_cover_line(tally, build, [[1, 0, 0, 0], END, END], "attack")
			_cover_line(tally, build, [[1, 0, 0, 0], END, [2, 2, 0, 0], END], "blocked")
			_cover_line(tally, build, [[1, 0, 0, 0], END, [2, 3, 0, 0], END, END, END], "blocked by the ogre")
			_cover_line(tally, build, [[1, 0, 0, 0], END, [2, 6, 0, 0], END], "blocked by the flyer")
		if variant == 1 and listed.has([2, 0, 2, 0]): _cover_line(tally, build, [[2, 0, 2, 0], END, END, END], "blocks")
		if variant != 1 and variant != 3: _cover_line(tally, build, [END, END, END], "turns v%d" % variant)
		var able := _cover_abilities(probe, 2)
		for move: Array in _spread(able, 5): _cover_both(tally, build, [move], "ability v%d" % variant)
		if able.is_empty():
			for ability: Dictionary in probe.abilities(2):
				if probe.can_use_ability(2, String(ability.key)):
					tally.unlisted += 1
					if (tally.notes as Array).size() < 3: tally.notes.append("v%d: the game allows %s, which the engine does not list" % [variant, String(ability.key)])

## An enchantment standing on a creature: its own hero's, the other's, and
## one the other hero laid.
func _cover_worn(card: String) -> void:
	var tally := _tally("worn", card)
	for where in 3:
		var own := [{"card": "KBWR", "owner": 0}, {"card": "STRT", "owner": 0}]
		# Laid as the game lays it: on the hero's own kobold, on the other
		# hero's, and on its own by the other hero.
		var change := func(d: ELDuel) -> void: d._enchant(card, 1 if where == 2 else 0, 4 if where == 1 else 2, ELCatalog.rule(profile, card))
		for variant in 2:
			var build := func() -> ELDuel: return _cover_board(variant, ["GROG"], own, change)
			var probe: ELDuel = build.call()
			if probe == null: continue
			var listed := _cover_moves(probe).map(func(pair: Array) -> Array: return pair[0])
			if variant == 0:
				if listed.has([1, 0, 0, 0]):
					_cover_line(tally, build, [[1, 0, 0, 0], END, END], "attack w%d" % where)
					_cover_line(tally, build, [[1, 0, 0, 0], END, [2, 2, 0, 0], END, END, END], "blocked w%d" % where)
				_cover_line(tally, build, [END, END, END], "turns w%d" % where)
			elif listed.has([2, 0, 2, 0]): _cover_line(tally, build, [[2, 0, 2, 0], END, END, END], "blocks w%d" % where)
			for move: Array in _spread(_cover_abilities(probe, 2), 3): _cover_both(tally, build, [move], "ability w%d v%d" % [where, variant])

## An enchantment standing on a hero: the one to move, and the other.
func _cover_laid(card: String) -> void:
	var tally := _tally("laid", card)
	for where in 2:
		for variant in 3:
			# Laid as the game lays it, in its hero's own turn: this one, or the one before.
			var change := func(d: ELDuel) -> void:
				d._enchant(card, where, where, ELCatalog.rule(profile, card))
				if where != d.attacker and not d.heroes[where].enchantments.is_empty(): d.heroes[where].enchantments[-1].born = d.turn_serial - 1
			var build := func() -> ELDuel: return _cover_board(variant, ["GROG"], OWN, change)
			var probe: ELDuel = build.call()
			if probe == null or probe._enchantment_count(where, card) == 0: continue
			var listed := _cover_moves(probe).map(func(pair: Array) -> Array: return pair[0])
			if variant != 1:
				if listed.has([1, 0, 0, 0]): _cover_line(tally, build, [[1, 0, 0, 0], END, [2, 2, 0, 0], END, END, END], "attack h%d v%d" % [where, variant])
				_cover_line(tally, build, [END, END, END], "turns h%d v%d" % [where, variant])
			elif listed.has([2, 0, 2, 0]): _cover_line(tally, build, [[2, 0, 2, 0], END, END, END], "blocks h%d" % where)
			var able := _cover_abilities(probe, 0)
			for move: Array in _spread(able, 4): _cover_both(tally, build, [move], "ability h%d v%d" % [where, variant])
			if able.is_empty() and where == 0:
				for ability: Dictionary in probe.abilities(0):
					if probe.can_use_ability(0, String(ability.key)):
						tally.unlisted += 1
						if (tally.notes as Array).size() < 3: tally.notes.append("v%d: the game allows %s, which the engine does not list" % [variant, String(ability.key)])

## A thing a hero carries.
func _cover_carried(spell: String, entry: Dictionary) -> void:
	var tally := _tally("carried", spell)
	for variant in 3:
		var change := func(d: ELDuel) -> void:
			var thing := entry.duplicate(true)
			thing.charges = 2
			thing.ready_round = 0
			d.heroes[0].artifacts = [thing]
			d.heroes[0].artifact_uses = 0
		var build := func() -> ELDuel: return _cover_board(variant, ["GROG"], OWN, change)
		var probe: ELDuel = build.call()
		if probe == null: continue
		var able := _cover_abilities(probe, 0, true)
		for move: Array in _spread(able, 6): _cover_both(tally, build, [move], "v%d" % variant)
		if able.is_empty() and probe.artifact_error(0, 0).is_empty():
			tally.unlisted += 1
			if (tally.notes as Array).size() < 3: tally.notes.append("v%d: the game allows its use, which the engine does not list" % variant)

## The commands the engine lists at its first command here, [kind, a, b, c].
func _native_moves(duel: ELDuel, side: int, proof: bool) -> Array:
	var raw: PackedInt32Array = ELCombatBrain.ask(_context(side), duel, 1, 1, true, 11 if proof else 10).get("raw", PackedInt32Array())
	var out: Array = []
	# A library that does not list answers something else, of another length.
	if raw.size() < 1 or raw.size() != 1 + 4 * int(raw[0]): return out
	for i in int(raw[0]):
		var at := 1 + i * 4
		if at + 3 >= raw.size(): break
		out.append([int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3])])
	return out

## Whether two commands do the same: the same card (any copy of it), the same
## aim and choices; a hero's ability by any copy of it; no aim where the
## rule has none.
func _same_command(duel: ELDuel, ours: Dictionary, wanted: Dictionary) -> bool:
	var kind := String(wanted.get("kind", ""))
	if String(ours.get("kind", "")) != kind: return false
	var side := duel.active_side()
	match kind:
		"end_phase": return true
		"attack": return int(ours.id) == int(wanted.id)
		"block": return int(ours.id) == int(wanted.id) and int(ours.target) == int(wanted.target)
		"cast":
			var hand: Array = duel.heroes[side].hand
			if int(ours.index) < 0 or int(ours.index) >= hand.size() or int(wanted.index) < 0: return false
			var card := String(hand[int(wanted.index)])
			if String(hand[int(ours.index)]) != card: return false
			var aimed := duel.target_kind(card) != "none"
			if aimed and int(ours.target) != int(wanted.target): return false
			if int(ours.get("grave", -1)) != int(wanted.get("grave", -1)) and (int(ours.get("grave", -1)) >= 0 or int(wanted.get("grave", -1)) >= 0): return false
			if duel.variable_power(card) and int(ours.get("power", 0)) != int(wanted.get("power", 0)): return false
			return true
		"ability":
			var id := int(wanted.id)
			if int(ours.id) != id: return false
			var key := String(wanted.key)
			var theirs := String(ours.key)
			if id < 2:
				key = key.get_slice(":", 0)
				theirs = theirs.get_slice(":", 0)
			if key != theirs: return false
			var aimed := true
			for definition: Dictionary in duel.abilities(id):
				if String(definition.get("key", "")) == String(wanted.key) and String(definition.get("target", "none")) == "none": aimed = false
			if aimed and int(ours.target) != int(wanted.target): return false
			if int(ours.choice) != int(wanted.choice) and (int(ours.choice) >= 0 or int(wanted.choice) >= 0): return false
			if int(ours.amount) != int(wanted.amount) and (int(ours.amount) >= 0 or int(wanted.amount) >= 0): return false
			return true
	return false
