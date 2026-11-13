extends SceneTree
## Headless check that the map's status line has Russian texts (ELRemakeText):
## the notices the director, the strategy rules and the map view show when a
## route, an order or a day end is refused or announced, read from the code
## that sets them, and the lines built with a name or a list.
##
##   godot --headless --path game --script ../tools/map_notice_text_check.gd
##
## A notice counts as untranslated when its Russian is the same English text.
## It needs no game files and writes nothing.

var failures: Array[String] = []

const FILES := ["content/adventure_director.gd", "content/strategy.gd", "content/interception.gd", "render/adventure_view.gd"]
## How a notice is set in the code; the text follows in quotes.
const LEADS := ["notice = ", "notice.text = ", "_remark(", "ROUTE_NOTICE := ", "BATTLE_REFUSED := "]
## Starts of lines finished with a name or a list, checked below as built.
const BUILT := ["Not usable in battle yet: ", "Resolving ", "Captured ", "Collected ", "Mine production · ", "%s entered the %s."]
## Faults of a scenario script, kept in English for bug reports.
const DIAGNOSTICS := ["Missing actor in scenario command: ", "Missing destination in scenario command.",
	"Scenario command calls an unknown function: ", "Unsupported scenario command: "]

var _cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
var _latin := RegEx.create_from_string("[A-Za-z]{2,}")

func check(ok: bool, what: String) -> void:
	if not ok: failures.append(what)

func _initialize() -> void:
	OS.set_environment("DEMIURGES_LANGUAGE", "ru")
	var quote := char(34)
	var seen := {}
	for file: String in FILES:
		var source := FileAccess.get_file_as_string("res://src/" + file)
		check(not source.is_empty(), "%s could not be read" % file)
		for row: String in source.split("\n"):
			for lead: String in LEADS:
				var at := row.find(lead + quote)
				if at < 0: continue
				var from := at + lead.length() + 1
				var to := row.find(quote, from)
				if to <= from: continue
				var text := row.substr(from, to - from)
				if seen.has(text) or text in BUILT or text in DIAGNOSTICS or _latin.search(text) == null: continue
				seen[text] = true
				check(ELRemakeText.russian(text) != text, "no Russian for \"%s\" (%s)" % [text, file])
	check(seen.size() >= 20, "only %d notices were found in the code" % seen.size())
	check(seen.has("This route enters a guarded area. The hero will stop for combat."), "the guarded-route notice was not found")
	# Lines built with a name or a list: the fixed part is Russian, the name stays.
	for built: Array in [
		["Not usable in battle yet: Rod, Ring", "Rod, Ring"],
		["Resolving movement…", ""], ["Resolving combat…", ""], ["Resolving use…", ""],
		["Captured Сапфировая шахта", "Сапфировая шахта"],
		["Collected 3 Чёрный жемчуг", "3 Чёрный жемчуг"],
		["Mine production · 3 Чёрный жемчуг", "3 Чёрный жемчуг"],
		["Алина entered the форт.", "Алина"]]:
		var shown := ELRemakeText.russian(built[0])
		check(shown != built[0] and _cyrillic.search(shown) != null, "no Russian for \"%s\"" % built[0])
		check(str(built[1]).is_empty() or shown.contains(built[1]), "\"%s\" lost its name: \"%s\"" % [built[0], shown])
		var rest := shown.replace("Rod, Ring", "")
		check(_latin.search(rest) == null, "English left in \"%s\"" % shown)
	for failure in failures: print("FAIL: " + failure)
	print("MAP NOTICES: %d notices, %d failure(s)" % [seen.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
