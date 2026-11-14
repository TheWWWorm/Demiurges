extends SceneTree
## Measures what each first-game shop spell is worth to a computer hero: the
## starting book of a random hero of a random colour has its cheapest copies
## replaced by random shop spells of its colour, as the computer's shopping
## does, and two such books fight a computer-vs-computer duel. One line per
## duel names the winner and the bought spells of both sides:
##
##   DUEL winner=<0|1|-1> rounds=<n> | <colour> <card>,<card>,... | <colour> ...
##
## and, before the duels, one line per shop spell:
##
##   CARD <card> <colour> <rarity> <ether cost> <1 for a creature> <name>
##
## tools/first_spell_rating.py turns many such lines into the ratings table
## of game/src/content/first_spell_ratings.gd.
##
##   godot --headless --path game --script ../tools/first_spell_rating.gd -- \
##       [--duels=N] [--seed=N] [--shard=I/N] [--bought=6] [--level=8] [--ai=smart]
##
## Settings are those of duel_ai_bench.gd ("orig", "smart", "smart:...").
## Needs the first game's files (user://profiles.json or --el1=<folder>).

const FACTIONS := ["Red", "Green", "Black", "Blue"]
const ROUND_CAP := 40
const PHASE_CAP := 80

var profile: ELProfile
var smart := true

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	var folder := _arg("el1", "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if stored is Dictionary: folder = String(stored.get("el1", ""))
	profile = ELProfile.new()
	if folder.is_empty() or not profile.mount("el1", folder):
		printerr("Game files are required: pass --el1=<folder>")
		quit(1)
		return
	var text := _arg("ai", "smart")
	smart = text.get_slice(":", 0) != "orig"
	for item: String in (text.get_slice(":", 1) if text.contains(":") else "").split(",", false):
		(ELCombatSearch as Script).set("smart_" + item.get_slice("=", 0), str_to_var(item.get_slice("=", 1)))
	var shard := _arg("shard", "0/1")
	var bought := int(_arg("bought", "6"))
	var level := int(_arg("level", "8"))
	var starts := _starts()
	var pools := _pools()
	for faction: String in FACTIONS:
		print("POOL %s %d spells, %d starting books" % [faction, pools[faction].size(), starts[faction].size()])
		for card: String in pools[faction]:
			var row: Dictionary = profile.table("CombatSpells")[card]
			print("CARD %s %s %s %d %d %s" % [card, faction, row.Rarity, int(row.get("Cost", 0)), 1 if profile.table("CombatCreatures").has(card) else 0, profile.text(str(row.get("Name", card))).replace(" ", "_")])
	var random := RandomNumberGenerator.new()
	for index in int(_arg("duels", "8")):
		random.seed = hash([int(_arg("seed", "1")), index])
		var players: Array = []
		var labels: Array = []
		for side in 2:
			var faction: String = FACTIONS[random.randi() % FACTIONS.size()]
			var book: Array = starts[faction][random.randi() % starts[faction].size()].duplicate()
			# The cheapest copies go first, as when the computer shops.
			var slots: Array = range(book.size())
			slots.sort_custom(func(a: int, b: int): return ELFirstAIEconomy.base_value(profile, book[a]) < ELFirstAIEconomy.base_value(profile, book[b]))
			var left: Array = pools[faction].duplicate()
			var added: Array = []
			for pick in mini(bought, mini(left.size(), slots.size())):
				var card: String = left.pop_at(random.randi() % left.size())
				book[slots[pick]] = card
				added.append(card)
			players.append({"faction": faction, "level": level, "cards": book})
			labels.append("%s %s" % [faction, ",".join(added)])
		var seed_value := int(random.randi() & 0x7fffffff)
		if index % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var result := _play(players, seed_value)
		print("DUEL winner=%d rounds=%d | %s | %s" % [result.winner, result.rounds, labels[0], labels[1]])
	print("DONE")
	quit(0)

## The books computer heroes start with: the level-one, non-quest templates.
func _starts() -> Dictionary:
	var result := {}
	for faction: String in FACTIONS: result[faction] = []
	var rows: Dictionary = profile.table("HeroTemplates")
	for key: String in rows:
		var row: Dictionary = rows[key]
		if str(row.get("Quest", "")) == "Yes" or int(row.get("Level", 1)) != 1 or not result.has(str(row.get("Color", ""))): continue
		var book := ELCatalog.deck(profile, str(row.get("StartDeck", "")))
		if not book.is_empty() and not result[row.Color].has(book): result[row.Color].append(book)
	return result

## Every spell a colour's shops may sell that a duel can play.
func _pools() -> Dictionary:
	var result := {}
	for faction: String in FACTIONS:
		var pool: Array = []
		for card: String in profile.table("CombatSpells"):
			var row: Dictionary = profile.table("CombatSpells")[card]
			if row.get("Color") != faction or row.get("Rarity") not in ["Common", "Rare", "Unique"] or ELCatalog.rule(profile, card).is_empty(): continue
			var probe := ELDuel.new()
			var player := {"faction": faction, "cards": [card]}
			if probe.start(profile, 1, {"players": [player, player]}): pool.append(card)
		result[faction] = pool
	return result

func _play(players: Array, seed_value: int) -> Dictionary:
	var duel := ELDuel.new()
	if not duel.start(profile, seed_value, {"players": players}):
		printerr("Cannot start: " + duel.error)
		return {"winner": -1, "rounds": 0}
	var commands := 0
	var mark := [-1, -1, -1]
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= ROUND_CAP:
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			commands = 0
		commands += 1
		var sides: Array[int] = []
		if smart: sides.append(duel.active_side())
		duel.smart_sides = sides
		var command := ELCombatSearch.think(duel) if commands <= PHASE_CAP else {}
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	return {"winner": duel.winner if duel.phase == ELDuel.Phase.FINISHED else -1, "rounds": duel.round_number}
