class_name ELWikiHtml
extends RefCounted
## Small offline HTML reader for wiki articles (as the EI remake's WikiHtml):
## the escaped subset written by tools/build_wiki.py and ELWikiCatalog (h1-h3,
## p, ul/ol/li, table, th/td, strong/b, em/i, code, a; `p.note`, `p.games`,
## `td.changed` and the map-object galleries `div.objects` of
## `figure data-object` with a figcaption) becomes RichTextLabel BBCode. An
## object becomes an `object:<game>/<id>` link that shows its model. Nothing is
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
## The map-object links of a gallery line.
const OBJECTS := "9fc3a0"

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
	var objects := false
	var object_count := 0
	var object_link := false
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
				"div":
					objects = parser.get_named_attribute_value_safe("class") == "objects"
					object_count = 0
					if objects: out += "[color=#%s]▸ [/color]" % OBJECTS
				"figure":
					var object := parser.get_named_attribute_value_safe("data-object")
					object_link = objects and not object_id(object).is_empty()
					if object_link:
						if object_count > 0: out += "[color=#%s]  ·  [/color]" % OBJECTS
						out += "[url=object:%s]" % object
						object_count += 1
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
				"figure":
					if object_link: out += "[/url]"
					object_link = false
				"div":
					if objects: out += "\n\n"
					objects = false
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

## The page `html` with its `!text` placeholders (`p.gametext`, see
## tools/build_wiki.py) replaced by those texts of the installed games, one
## note paragraph per line, escaped; a text the games lack is left out.
static func fill_game_texts(html: String, profiles: Dictionary) -> String:
	if not "class=\"gametext\"" in html: return html
	var tag := RegEx.create_from_string("<p class=\"gametext\" data-text=\"(el[12])/([A-Za-z0-9_]+)\"></p>")
	var out := ""
	var at := 0
	for found: RegExMatch in tag.search_all(html):
		out += html.substr(at, found.get_start() - at)
		at = found.get_end()
		var profile: ELProfile = profiles.get(found.get_string(1))
		if profile == null or not profile.texts.has(found.get_string(2)): continue
		for line: String in str(profile.texts[found.get_string(2)]).split("
"):
			if line.strip_edges().is_empty(): continue
			out += "<p class=\"note\">%s</p>" % line.strip_edges().xml_escape()
	return out + html.substr(at)

## The map object ("<game>/<Table>/<row>") of an `object:` link or a
## `data-object` value, or "" for anything else.
static func object_id(url: String) -> String:
	var id := url.trim_prefix("object:")
	var check := RegEx.create_from_string("^el[12]/[A-Za-z]+/[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@-]+)*$")
	return id if check.search(id) != null else ""

static func _external(url: String) -> bool:
	if not url.begins_with("https://"): return false
	for c: String in ["[", "]", '"', "'", "<", ">", " ", "\n", "\r", "\t", "\\"]:
		if c in url: return false
	return true
