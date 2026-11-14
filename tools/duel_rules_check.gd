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
## mastery of theirs can roll and the fight is the plain rules alone.
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

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

## A name the game gives a thing a hero carries, by the spell it works.
var artifact_names := {}

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
	if _arg("line", "") == "1":
		_lines(int(_arg("cases", "20")), shard)
		for what: String in line_blame: print("PARTS %s %d" % [what, line_blame[what]])
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, cases, differed])
		quit(0)
		return
	if _arg("real", "") == "1":
		_real(random, int(_arg("cases", "20")), shard)
		for card: String in blamed: print("BLAME %s %d" % [card, blamed[card]])
		for card: String in standing_blame: print("STANDING %s %d" % [card, standing_blame[card]])
		for card: String in cast_blame: print("CAST %s %d" % [card, cast_blame[card]])
		print("TOTAL cases=%d fights=%d differed=%d" % [cases, fights, differed])
		quit(0)
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
	quit(0)

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
			choice.shuffle()
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
				# The next card the engine was told of that is this one.
				var named := -1
				var listed: Array = coming[hero]
				for k in range(int(drawn[hero]), listed.size()):
					if String(listed[k]) == String(now[at_now + extra]):
						named = k
						break
				slots.append(ELCombatBrain.HAND + named if named >= 0 else -1)
				if named >= 0: drawn[hero] = named + 1
			places[hero] = slots
		for id: int in copy.creatures:
			if not ids.has(id): ids.append(id)
		commands.append(cmd)
		said.append(what)
		after.append(copy.search_copy())
	if commands.is_empty() and refused.is_empty(): return
	# The first command after which the two no longer agree: a command the
	# game turns down later is often only what that parting led to.
	for i in said.size():
		var part := ELCombatBrain.fight(ctx, start, 4, commands.slice(0, i + 1), 200000)
		if part.is_empty(): return
		var parting := _compare(after[i], part, before, true)
		var phase_now := 0 if (after[i] as ELDuel).phase == ELDuel.Phase.ATTACK else 1
		if (after[i] as ELDuel).phase != ELDuel.Phase.FINISHED and int(part.phase) != phase_now:
			parting.append("the game stands in phase %d, the model in %d" % [phase_now, int(part.phase)])
		if int(part.played) != i + 1: parting.append("the model turned down one of its own commands")
		var game: ELDuel = after[i]
		walked.append("%s: game %d/%d health %d/%d ether, model %d/%d health %d/%d ether" % [said[i],
			int(game.heroes[0].health), int(game.heroes[1].health), int(game.heroes[0].mana), int(game.heroes[1].mana),
			int(part.health[0]), int(part.health[1]), int(part.ether[0]), int(part.ether[1])])
		if parting.is_empty(): continue
		trouble = parting
		var name: String = String(said[i]).get_slice(" #", 0)
		line_blame[name] = int(line_blame.get(name, 0)) + 1
		trouble.append("first after \"%s\"" % said[i])
		break
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
	return said

## A short run of commands through both sets of rules. The model is handed the
## board as it stood, then the same commands, and must arrive where the game
## arrived.
func _play_case(index: int, duel: ELDuel, random: RandomNumberGenerator, attacker: int) -> void:
	var start := duel.search_copy()
	var before := _board(duel)
	# Where each card of a hand stood when the model was told the board.
	var hands: Array = [[], []]
	for side in 2:
		for i in mini(duel.heroes[side].hand.size(), 8): hands[side].append(i)
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
	for line: String in said:
		if line.begins_with("cast "): cast_total[line.substr(5)] = int(cast_total.get(line.substr(5), 0)) + 1
	var trouble := _compare(duel, model, before, true)
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
