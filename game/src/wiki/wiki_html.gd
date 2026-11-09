class_name ELWikiHtml
extends RefCounted
## Small offline HTML reader for wiki articles (as the EI remake's WikiHtml):
## the escaped subset written by tools/build_wiki.py and ELWikiCatalog (h1-h3,
## p, ul/ol/li, table, th/td, strong/b, em/i, code, a; `p.note`, `p.games` and
## `td.changed`) becomes RichTextLabel BBCode. Nothing is
## executed or fetched. Text brackets are escaped, so article text can never
## open a BBCode tag. Internal links stay `wiki://<page>`; https:// links are
## kept for the reader to open in the system browser.

const HEADING := "d6bb88"
const NOTE := "c8b48e"
const LINE := "4a3c2c"
const HEAD_CELL := "2f261d"
## Cells with a value Etherlords II changed, and the "which games" line.
const CHANGED_CELL := "4a3516"
const CHANGED := "ffd88a"
const GAMES := "9fc3a0"

static func to_bbcode(html: String, scale := 1.0) -> String:
	var parser := XMLParser.new()
	# The page is a sequence of elements: give the parser one root.
	if parser.open_buffer(("<page>" + html + "</page>").to_utf8_buffer()) != OK: return ""
	var out := ""
	var lists: Array[String] = []
	var anchors: Array[bool] = []
	var note := false
	var games := false
	var changed := false
	var first_cell := false
	while parser.read() == OK:
		var type := parser.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var tag := parser.get_node_name().to_lower()
			match tag:
				"h1": out += "[font_size=%d][b][color=#%s]" % [roundi(38 * scale), HEADING]
				"h2": out += "[font_size=%d][b][color=#%s]" % [roundi(29 * scale), HEADING]
				"h3": out += "[font_size=%d][b]" % roundi(23 * scale)
				"p":
					note = parser.get_named_attribute_value_safe("class") == "note"
					games = parser.get_named_attribute_value_safe("class") == "games"
					if note: out += "[indent][color=#%s][i]" % NOTE
					if games: out += "[color=#%s][b]" % GAMES
				"strong", "b": out += "[b]"
				"em", "i": out += "[i]"
				"code": out += "[code]"
				"br": out += "\n"
				"ul":
					lists.append("ul")
					out += "[ul]"
				"ol":
					lists.append("ol")
					out += "[ol type=1]"
				"li": first_cell = false
				"table":
					var columns := clampi(parser.get_named_attribute_value_safe("data-columns").to_int(), 1, 8)
					out += "[table=%d]" % columns
				"td":
					changed = parser.get_named_attribute_value_safe("class") == "changed"
					if changed: out += "[cell border=#%s bg=#%s padding=10,5,10,5][color=#%s]" % [LINE, CHANGED_CELL, CHANGED]
					else: out += "[cell border=#%s padding=10,5,10,5]" % LINE
				"th": out += "[cell border=#%s bg=#%s padding=10,5,10,5][b][color=#%s]" % [LINE, HEAD_CELL, HEADING]
				"a":
					var href := parser.get_named_attribute_value_safe("href")
					var allowed := not key_from_url(href).is_empty() or _external(href)
					anchors.append(allowed)
					if allowed: out += "[url=%s]" % href
		elif type == XMLParser.NODE_ELEMENT_END:
			match parser.get_node_name().to_lower():
				"h1", "h2": out += "[/color][/b][/font_size]\n"
				"h3": out += "[/b][/font_size]\n"
				"p":
					if note: out += "[/i][/color][/indent]"
					if games: out += "[/b][/color]"
					note = false
					games = false
					out += "\n\n"
				"strong", "b": out += "[/b]"
				"em", "i": out += "[/i]"
				"code": out += "[/code]"
				"li": out += "\n"
				"ul", "ol":
					if not lists.is_empty(): lists.pop_back()
					out = out.trim_suffix("\n") + ("[/ul]" if parser.get_node_name() == "ul" else "[/ol]") + "\n\n"
				"table": out += "[/table]\n\n"
				"td":
					out += "[/color][/cell]" if changed else "[/cell]"
					changed = false
				"th": out += "[/color][/b][/cell]"
				"a":
					if not anchors.is_empty() and anchors.pop_back(): out += "[/url]"
		elif type == XMLParser.NODE_TEXT:
			out += parser.get_node_data().replace("[", "[lb]")
	return out.strip_edges()

## The page name of an internal `wiki://<page>` link, or "" for anything else.
static func key_from_url(url: String) -> String:
	if not url.begins_with("wiki://"): return ""
	var key := url.trim_prefix("wiki://")
	# Generated names are lower-case words joined by "-"; anything else could
	# break out of the RichTextLabel url tag.
	var check := RegEx.create_from_string("^[a-z0-9]+(-[a-z0-9]+)*$")
	return key if check.search(key) != null else ""

static func _external(url: String) -> bool:
	if not url.begins_with("https://"): return false
	for c: String in ["[", "]", '"', "'", "<", ">", " ", "\n", "\r", "\t", "\\"]:
		if c in url: return false
	return true
