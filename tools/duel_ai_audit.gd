extends SceneTree
## Counts the computer opponent's plainly poor plays in computer-vs-computer
## duels, the kind a player watching would call a blunder:
##
##   wasted    a spell or ability that changed nothing but the caster's hand
##             and ether
##   surplus   a spell that only gave ether, in a turn whose other plays
##             the ether already there would have paid for, by a hero with
##             no creature that regenerates (ether left over pays for that
##             through the other hero's turn)
##   missed    a turn that could have won by attacking (the opponent's own
##             blocking could not have stopped it) and did not
##   unblocked the hero died to an attack that its creatures could have stopped
##   futile    an attack that dealt no damage and killed nothing, and lost a
##             creature to a blocker that stood ready when it was sent, with
##             no spell or ability played in between
##   chump     a blocker thrown away under an attacker that survived, when
##             the whole attack was less than half the hero's health (listed,
##             not judged: played out, these blocks won a little more often
##             than not blocking)
##   idle      a turn ended with a creature card in hand that the ether left
##             would have paid for (not always a mistake; counted for scale)
##
##   godot --headless --path game --script ../tools/duel_ai_audit.gd -- \
##       [--game=el1|el2] [--ai=<settings>] [--pairs=N] [--seed=N] \
##       [--shard=I/N] [--books=starter|preset] [--save=<folder>] [--quiet]
##
## Prints one AUDIT line per play with the position, and the totals. --save
## writes each position as a duel save that ELDuel.restore reads (an idle
## one only while the army has room). Settings are those of duel_ai_bench.gd ("orig", "smart", "smart:...").
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const LETTER := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
const ROUND_CAP := 30
const PHASE_CAP := 80
## Hero entries a spell may change without having done anything.
const SPENT := ["hand", "hand_slots", "hand_view", "hand_ids", "mana", "grave", "spell_uses", "drawn"]

var profile: ELProfile
var defaults := {}
var settings := {}
var save := ""
var quiet := false
var totals := {"wasted": 0, "surplus": 0, "missed": 0, "unblocked": 0, "futile": 0, "chump": 0, "idle": 0, "turns": 0, "duels": 0, "commands": 0}
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
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if stored is Dictionary: folder = String(stored.get(game, ""))
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
	var text := _arg("ai", "smart")
	settings = {"smart": text.get_slice(":", 0) != "orig", "set": {}}
	for item: String in (text.get_slice(":", 1) if text.contains(":") else "").split(",", false):
		var name := "smart_" + item.get_slice("=", 0)
		if not defaults.has(name):
			printerr("Unknown setting: " + name)
			quit(1)
			return
		settings.set[name] = str_to_var(item.get_slice("=", 1))
	for name: String in defaults: (ELCombatSearch as Script).set(name, settings.set.get(name, defaults[name]))
	save = _arg("save", "")
	quiet = _arg("quiet", "") == "1"
	var pairs := int(_arg("pairs", "8"))
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
	print("TOTAL " + " ".join(totals.keys().map(func(key: String) -> String: return "%s=%d" % [key, totals[key]])))
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

func _think(d: ELDuel) -> Dictionary:
	var smart: Array[int] = []
	if settings.smart: smart.append(d.active_side())
	d.smart_sides = smart
	return ELCombatSearch.think(d)

func _play(game: String, books: Array, seed_value: int) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": books}):
		printerr("Cannot start: " + duel.error)
		return
	totals.duels += 1
	var commands := 0
	var mark := [-1, -1, -1]
	# This turn: the position it began from when an attack could have won it,
	# the creatures of the other side ready as each attacker was sent, and
	# whether anything was played after the first attacker.
	var winnable: Dictionary = {}
	var turn_start: Dictionary = {}
	# Ether-only spells of this turn: the position, the command, the ether the
	# hero would hold without it, and whether a later play needed more.
	var gains: Array[Dictionary] = []
	var missed: Dictionary = {}
	var sent := {}
	var played_since := false
	var block_start: Dictionary = {}
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
			if duel.phase == ELDuel.Phase.ATTACK:
				# The last turn could have won and the duel goes on.
				if not missed.is_empty(): _found("missed", game, missed, 1 - side, "attack with %s wins" % str(missed.ids))
				missed = {}
				totals.turns += 1
				sent = {}
				played_since = false
				winnable = _winning_attack(duel)
				turn_start = {"state": duel.snapshot(), "board": _board(duel)}
				gains = []
			else:
				block_start = {"state": duel.snapshot(), "board": _board(duel), "saving": _saving_blocks(duel)}
		commands += 1
		totals.commands += 1
		var command := _think(duel) if commands <= PHASE_CAP else {}
		var kind := String(command.get("kind", "end_phase"))
		var before := {"state": duel.snapshot(), "board": _board(duel)} if kind in ["cast", "ability"] or duel.phase == ELDuel.Phase.DEFENCE else {}
		var fight := _fight(duel) if duel.phase == ELDuel.Phase.DEFENCE and kind == "end_phase" else {}
		var trace := _mark(duel, side) if kind in ["cast", "ability"] else []
		var spent := _price(duel, side, command) if kind == "cast" else 0
		if kind == "end_phase" and duel.phase == ELDuel.Phase.ATTACK:
			_idle(game, duel, side)
			var banks := duel.army(side).any(func(c: Dictionary) -> bool: return duel.regeneration_cost(c.id) > 0)
			for gain: Dictionary in gains:
				if not gain.needed and not banks: _found("surplus", game, gain.position, side, "%s was not needed, %d ether left unspent" % [gain.text, duel.available_mana(side)])
		if kind == "attack":
			var ready: Array = []
			for c: Dictionary in duel.army(1 - side):
				if duel.ready(c.id): ready.append(int(c.id))
			sent[int(command.id)] = ready
		elif kind in ["cast", "ability"] and not sent.is_empty(): played_since = true
		var ended_turn := kind == "end_phase" and duel.phase == ELDuel.Phase.ATTACK
		var ether := int(duel.heroes[side].mana)
		var price := spent if kind == "cast" else (duel.attack_cost(int(command.id)) if kind == "attack" else -1)
		if command.is_empty() or not ELCombatSearch.apply(duel, command):
			duel.end_phase()
			kind = "end_phase"
		if kind in ["cast", "ability"] and not trace.is_empty():
			var after := _mark(duel, side)
			var hero: Dictionary = duel.heroes[side]
			var hand: Array = hero.hand.duplicate()
			if kind == "cast": hand.append(String(command.card))
			hand.sort()
			if duel.phase != ELDuel.Phase.FINISHED and after[0] == trace[0] and int(hero.mana) == int(trace[1]) - spent and hand == trace[2]:
				_found("wasted", game, before, side, _describe(command))
			elif duel.phase == ELDuel.Phase.ATTACK and after[0] == trace[0] and int(hero.mana) > int(trace[1]) - spent and hand == trace[2]:
				gains.append({"position": before, "text": _describe(command), "without": int(trace[1]), "needed": false, "fresh": true})
		if ended_turn: missed = winnable
		elif duel.phase == ELDuel.Phase.ATTACK and duel.active_side() == side:
			# What each play cost, against the ether there would be without the
			# ether spells before it (refunds and other gains follow along).
			var change := int(duel.heroes[side].mana) - ether
			for gain: Dictionary in gains:
				if gain.fresh:
					gain.fresh = false
					continue
				if int(gain.without) < (price if price >= 0 else maxi(0, -change)): gain.needed = true
				gain.without = int(gain.without) + change
		if not fight.is_empty():
			_after_fight(game, duel, fight, before, sent, played_since, block_start, turn_start)
	if not quiet: print("END %s winner=%d rounds=%d" % [game, duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1, duel.round_number])

func _context(d: ELDuel, side: int) -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.steady_weights(ctx.second)
	ctx.remember = true
	return ctx

## The start of a turn that an attack alone wins: the attackers the compiled
## lookahead names, confirmed against the opponent's own defence under the
## real rules. Empty when there is none.
func _winning_attack(d: ELDuel) -> Dictionary:
	if not ELCombatBrain.available: return {}
	var side := d.active_side()
	var answer := ELCombatBrain.ask(_context(d, side), d, 1, 200000, true)
	if answer.is_empty() or int(answer.status) != 1 or answer.ids.is_empty(): return {}
	var copy := d.search_copy()
	for id: int in answer.ids:
		if not copy.toggle_attack(id): return {}
	copy.end_phase()
	var steps := 0
	while copy.phase == ELDuel.Phase.DEFENCE and steps < PHASE_CAP:
		steps += 1
		var command := _think(copy)
		if command.is_empty() or not ELCombatSearch.apply(copy, command): copy.end_phase()
	if copy.phase != ELDuel.Phase.FINISHED or copy.winner != side: return {}
	return {"state": d.snapshot(), "board": _board(d), "ids": answer.ids}

## The blocks that keep the defending hero alive this fight, as the compiled
## lookahead finds them and the real rules confirm; empty when there are none
## or the hero is in no danger.
func _saving_blocks(d: ELDuel) -> Array:
	if not ELCombatBrain.available: return []
	var side := d.active_side()
	var unblocked := d.search_copy()
	unblocked.end_phase()
	if unblocked.phase != ELDuel.Phase.FINISHED or unblocked.winner == side: return []
	var answer := ELCombatBrain.ask(_context(d, side), d, 1, 200000, true)
	if answer.is_empty() or answer.ids.is_empty(): return []
	var copy := d.search_copy()
	for i in range(0, answer.ids.size() - 1, 2):
		if not copy.assign_block(int(answer.ids[i]), int(answer.ids[i + 1])): return []
	copy.end_phase()
	if copy.phase == ELDuel.Phase.FINISHED and copy.winner != side: return []
	return answer.ids

## The fight about to be resolved: who attacks, who blocks whom, and the
## defending hero's health.
func _fight(d: ELDuel) -> Dictionary:
	var power := 0
	for id: int in d.attacks:
		if d.creatures.has(id): power += int(d.creatures[id].power)
	var foes := 0
	for c: Dictionary in d.army(1 - d.attacker): foes += 1
	return {"attacks": d.attacks.duplicate(), "blocks": d.blocks.duplicate(), "defender": 1 - d.attacker, "health": int(d.heroes[1 - d.attacker].health), "power": power, "foes": foes, "board": _board(d)}

func _after_fight(game: String, d: ELDuel, fight: Dictionary, before: Dictionary, sent: Dictionary, played_since: bool, block_start: Dictionary, turn_start: Dictionary) -> void:
	var defender := int(fight.defender)
	var finished := d.phase == ELDuel.Phase.FINISHED
	if finished and d.winner != defender and not block_start.get("saving", []).is_empty():
		_found("unblocked", game, block_start, defender, "blocks %s save the hero" % str(block_start.saving))
	if finished: return
	var hurt := int(fight.health) - int(d.heroes[defender].health)
	var foes := 0
	for c: Dictionary in d.army(defender): foes += 1
	var lost: Array = []
	for id: int in fight.attacks:
		if d.creatures.has(id): continue
		var foreseen := false
		for blocker: int in fight.blocks:
			if int(fight.blocks[blocker]) == id and sent.get(id, []).has(blocker) and d.creatures.has(blocker): foreseen = true
		if foreseen: lost.append(id)
	if not lost.is_empty() and hurt <= 0 and foes >= int(fight.foes) and not played_since:
		_found("futile", game, turn_start, 1 - defender, "lost %s for nothing to blocks %s" % [str(lost), str(fight.blocks)])
	var thrown: Array = []
	for blocker: int in fight.blocks:
		if not d.creatures.has(blocker) and d.creatures.has(int(fight.blocks[blocker])): thrown.append(blocker)
	if not thrown.is_empty() and int(fight.power) * 2 < int(fight.health):
		_found("chump", game, before, defender, "threw away %s under an attack of %d at health %d" % [str(thrown), fight.power, fight.health])

## What a spell could change: the whole battlefield and both heroes but for
## the caster's hand and ether, then that ether and the hand's cards.
func _mark(d: ELDuel, side: int) -> Array:
	var heroes: Array = []
	for index in 2:
		var hero: Dictionary = d.heroes[index].duplicate()
		if index == side:
			for key: String in SPENT: hero.erase(key)
		heroes.append(hero)
	var hand: Array = d.heroes[side].hand.duplicate()
	hand.sort()
	return [var_to_str([heroes, d.creatures, d.attacks, d.blocks, d.phase]), int(d.heroes[side].mana), hand]

func _price(d: ELDuel, side: int, command: Dictionary) -> int:
	var card := String(command.get("card", d.heroes[side].hand[int(command.index)]))
	var rule := ELCatalog.rule(profile, card)
	return d.cost(card) + (int(command.power) if rule.get("x_source", "") != "health" else 0)

func _idle(game: String, d: ELDuel, side: int) -> void:
	var hero: Dictionary = d.heroes[side]
	for card: String in hero.hand:
		if profile.table("CombatCreatures").has(card) and ELCatalog.rule(profile, card).get("effect", "") == "summon" and d.cost(card) <= d.available_mana(side):
			# Counted apart from the plays above; saved only with room in the army.
			totals.idle -= 1
			_found("idle", game, {"board": _board(d), "state": d.snapshot()} if d.army(side).size() < 8 else {"board": _board(d)}, side, "%s (%d) with %d ether" % [card, d.cost(card), d.available_mana(side)])
			totals.idle += 1
			return

func _found(kind: String, game: String, position: Dictionary, side: int, note: String) -> void:
	totals[kind] += 1
	print("AUDIT %s %s side%d: %s" % [kind, game, side, note])
	if not quiet: print(position.get("board", ""))
	if save.is_empty() or not position.has("state"): return
	saved += 1
	var path := "%s/%s-%s-%s-%d.json" % [save, profile.id, kind, game, saved]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"format": "etherlords-duel", "version": 1, "state": position.state, "found": {"kind": kind, "side": side, "note": note}}, "", true, true))
	file.close()
	print("   saved %s" % path)

func _board(duel: ELDuel) -> String:
	var text := "   -- round %d, side %d %s" % [duel.round_number, duel.attacker, "to attack" if duel.phase == ELDuel.Phase.ATTACK else "attacks with %s, side %d to block, blocks %s" % [str(duel.attacks), 1 - duel.attacker, str(duel.blocks)]]
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

func _describe(command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s target %d choice %d x %d" % [command.card, command.target, command.grave, command.power]
		"attack": return "attack with #%d" % command.id
		"block": return "block #%d with #%d" % [command.target, command.id]
		"ability": return "ability %s of %d target %d" % [command.key, command.id, command.target]
	return "end phase"
