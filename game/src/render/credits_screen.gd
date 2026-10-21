class_name ELCreditsScreen
extends RefCounted
## Credits on the ELFrontMenu canvas.
## First game: paged credits over the CREDITS1..6 pictures. The CR_CAPTION_nn /
## CR_TEXT_nn entries form 16 groups; trailing empty entries and empty groups
## are dropped; one group per page, the testers' group split over two pages;
## titles 30 px, captions 17 px, names wrapped at commas, the block centred
## vertically in the text area. The 1024x768 layout keeps the 800x600 column
## width and font sizes: the 348 px column sits at the left of the 1024 text
## container (542,19)-(984,749); the copyright rectangle is not moved. Keys: Backspace
## or Left = previous page, Esc = close, any other key or a click = next page.
## Second game: T_CREDITS_TEXT_nnn entries (plain, _H header, _1 title, _T/_HT/_1T
## without the gap) scroll upwards inside CreditsScrollBounds while the Type1..4
## pictures cross-fade; any key or click fades out to the main menu.
## Second-game scroll as EL2 runs it: an entry's gap comes before its
## first line; entries are wrapped to the bounds width and set left-aligned at
## the bounds' left edge; lines rise from the bounds' bottom edge (clipped there)
## and the topmost line fades out over 0.22 s once its top is within 10 px of
## the top edge (or its predecessor has left); the screen fades to the menu
## once the last line has gone. At 1024x768 the bounds keep their shifted
## top-left (606,86) but reach 224 px further right and 168 px further down
## (606..975 x 86..657), as the original lays them out (it wraps «Заместитель
## руководителя / проекта» and clips at 657).
## Faces: the first game sets every credits line in Arial
## Bold (30/17 px cells) and the copyright in Arial (15 px cell); the second sets
## plain entries in Arial (20 px cell), headers and titles in Arial Bold (24/32).
## Sizes below are cell heights, drawn at ELFrontMenu.cell_em.

## First game: group table (first, last entry) from the original.
const FIRST_GROUPS := [[0, 4], [5, 13], [14, 19], [20, 25], [26, 30], [31, 37], [38, 46], [47, 55], [56, 57], [58, 59],
	[100, 109], [110, 119], [120, 129], [130, 139], [140, 149], [150, 159]]
## 1024x768 rects: text column (container left, 800 layout width, container
## height) and copyright.
const FIRST_AREA := Rect2(542, 19, 348, 730)
## Copyright: measured on the original at 1024x768 (glyphs 425..903 x 662..688, two lines near the bottom of the page); the
## registry rectangle (265,511) is the 800x600 one and is not where it shows.
const FIRST_COPYRIGHT := Rect2(416, 657, 560, 60)
const FIRST_SPLIT_GROUP := 8
const TEXT_INK := Color("f5b427")
const CAPTION_INK := Color("d6bb88")
## Second game: suffix -> [cell size, gap after, bold].
const SECOND_STYLES := {"": [20, 6, false], "_H": [24, 24, true], "_T": [20, 0, false], "_HT": [24, 0, true], "_1": [32, 32, true], "_1T": [32, 0, true]}
const SECOND_SPEED := 50.3
const SECOND_PICTURE_TIME := 19.7
const SECOND_FADE := 1.0
## Top-line fade (: 0xdc ms, when its top < bounds top + 10).
const SECOND_LINE_FADE := 0.22
const SECOND_FADE_MARGIN := 10.0

var menu: ELFrontMenu
var page := 0
var pages: Array = []
var entries: Array = []
var scroll := 0.0
var clock := 0.0
var closing := -1.0
var view: CreditsView

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func first() -> bool:
	return menu.edition == "el1"

func open() -> void:
	page = 0
	scroll = 0.0
	clock = 0.0
	closing = -1.0
	menu.show_screen("credits")
	menu.play_music("Credits")

# --- First game data ------------------------------------------------------------

static func _entry_text(profile: ELProfile, key: String) -> String:
	if not profile.texts.has(key): return ""
	var value := profile.text(key)
	return "" if value == "-" else value

## Groups after the original trimming: arrays of {caption, text}.
static func first_groups(profile: ELProfile) -> Array:
	var groups: Array = []
	for bounds: Array in FIRST_GROUPS:
		var group: Array = []
		for number in range(int(bounds[0]), int(bounds[1]) + 1):
			var suffix := ("%02d" % number) if number < 100 else str(number)
			group.append({"caption": _entry_text(profile, "CR_CAPTION_" + suffix), "text": _entry_text(profile, "CR_TEXT_" + suffix)})
		while not group.is_empty() and group.back().caption.is_empty() and group.back().text.is_empty(): group.pop_back()
		if not group.is_empty(): groups.append(group)
	return groups

## Pages: {group, entries}. Page p shows group p up to the split group and
## group p - 1 after it; the split group's texts are cut at the first comma
## from their middle (left part, then the rest).
static func first_pages(profile: ELProfile) -> Array:
	var groups := first_groups(profile)
	var result: Array = []
	var count := groups.size() + 1 if groups.size() > FIRST_SPLIT_GROUP else groups.size()
	for index in count:
		var group_index := index if index <= FIRST_SPLIT_GROUP else index - 1
		var shown: Array = []
		for entry: Dictionary in groups[group_index]:
			var copy := entry.duplicate()
			if group_index == FIRST_SPLIT_GROUP and not copy.text.is_empty():
				var cut: int = copy.text.find(",", copy.text.length() / 2)
				if cut >= 0: copy.text = copy.text.substr(0, cut) if index == FIRST_SPLIT_GROUP else copy.text.substr(cut + 1).strip_edges()
			shown.append(copy)
		result.append({"group": group_index, "entries": shown})
	return result

## Greedy wrap at commas; every line but the last keeps its comma.
static func wrap_commas(text: String, font: Font, size_px: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var rest := text.strip_edges()
	while not rest.is_empty():
		var line := rest
		var comma := rest.find(",")
		if comma >= 0 and font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width:
			# The longest prefix ending at a comma that fits (at least the first).
			line = rest.substr(0, comma + 1)
			var next := rest.find(",", comma + 1)
			while next >= 0:
				var longer := rest.substr(0, next + 1)
				if font.get_string_size(longer, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width: break
				line = longer
				next = rest.find(",", next + 1)
		lines.append(line.strip_edges())
		rest = rest.substr(line.length()).strip_edges()
	return lines

## Laid-out lines of one first-game page in the 800x600 area: {text, y, size, color}.
func first_layout(index: int) -> Array:
	var lines: Array = []
	if index < 0 or index >= pages.size(): return lines
	var title_size := 30
	var body_size := 17
	var width := FIRST_AREA.size.x
	var y := 0.0
	for entry: Dictionary in pages[index].entries:
		if entry.text.is_empty():
			# Caption only: a 30 px title; nothing at all: a 10 px gap.
			if entry.caption.is_empty(): y += 10
			else:
				lines.append({"text": entry.caption, "y": y, "size": title_size, "color": TEXT_INK, "bold": true})
				y += 30
		else:
			lines.append({"text": entry.caption, "y": y, "size": body_size, "color": CAPTION_INK, "bold": true})
			y += 17
			for line: String in wrap_commas(entry.text, menu.arial_bold, ELFrontMenu.cell_em(body_size), width):
				lines.append({"text": line, "y": y, "size": body_size, "color": TEXT_INK, "bold": true})
				y += 17
		y += 20
	var height := FIRST_AREA.size.y
	var top := (height - y) * 0.5 if y < height else 0.0
	for line: Dictionary in lines: line.y += top
	return lines

# --- Second game data -----------------------------------------------------------

## Entries in order: {text, size, gap}; the list ends at the first missing number.
static func second_entries(profile: ELProfile) -> Array:
	var result: Array = []
	var number := 1
	while true:
		var found := false
		for suffix: String in SECOND_STYLES:
			var key := "T_CREDITS_TEXT_%03d%s" % [number, suffix]
			if not profile.texts.has(key): continue
			result.append({"key": key, "text": profile.text(key), "size": int(SECOND_STYLES[suffix][0]), "gap": int(SECOND_STYLES[suffix][1]), "bold": bool(SECOND_STYLES[suffix][2])})
			found = true
			break
		if not found: break
		number += 1
	return result

## Scroll bounds on the 1024 canvas: the control's shifted top-left, its far
## edges moved by the 800x600 -> 1024x768 difference (see the header).
func second_bounds() -> Rect2:
	var rect := menu.control_rect("CreditsScrollBounds")
	var far := rect.end - menu.shift("CreditsScrollBounds") + ELFrontMenu.DESIGN - Vector2(800, 600)
	return Rect2(rect.position, far - rect.position)

## Greedy wrap at spaces and after hyphens to `width`; explicit newlines kept.
static func wrap_words(text: String, font: Font, em: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	for paragraph: String in text.split("\n"):
		paragraph = paragraph.strip_edges()
		var line := ""
		var at := 0
		while at < paragraph.length():
			# Next piece: up to and including a space or hyphen.
			var end := at
			while end < paragraph.length() and paragraph[end] != " " and paragraph[end] != "-": end += 1
			var piece := paragraph.substr(at, end + 1 - at)
			at = end + 1
			var candidate := line + piece
			if not line.is_empty() and font.get_string_size(candidate.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, em).x > width:
				lines.append(line.strip_edges())
				line = piece
			else:
				line = candidate
		lines.append(line.strip_edges())
	return lines

## Scroll lines in content coordinates (0 = the bounds' bottom edge at scroll
## 0): {text, y, size, bold}; and the total height. The gap precedes the entry.
func second_layout(width := -1.0) -> Dictionary:
	if width < 0.0: width = second_bounds().size.x
	var lines: Array = []
	var y := 0.0
	for entry: Dictionary in entries:
		y += entry.gap
		var font: Font = menu.arial_bold if entry.bold else menu.arial
		for line: String in wrap_words(str(entry.text), font, ELFrontMenu.cell_em(entry.size), width):
			lines.append({"text": line, "y": y, "size": entry.size, "bold": entry.bold})
			y += entry.size
	return {"lines": lines, "height": y}

## Second game: screen top of a line and its alpha (0 = gone) at this scroll.
func second_line_state(index: int) -> Dictionary:
	var line: Dictionary = view.lines[index]
	var area := view.area
	var top: float = area.end.y + line.y - scroll
	var bottom: float = top + line.size
	if bottom <= area.position.y: return {"top": top, "alpha": 0.0}
	# Fade starts when the line is the topmost one left and its top is within
	# the margin: scroll positions of both events, the later one wins.
	var near := area.end.y + float(line.y) - area.position.y - SECOND_FADE_MARGIN
	var first := 0.0
	if index > 0:
		var previous: Dictionary = view.lines[index - 1]
		first = area.end.y + float(previous.y) + float(previous.size) - area.position.y
	var start := maxf(near, first)
	var alpha := 1.0
	if scroll > start: alpha = clampf(1.0 - (scroll - start) / (SECOND_LINE_FADE * SECOND_SPEED), 0.0, 1.0)
	return {"top": top, "alpha": alpha}

## Background picture (1..6) shown now, the next one and its fade weight.
func picture() -> Dictionary:
	if first():
		var group: int = pages[page].group if page < pages.size() else 0
		return {"type": group % 6 + 1, "next": group % 6 + 1, "weight": 0.0}
	var slot := int(floor(clock / SECOND_PICTURE_TIME))
	var into := clock - slot * SECOND_PICTURE_TIME
	var weight := clampf((into - (SECOND_PICTURE_TIME - SECOND_FADE)) / SECOND_FADE, 0.0, 1.0)
	return {"type": slot % 4 + 1, "next": (slot + 1) % 4 + 1, "weight": weight}

# --- Screen -----------------------------------------------------------------------

func build_screen() -> void:
	view = CreditsView.new()
	view.screen = self
	view.size = ELFrontMenu.DESIGN
	for type in 6:
		var pieces: Array = []
		var group := menu.rows("Credits", ["Type%d" % (type + 1)], ["Res1"])
		group.sort_custom(func(a: Dictionary, b: Dictionary): return ELFrontMenu._layer(a) < ELFrontMenu._layer(b))
		for row: Dictionary in group:
			var piece := menu.cut(row, menu.shift("Credits"))
			if not piece.is_empty(): pieces.append(piece)
		view.pictures.append(pieces)
	menu.canvas.add_child(view)
	menu.labels["credits"] = view
	if first():
		if pages.is_empty(): pages = first_pages(menu.profile)
		page = clampi(page, 0, maxi(0, pages.size() - 1))
		view.lines = first_layout(page)
		view.area = FIRST_AREA
		if page == 0:
			# Wrapping is set before the text so the label keeps its rectangle.
			var copyright := menu._label("copyright", "", FIRST_COPYRIGHT, 15, TEXT_INK, HORIZONTAL_ALIGNMENT_LEFT)
			copyright.add_theme_font_override("font", menu.arial)
			copyright.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			copyright.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			copyright.text = menu.text("CR_COPYRIGHT")
	else:
		if entries.is_empty(): entries = second_entries(menu.profile)
		view.area = second_bounds()
		var layout := second_layout(view.area.size.x)
		view.lines = layout.lines
		view.content_height = layout.height
		# Lines are clipped at the bottom edge of the bounds.
		view.text_layer.clip_contents = true
		view.text_layer.size = Vector2(ELFrontMenu.DESIGN.x, view.area.end.y)
		# No alignment keyword in its FontType: left-aligned, as the original shows it.
		var copyright := menu._label("copyright", "", menu.control_rect("CreditsCopyright"), 16, TEXT_INK, HORIZONTAL_ALIGNMENT_LEFT)
		copyright.add_theme_font_override("font", menu.face_for("CreditsCopyright"))
		copyright.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copyright.text = menu._caption("CreditsCopyright")
		view.set_process(true)
	view.queue_redraw()

func next_page() -> void:
	if page + 1 >= pages.size():
		close()
		return
	page += 1
	menu.show_screen("credits")

func previous_page() -> void:
	if page == 0: return
	page -= 1
	menu.show_screen("credits")

## Key routing while the credits are shown.
func key(event: InputEventKey) -> void:
	if not event.pressed or event.echo: return
	if not first():
		begin_close()
		return
	match event.keycode:
		KEY_ESCAPE: close()
		KEY_BACKSPACE, KEY_LEFT: previous_page()
		_: next_page()

func click() -> void:
	if first(): next_page()
	else: begin_close()

## Second game: the 1 s fade to black before the main menu.
func begin_close() -> void:
	if closing < 0.0: closing = 0.0

## Advances the second game's scroll, pictures and fade-out.
func tick(delta: float) -> void:
	if first() or menu.screen != "credits": return
	clock += delta
	if closing >= 0.0:
		closing += delta
		if closing >= SECOND_FADE:
			close()
			return
	scroll += delta * SECOND_SPEED
	# The last line has left the top: fade out to the menu (end).
	if view != null and closing < 0.0 and scroll >= view.area.size.y + view.content_height: begin_close()
	if view != null:
		view.queue_redraw()
		view.text_layer.queue_redraw()
		view.fade_layer.queue_redraw()

func close() -> void:
	closing = -1.0
	menu.stop_audio()
	# Hosted after the second game's last campaign: back to the host, which
	# shows the main menu.
	if menu.hosted: menu.leave_screen()
	else: menu.show_screen("main")

class CreditsView extends Control:
	var screen: ELCreditsScreen
	var pictures: Array = []
	var lines: Array = []
	var area := Rect2()
	var content_height := 0.0
	var _down := false
	## Second game: the scrolling lines, clipped at the bounds' bottom edge.
	var text_layer := Control.new()
	var fade_layer := Control.new()

	func _init() -> void:
		text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_layer.draw.connect(_draw_scroll)
		add_child(text_layer)
		fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade_layer.draw.connect(_draw_fade)
		add_child(fade_layer)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		fade_layer.size = size

	func _process(delta: float) -> void:
		screen.tick(delta)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _down = true
			elif _down:
				_down = false
				screen.click()
			accept_event()

	func _draw_picture(type: int, alpha: float) -> void:
		if type < 1 or type > pictures.size(): return
		for piece: Dictionary in pictures[type - 1]:
			draw_texture_rect_region(piece.texture, piece.rect, piece.source, Color(1, 1, 1, alpha))

	func _draw() -> void:
		var shown := screen.picture()
		_draw_picture(shown.type, 1.0)
		if shown.weight > 0.0: _draw_picture(shown.next, shown.weight)
		if not screen.first(): return
		for line: Dictionary in lines:
			var font: Font = screen.menu.arial_bold if line.get("bold", false) else screen.menu.arial
			var em := ELFrontMenu.cell_em(line.size)
			var width := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, em).x
			var at := Vector2(area.position.x + (area.size.x - width) * 0.5, area.position.y + float(line.y) + font.get_ascent(em))
			var colour: Color = line.get("color", ELCreditsScreen.TEXT_INK)
			draw_string(font, at + Vector2(1, 1), line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, em, Color(0, 0, 0, 0.6))
			draw_string(font, at, line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, em, colour)

	## Hard-edged copies of the menu fonts: the original draws the scrolling
	## credits without antialiasing (solid strokes).
	var _hard: Dictionary = {}

	func _hard_font(font: Font) -> Font:
		if not _hard.has(font):
			var copy: Font = font.duplicate()
			if copy is SystemFont:
				copy.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				copy.hinting = TextServer.HINTING_NORMAL
			_hard[font] = copy
		return _hard[font]

	func _draw_scroll() -> void:
		if screen.first(): return
		for index in lines.size():
			var line: Dictionary = lines[index]
			var state := screen.second_line_state(index)
			var top: float = state.top
			if state.alpha <= 0.0 or top > area.end.y: continue
			var font: Font = _hard_font(screen.menu.arial_bold if line.get("bold", false) else screen.menu.arial)
			var em := ELFrontMenu.cell_em(line.size)
			# Whole pixels with a solid black shadow, as the original draws
			# (its shadow pixels are pure black).
			var at := Vector2(area.position.x, top + font.get_ascent(em)).round()
			text_layer.draw_string(font, at + Vector2(1, 1), line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, em, Color(0, 0, 0, state.alpha))
			text_layer.draw_string(font, at, line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, em, Color(ELCreditsScreen.TEXT_INK, state.alpha))

	func _draw_fade() -> void:
		if screen.closing >= 0.0:
			fade_layer.draw_rect(Rect2(Vector2.ZERO, fade_layer.size), Color(0, 0, 0, clampf(screen.closing / ELCreditsScreen.SECOND_FADE, 0.0, 1.0)))
