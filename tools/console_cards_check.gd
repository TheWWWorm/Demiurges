extends SceneTree
## Checks how the developer console's add spell, add creature and add enemy
## read their cards (ELConsoleCards): codes as before, English and Russian
## names in any case, a part of a name only one card has, counts ("x3", "3"),
## several cards separated by commas, the refusals, and the completion of the
## card being typed. With installed game files (user://profiles.json or
## --el1=/--el2=) every card is also found by each of its names, and cards
## named in a line reach the hand and the battlefield.
##
##   godot --headless --path game --script ../tools/console_cards_check.gd [-- --el1=<folder> --el2=<folder>]

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures: Array[String] = []
var checks := 0

func check(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures.append(what)
		printerr("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _rows() -> Array:
	return [
		ELConsoleCards.entry("ORSH", PackedStringArray(["Орк-шаман", "Orc Shaman"])),
		ELConsoleCards.entry("ORWR", PackedStringArray(["Орк-воин", "Orc Warrior"])),
		ELConsoleCards.entry("ZAPP", PackedStringArray(["Электрошок", "Zap"])),
		ELConsoleCards.entry("FRBL", PackedStringArray(["Огненный Шар", "Fireball"])),
		ELConsoleCards.entry("SNVN", PackedStringArray(["Змеиный яд", "Snake's Venom"])),
		ELConsoleCards.entry("HEAL", PackedStringArray(["Лечение", "Healing"])),
		ELConsoleCards.entry("HEA2", PackedStringArray(["Лечение", "Healing"])),
		ELConsoleCards.entry("WRSP", PackedStringArray(["Призрак-воин", "Warrior Spirit"])),
		ELConsoleCards.entry("ЁЖИК", PackedStringArray(["Ёжик"])),
	]

func _cards(line: String, rows: Array) -> Array:
	var parsed := ELConsoleCards.parse(line, rows)
	return Array(parsed.cards) if str(parsed.error).is_empty() else ["error: " + str(parsed.error)]

func _run() -> void:
	var rows := _rows()
	# Names are compared without case, ё, hyphens or apostrophes.
	check(ELConsoleCards.normalize("  Орк-Шаман ") == "орк шаман", "names lose case and hyphens")
	check(ELConsoleCards.normalize("Snake’s  Venom") == "snakes venom", "names lose apostrophes and doubled spaces")
	check(ELConsoleCards.normalize("Ёжик") == "ежик", "ё reads as е")
	# Codes keep working, in any case.
	check(_cards("ORSH", rows) == ["ORSH"], "a code adds its card")
	check(_cards("orsh", rows) == ["ORSH"], "a code is read in any case")
	check(_cards("ORSH ZAPP", rows) == ["ORSH", "ZAPP"], "codes separated by spaces add each card")
	# Names in both languages, whole or in part.
	check(_cards("Orc Shaman", rows) == ["ORSH"], "an English name adds its card")
	check(_cards("орк-шаман", rows) == ["ORSH"], "a Russian name adds its card")
	check(_cards("орк шаман", rows) == ["ORSH"], "a Russian name without its hyphen")
	check(_cards("огненный шар", rows) == ["FRBL"], "a Russian name in lower case")
	check(_cards("FIREBALL", rows) == ["FRBL"], "an English name in upper case")
	check(_cards("fire", rows) == ["FRBL"], "a unique beginning of a name")
	check(_cards("o sha", rows) == ["ORSH"], "beginnings of the name's words")
	check(_cards("шаман", rows) == ["ORSH"], "a unique part of a name")
	check(_cards("snakes venom", rows) == ["SNVN"], "a name without its apostrophe")
	check(_cards("ежик", rows) == ["ЁЖИК"], "е finds ё")
	check(_cards("zap", rows) == ["ZAPP"], "a whole name wins over longer names it begins")
	# Counts and lists.
	check(_cards("orc shaman x3", rows) == ["ORSH", "ORSH", "ORSH"], "x3 after a name adds three copies")
	check(_cards("ORSH×2", rows) == ["ORSH", "ORSH"], "×2 after a code")
	check(_cards("ORSH *2", rows) == ["ORSH", "ORSH"], "*2 after a code")
	check(_cards("zap 2", rows) == ["ZAPP", "ZAPP"], "a number after a name")
	check(_cards("2 zap", rows) == ["ZAPP", "ZAPP"], "a number before a name")
	check(_cards("2x fireball", rows) == ["FRBL", "FRBL"], "2x before a name")
	check(_cards("электрошок х2", rows) == ["ZAPP", "ZAPP"], "a Cyrillic х as the count's x")
	check(_cards("orc shaman x2, zap, огненный шар", rows) == ["ORSH", "ORSH", "ZAPP", "FRBL"], "commas separate cards, in order")
	check(_cards("zap; fireball", rows) == ["ZAPP", "FRBL"], "semicolons separate cards too")
	check(_cards("zap,, fireball,", rows) == ["ZAPP", "FRBL"], "empty items are skipped")
	# Refusals.
	check(_cards("orc", rows)[0].begins_with("error: \"orc\" fits several cards") and "ORSH" in _cards("orc", rows)[0] and "ORWR" in _cards("orc", rows)[0], "an ambiguous name lists its cards")
	check(_cards("healing", rows)[0].begins_with("error: \"healing\" fits several"), "two cards of one name ask for a code")
	check(_cards("HEA2", rows) == ["HEA2"], "a code picks one of two cards of one name")
	check(_cards("nothing like it", rows)[0] == "error: No card is called \"nothing like it\".", "an unknown name is refused")
	check(_cards("zap x0", rows)[0].begins_with("error: A count must be"), "a count of 0 is refused")
	check(_cards("zap x51", rows)[0].begins_with("error: A count must be"), "a count past the limit is refused")
	check(_cards("zap x30, fireball x30", rows)[0].begins_with("error: At most"), "a line adds at most the limit")
	check(_cards(" ", rows)[0].begins_with("error: Name a card"), "an empty line asks for a card")
	check(_cards("zap, nothing", rows)[0].begins_with("error: No card"), "one unknown card refuses the whole line")
	# Completion of the item being typed.
	var typed := ELConsoleCards.typing("zap x2, 3 orc s")
	check(typed.query == "orc s" and "zap x2, 3 orc s".left(typed.name_at) == "zap x2, 3 ", "completion reads the last item after its count")
	check(ELConsoleCards.typing("орк").query == "орк" and ELConsoleCards.typing("орк").name_at == 0, "completion of a first item")
	var offered := ELConsoleCards.suggest("orc", rows, 12).map(func(row): return row.code)
	check(offered == ["ORWR", "ORSH"], "completion offers every card the name fits, by name")
	check(ELConsoleCards.suggest("шаман", rows, 12).map(func(row): return row.code) == ["ORSH"], "completion by part of a Russian name")
	check(ELConsoleCards.suggest("", rows, 3).size() == 3, "an empty name offers the first cards")
	check(ELConsoleCards.caption(rows[0]) == "ORSH  —  Орк-шаман / Orc Shaman", "a suggestion shows the code and both names")
	# The checked-in names of both games.
	check(ELCardNames.NAMES.get("ORSH") == ["Orc Shaman", "Орк-шаман"], "the card names know the Orc Shaman in both languages")
	check(ELCardNames.NAMES.size() > 300, "the card names cover both games")
	_installed()
	print("console cards check: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _arg(name: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.get_slice("=", 1)
	return ""

func _installed() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for game: String in ["el1", "el2"]:
		var folder := _arg(game)
		if folder.is_empty() and saved is Dictionary: folder = String(saved.get(game, ""))
		var profile := ELProfile.new()
		if folder.is_empty() or not profile.mount(game, folder):
			print("SKIP: no files of %s" % game)
			continue
		var duel: ELDuel = Fixtures.build(profile, {"heroes": [{"hand": []}, {"hand": []}]})
		if duel == null:
			print("SKIP: no puzzle position for %s" % game)
			continue
		for table: String in ["CombatSpells", "CombatCreatures"]:
			var rows := ELConsoleCards.catalog(duel, table)
			var lost: Array[String] = []
			for row: Dictionary in rows:
				for name: String in row.names:
					var shared := rows.filter(func(other): return ELConsoleCards.normalize(name) in other.keys).size() > 1
					var found := ELConsoleCards.parse(name, rows)
					if not shared and Array(found.cards) != [row.code]: lost.append("%s %s" % [row.code, name])
			check(lost.is_empty(), "%s %s: every card is found by each of its names%s" % [game, table, "" if lost.is_empty() else " (%s)" % ", ".join(lost.slice(0, 5))])
		var spells := ELConsoleCards.catalog(duel, "CombatSpells")
		var creatures := ELConsoleCards.catalog(duel, "CombatCreatures")
		var english: String = ELCardNames.NAMES.ORSH[0]
		var russian: String = ELCardNames.NAMES.ORSH[1]
		var parsed := ELConsoleCards.parse("%s x2, %s" % [english.to_lower(), russian.to_upper()], spells)
		check(Array(parsed.cards) == ["ORSH", "ORSH", "ORSH"], "%s: both names of the Orc Shaman card" % game)
		var hand := (duel.heroes[0].hand as Array).size()
		for code: String in parsed.cards:
			check(duel.console_action({"kind": "console", "side": 0, "op": "spell", "card": code}), "%s: %s reaches the hand" % [game, code])
		check((duel.heroes[0].hand as Array).size() == hand + 3, "%s: three cards reach the hand" % game)
		var army := duel.army(1).size()
		for code: String in ELConsoleCards.parse("2 " + russian, creatures).cards:
			duel.console_action({"kind": "console", "side": 1, "op": "creature", "card": code})
		check(duel.army(1).size() == army + 2, "%s: two creatures are summoned" % game)
