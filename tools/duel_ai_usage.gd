extends SceneTree
## Tallies what the computer opponent does with every spell and ability, in
## computer-vs-computer duels played from random spellbooks so that each card
## of the game turns up:
##
##   SPELL <card> seen=<turns it began in hand> cast=<times cast>
##         kept=<turns ended with it in hand, paid for, when casting it
##         would have changed something>
##   ABILITY <card>:<ability> used=<times> unused=<turns ended with it usable>
##   POWER <card> casts=<times> x=<ether paid into X in all> most=<the X it
##         could have paid in all> least=<casts that paid under half of
##         it; health is never counted, since paying all of it would kill>
##   AREA  <card> casts=<times> hit=<enemy creatures it could reach in all>
##         bare=<casts with one or none>
##
## A card that is seen often, never cast and often kept is one the opponent
## does not know how to play.
##
##   godot --headless --path game --script ../tools/duel_ai_usage.gd -- \
##       [--game=el1|el2] [--ai=<settings>] [--duels=N] [--seed=N] \
##       [--shard=I/N] [--level=N] [--save=<folder>] [--watch=CARD,...]
##       [--force=CARD,...]
##
## --save alone writes the position before each cast that paid under half the
## X it could, or spread an area spell over one creature or none.
## --save with --watch writes the position of each turn that ended with a
## watched card kept (or a watched "CARD:ability" or ability unused) as a
## duel save. --force puts the cards in every book of their faction.
## Settings are those of duel_ai_bench.gd ("orig", "smart", "smart:...").
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const ROUND_CAP := 30
const PHASE_CAP := 80
const BOOK := 16
## Spells that reach a whole army or both hands at once.
const MASS := ["wave", "cleanse", "amnesia", "ban", "discard_creatures", "flux", "pale_calamity", "discard_all"]

var profile: ELProfile
var settings := {}
var spells := {}
var powers := {}
var areas := {}
var abilities := {}
var save := ""
var watch: Array = []
var force: Array = []
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
	var text := _arg("ai", "smart")
	settings = {"smart": text.get_slice(":", 0) != "orig"}
	for item: String in (text.get_slice(":", 1) if text.contains(":") else "").split(",", false):
		(ELCombatSearch as Script).set("smart_" + item.get_slice("=", 0), str_to_var(item.get_slice("=", 1)))
	save = _arg("save", "")
	watch = Array(_arg("watch", "").split(",", false))
	force = Array(_arg("force", "").split(",", false))
	var level := int(_arg("level", "12"))
	var shard := _arg("shard", "0/1")
	var pools := _pools()
	var random := RandomNumberGenerator.new()
	for index in int(_arg("duels", "8")):
		random.seed = hash([int(_arg("seed", "1")), index])
		var players: Array = []
		for side in 2:
			var faction: String = FACTIONS[random.randi() % FACTIONS.size()]
			players.append({"faction": faction, "level": level, "cards": _book(pools[faction], random)})
		var seed_value := int(random.randi() & 0x7fffffff)
		if index % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		_play(players, seed_value)
	for card: String in spells:
		var row: Dictionary = spells[card]
		print("SPELL %s seen=%d cast=%d kept=%d name=%s" % [card, row.seen, row.cast, row.kept, row.name])
	for card: String in powers:
		var row: Dictionary = powers[card]
		print("POWER %s casts=%d x=%d most=%d least=%d" % [card, row.casts, row.x, row.most, row.least])
	for card: String in areas:
		var row: Dictionary = areas[card]
		print("AREA %s casts=%d hit=%d bare=%d" % [card, row.casts, row.hit, row.bare])
	for key: String in abilities:
		var row: Dictionary = abilities[key]
		print("ABILITY %s used=%d unused=%d name=%s" % [key, row.used, row.unused, row.name])
	print("DONE")
	quit(0)

## Every card a faction's book may hold, creatures apart from the rest.
func _pools() -> Dictionary:
	var result := {}
	for faction: String in FACTIONS:
		var pool := {"creatures": [], "spells": []}
		for card: String in profile.table("CombatSpells"):
			if ELCatalog.rule(profile, card).is_empty(): continue
			var probe := ELDuel.new()
			var player := {"faction": faction, "cards": [card]}
			if not probe.start(profile, 1, {"players": [player, player]}): continue
			pool["creatures" if profile.table("CombatCreatures").has(card) else "spells"].append(card)
		result[faction] = pool
	return result

## Half creatures, half other spells, no card twice while the pool lasts.
func _book(pool: Dictionary, random: RandomNumberGenerator) -> Array:
	var cards: Array = []
	for kind: String in ["creatures", "spells"]:
		var left: Array = pool[kind].duplicate()
		var forced: Array = force.filter(func(card: String) -> bool: return left.has(card))
		for card: String in forced: left.erase(card)
		cards.append_array(forced)
		for i in BOOK / 2 - forced.size():
			if left.is_empty(): left = pool[kind].duplicate()
			if left.is_empty(): break
			cards.append(left.pop_at(random.randi() % left.size()))
	return cards

func _spell(d: ELDuel, card: String) -> Dictionary:
	if not spells.has(card): spells[card] = {"seen": 0, "cast": 0, "kept": 0, "name": d.card_name(card)}
	return spells[card]

func _ability(d: ELDuel, id: int, key: String) -> Dictionary:
	var card := ""
	var name := ""
	if id < 2:
		for ability: Dictionary in d.abilities(id):
			if ability.key != key: continue
			name = String(ability.get("name", ""))
			for e: Dictionary in d.heroes[id].enchantments:
				if e.id == ability.get("enchantment", -1): card = e.card
			if key.begins_with("artifact:"): card = String(ability.get("card", "artifact"))
	elif d.creatures.has(id):
		card = d.creatures[id].card
		for ability: Dictionary in d.abilities(id):
			if ability.key == key: name = String(ability.get("name", ""))
	var label := "%s:%s" % [card, key.get_slice(":", 0)]
	if not abilities.has(label): abilities[label] = {"used": 0, "unused": 0, "name": "%s / %s" % [d.card_name(card) if not card.is_empty() else "", name]}
	return abilities[label]

func _think(d: ELDuel) -> Dictionary:
	var smart: Array[int] = []
	if settings.smart: smart.append(d.active_side())
	d.smart_sides = smart
	return ELCombatSearch.think(d)

func _play(players: Array, seed_value: int) -> void:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": players}):
		printerr("Cannot start: " + duel.error)
		return
	var commands := 0
	var mark := [-1, -1, -1]
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP:
		var side := duel.active_side()
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
			if duel.phase == ELDuel.Phase.ATTACK:
				var began := {}
				for card: String in duel.heroes[side].hand: began[card] = true
				for card: String in began: _spell(duel, card).seen += 1
		commands += 1
		var command := _think(duel) if commands <= PHASE_CAP else {}
		match String(command.get("kind", "end_phase")):
			"cast":
				var card := String(command.card)
				_spell(duel, card).cast += 1
				if duel.variable_power(card) and ELCatalog.rule(profile, card).get("x_source", "") != "health":
					if not powers.has(card): powers[card] = {"casts": 0, "x": 0, "most": 0, "least": 0}
					var most := duel.maximum_power(card)
					var row: Dictionary = powers[card]
					row.casts += 1
					row.x += int(command.power)
					row.most += most
					if int(command.power) * 2 < most:
						row.least += 1
						_save(duel, side, "power-%s" % card)
				if String(ELCatalog.rule(profile, card).get("effect", "")) in MASS:
					if not areas.has(card): areas[card] = {"casts": 0, "hit": 0, "bare": 0}
					var reach := duel.army(1 - side).size()
					var row: Dictionary = areas[card]
					row.casts += 1
					row.hit += reach
					if reach <= 1:
						row.bare += 1
						_save(duel, side, "area-%s" % card)
			"ability": _ability(duel, int(command.id), String(command.key)).used += 1
			"end_phase":
				if duel.phase == ELDuel.Phase.ATTACK: _turn_end(duel, side)
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	print("END winner=%d rounds=%d" % [duel.winner, duel.round_number])

## What the hero could still have played as it ended its own turn.
func _turn_end(d: ELDuel, side: int) -> void:
	var kept := {}
	var hand: Array = d.heroes[side].hand
	for index in hand.size():
		var card: String = hand[index]
		if kept.has(card) or d.cost(card) > d.available_mana(side) or not d.phase_allows(card): continue
		kept[card] = false
		if not _useful(d, index, card): continue
		kept[card] = true
		_spell(d, card).kept += 1
		if card in watch: _save(d, side, card)
	var holders: Array = [side]
	for c: Dictionary in d.army(side): holders.append(int(c.id))
	var counted := {}
	for id: int in holders:
		for ability: Dictionary in d.abilities(id):
			if not d.can_use_ability(id, ability.key): continue
			var row := _ability(d, id, String(ability.key))
			if counted.has(row): continue
			counted[row] = true
			row.unused += 1
			var label: String = abilities.find_key(row)
			if label in watch or label.get_slice(":", 1) in watch: _save(d, side, label)

## Whether some way of casting the card changes more than the hand and ether.
func _useful(d: ELDuel, index: int, card: String) -> bool:
	var rule := ELCatalog.rule(profile, card)
	var targets: Array = [-1]
	if d.target_kind(card) != "none": targets = d.valid_targets(card).slice(0, 12)
	var power := 0
	if d.variable_power(card): power = 1 if rule.get("x_source") == "health" else d.maximum_power(card)
	for target: int in targets:
		for choice: int in ELCombatSearch._spell_choices(d, card, String(rule.get("effect", "")), target).slice(0, 6):
			var line := ELCombatSearch.Line.new()
			line.command = {"kind": "cast", "index": index, "card": card, "target": target, "grave": choice, "power": power}
			var copy := d.search_copy()
			if ELCombatSearch.apply(copy, line.command) and ELCombatSearch._spent(d, copy, line) != 1: return true
	return false

func _save(d: ELDuel, side: int, what: String) -> void:
	if save.is_empty(): return
	saved += 1
	var path := "%s/%s-%s-%d-%d.json" % [save, profile.id, what.replace(":", "_"), d.rng_state & 0xffffff, saved]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"format": "etherlords-duel", "version": 1, "state": d.snapshot(), "found": {"kind": "kept", "side": side, "note": what}}, "", true, true))
	file.close()
