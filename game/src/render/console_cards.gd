class_name ELConsoleCards
extends RefCounted
## Card lookup for the developer console's add spell, add creature and add
## enemy (ELGameConsole). A card is named by its code or by its name in
## English or Russian (ELCardNames, beside the installed game's own name), in
## any case, in full or by a part that only one card has. Several cards are
## separated by commas, and a count adds copies: "x3", "×3", "*3" or "3" after
## a card, or "3" / "3x" before it.
##
##   add spell ORSH
##   add spell orc shaman x2, zap
##   add creature 3 орк-шаман

## The most copies one line adds.
const LIMIT := 50
## Match stages, best first: the first that finds anything decides.
const EXACT_CODE := 0
const EXACT_NAME := 1
const PREFIX := 2
const WORDS := 3
const PART := 4

static var _count_after := RegEx.create_from_string("^(.*?)(?:\\s*[xх×*]\\s*|\\s+)(\\d+)$")
static var _count_before := RegEx.create_from_string("^(\\d+)\\s*(?:[xх×*]\\s*|\\s+)(.+)$")

## [{code, names: [shown name, English, Russian], keys: [normalized names]}]
## for the codes of `table` ("CombatSpells" or "CombatCreatures").
static func catalog(duel: ELDuel, table: String) -> Array:
	var codes: Array = duel.profile.table(table).keys()
	codes.sort()
	var rows: Array = []
	for code: String in codes:
		var names := PackedStringArray()
		for name: String in [duel.card_name(code)] + ELCardNames.NAMES.get(code, []):
			if not name.is_empty() and not names.has(name): names.append(name)
		rows.append(entry(code, names if not names.is_empty() else PackedStringArray([code])))
	return rows

static func entry(code: String, names: PackedStringArray) -> Dictionary:
	var keys := PackedStringArray()
	for name: String in names:
		var key := normalize(name)
		if not key.is_empty() and not keys.has(key): keys.append(key)
	return {"code": code.to_upper(), "names": names, "keys": keys}

## Lower case, ё as е, hyphens as spaces, apostrophes dropped, one space
## between words.
static func normalize(text: String) -> String:
	var plain := text.to_lower().replace("ё", "е").replace("’", "").replace("'", "").replace("`", "")
	for mark: String in ["-", "‑", "–", "—", "_", "\t"]: plain = plain.replace(mark, " ")
	return " ".join(plain.split(" ", false))

## One item of a list ("orc shaman x2"): {query, count}. A count of 0 or
## past LIMIT is kept so that the caller can refuse it.
static func split_count(item: String) -> Dictionary:
	var text := item.strip_edges()
	var found := _count_after.search(text)
	if found != null and not found.get_string(1).strip_edges().is_empty():
		return {"query": found.get_string(1).strip_edges(), "count": _number(found.get_string(2))}
	found = _count_before.search(text)
	if found != null:
		return {"query": found.get_string(2).strip_edges(), "count": _number(found.get_string(1))}
	return {"query": text, "count": 1}

static func _number(digits: String) -> int:
	return digits.to_int() if digits.length() <= 4 else LIMIT + 1

## The cards of `query`, best stage first: [stage, [rows]]; [-1, []] when
## nothing matches.
static func find(query: String, rows: Array) -> Array:
	var key := normalize(query)
	if key.is_empty(): return [-1, []]
	var upper := query.strip_edges().to_upper()
	var words := key.split(" ", false)
	var stages: Array = [[], [], [], [], []]
	for row: Dictionary in rows:
		var stage := _stage(row, upper, key, words)
		if stage >= 0: stages[stage].append(row)
	for stage in stages.size():
		if not stages[stage].is_empty(): return [stage, stages[stage]]
	return [-1, []]

static func _stage(row: Dictionary, upper: String, key: String, words: PackedStringArray) -> int:
	if row.code == upper: return EXACT_CODE
	var best := -1
	for name: String in row.keys:
		if name == key: return EXACT_NAME
		var stage := -1
		if name.begins_with(key) or (row.code as String).to_lower().begins_with(key): stage = PREFIX
		elif _starts_words(name.split(" ", false), words): stage = WORDS
		elif name.contains(key): stage = PART
		if stage >= 0 and (best < 0 or stage < best): best = stage
	return best

## Whether every query word begins a different word of the name, in order.
static func _starts_words(name: PackedStringArray, words: PackedStringArray) -> bool:
	var at := 0
	for word: String in words:
		while at < name.size() and not name[at].begins_with(word): at += 1
		if at >= name.size(): return false
		at += 1
	return true

## Suggestions for a partly typed card, best first, at most `limit` rows.
static func suggest(query: String, rows: Array, limit: int) -> Array:
	var key := normalize(query)
	if key.is_empty(): return rows.slice(0, limit)
	var upper := query.strip_edges().to_upper()
	var words := key.split(" ", false)
	var ranked: Array = []
	for row: Dictionary in rows:
		var stage := _stage(row, upper, key, words)
		if stage >= 0: ranked.append([stage, row])
	ranked.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else String(a[1].names[0]).naturalnocasecmp_to(b[1].names[0]) < 0)
	var result: Array = []
	for pair: Array in ranked.slice(0, limit): result.append(pair[1])
	return result

## A card's line in suggestions and replies: "ORSH  —  Orc Shaman / Орк-шаман".
static func caption(row: Dictionary) -> String:
	return "%s  —  %s" % [row.code, " / ".join(row.names)]

## The cards a command's arguments name: {cards: [codes, one per copy],
## error}. Items are separated by commas (or semicolons); an item that names
## no card but is made of codes alone ("ORSH ZAPP") adds each of them.
static func parse(arguments: String, rows: Array) -> Dictionary:
	var cards: Array[String] = []
	var items := arguments.replace(";", ",").split(",", false)
	if items.is_empty() or arguments.strip_edges().is_empty(): return {"cards": cards, "error": "Name a card: its code or its name."}
	for raw: String in items:
		if raw.strip_edges().is_empty(): continue
		# A code is read whole, never as a name followed by a count.
		var item := {"query": raw.strip_edges(), "count": 1} if find(raw, rows)[0] == EXACT_CODE else split_count(raw)
		if item.count < 1 or item.count > LIMIT: return {"cards": cards, "error": "A count must be from 1 to %d." % LIMIT}
		var codes := _resolve(str(item.query), rows)
		if codes.has("error"): return {"cards": cards, "error": codes.error}
		for code: String in codes.codes:
			for i in int(item.count): cards.append(code)
		if cards.size() > LIMIT: return {"cards": [] as Array[String], "error": "At most %d cards at once." % LIMIT}
	if cards.is_empty(): return {"cards": cards, "error": "Name a card: its code or its name."}
	return {"cards": cards, "error": ""}

static func _resolve(query: String, rows: Array) -> Dictionary:
	var found := find(query, rows)
	var matches: Array = found[1]
	if matches.size() == 1: return {"codes": [matches[0].code]}
	# "ORSH ZAPP": codes alone, one card each.
	var words := query.split(" ", false)
	if words.size() > 1 and (matches.is_empty() or found[0] > EXACT_NAME):
		var codes: Array = []
		for word: String in words:
			var exact := find(word, rows)
			if exact[0] != EXACT_CODE: break
			codes.append(exact[1][0].code)
		if codes.size() == words.size(): return {"codes": codes}
	if matches.is_empty(): return {"error": "No card is called \"%s\"." % query}
	var shown := PackedStringArray()
	for row: Dictionary in matches.slice(0, 6): shown.append(caption(row))
	if matches.size() > 6: shown.append("…")
	return {"error": "\"%s\" fits several cards; use a code or more of the name:\n%s" % [query, "\n".join(shown)]}

## Where the item being typed starts in `text` (after the last comma or
## semicolon) and where its card name starts (after a count typed before it).
static func typing(text: String) -> Dictionary:
	var start := maxi(text.rfind(","), text.rfind(";")) + 1
	var item := text.substr(start)
	var lead := item.length() - item.strip_edges(true, false).length()
	var name_at := start + lead
	var count := RegEx.create_from_string("^(\\d+)\\s*(?:[xх×*]\\s*|\\s+)").search(item.strip_edges(true, false))
	if count != null: name_at += count.get_end()
	return {"start": start, "name_at": name_at, "query": text.substr(name_at)}
