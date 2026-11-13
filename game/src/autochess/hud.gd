class_name ELAutochessHud
extends RefCounted
## The autochess interface pieces, after the Cursed Lands autochess HUD: the
## board stays open, text sits on it with an outline, and only the round
## panel, the main buttons, small price plates and the creature inspector have
## a backing. Creatures are shown by their live models wherever the HUD shows
## a creature.

const PAPER := Color("f0eadc")
const GOLD := Color("d6b66f")
const MUTED := Color("b7c0bd")
const ACCENT := Color("9bfff0")
const WIN := Color("4fbf63")
const LOSS := Color("e0525e")
const ETHER := Color("8fd3ff")
const FACTION := {"Red": Color("ed8b74"), "Blue": Color("8fc0ee"), "Green": Color("a5d99a"), "Black": Color("c2a7e6"), "White": Color("efe8da")}
const ALLIANCE := {"chaots": Color("ed8b74"), "kinets": Color("8fc0ee"), "vitals": Color("a5d99a"), "synthets": Color("c2a7e6"), "flyers": Color("e2d08a"), "strikers": Color("f2b36f")}

static var heading_font: Font

static func serif() -> Font:
	if heading_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Liberation Serif", "Times New Roman", "DejaVu Serif", "serif"])
		heading_font = font
	return heading_font

## Price colours: 1 plain, then green, blue, violet and gold.
## The rarity colours of the price tiers (EI's bands, deepened to read on
## the darker Etherlords art): white, green, blue, violet, gold.
static func cost_accent(price: int) -> Color:
	if price <= 1: return Color("e4e0d6")
	if price == 2: return Color("72d47e")
	if price == 3: return Color("5fb2f2")
	if price == 4: return Color("b98cf2")
	return Color("f2b84a")

static func line_accent(line: int) -> Color:
	return cost_accent(ELAutochessRules.tier(line)) if line >= 0 else PAPER

static func style(fill: Color, border := Color("5a624c"), padding := Vector2(10, 8)) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(2)
	result.content_margin_left = padding.x
	result.content_margin_right = padding.x
	result.content_margin_top = padding.y
	result.content_margin_bottom = padding.y
	return result

static func outline(control: Control, size := 4) -> void:
	control.add_theme_color_override("font_outline_color", Color("161616"))
	control.add_theme_constant_override("outline_size", size)
	if control is Button: control.add_theme_constant_override("font_outline_size", size)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	control.add_theme_constant_override("shadow_offset_y", 1)

## Shrinks `control`'s font from `size` until `text` fits `width` (down to
## `smallest`), so long names and translations stay whole.
static func fit(control: Control, text: String, width: float, size: int, smallest := 10) -> void:
	var font := control.get_theme_font("font")
	var chosen := size
	while chosen > smallest and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > width: chosen -= 1
	control.add_theme_font_size_override("font_size", chosen)

static func label(parent: Node, text: String, size := 15, color := PAPER, heading := false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	if heading: result.add_theme_font_override("font", serif())
	outline(result)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null: parent.add_child(result)
	return result

static func wrap(parent: Node, text: String, size := 15, color := PAPER) -> Label:
	var result := label(parent, text, size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

## A dark main button (Start battle, Menu, Shop).
## The profile whose interface sounds the mode plays (set by the screens).
static var sound_profile: ELProfile
static var _sound_players: Array[AudioStreamPlayer] = []
static var _sound_next := 0

## Plays an interface sound of the original game on one of a few channels
## of its own, so a click or a purchase never cuts off an evolution.
static func play_sound(path: String) -> void:
	if path.is_empty() or sound_profile == null or ELUiSounds.volume <= 0.0: return
	var stream := ELAudio.sound(sound_profile, path)
	if stream == null: return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return
	_sound_players = _sound_players.filter(func(player: AudioStreamPlayer) -> bool: return is_instance_valid(player))
	while _sound_players.size() < 6:
		var player := AudioStreamPlayer.new()
		player.name = "AutochessSound%d" % _sound_players.size()
		tree.root.add_child(player)
		_sound_players.append(player)
	# A free channel, or the one that started longest ago.
	var chosen: AudioStreamPlayer = null
	for player in _sound_players:
		if not player.playing:
			chosen = player
			break
	if chosen == null:
		chosen = _sound_players[_sound_next % _sound_players.size()]
		_sound_next += 1
	chosen.stream = stream
	chosen.volume_db = linear_to_db(maxf(0.0001, ELAudio.option_gain(ELUiSounds.volume, sound_profile.id)))
	chosen.play()

static func button(parent: Node, text: String, action: Callable, primary := false) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_ARROW
	var edge := GOLD if primary else Color("777257")
	result.add_theme_stylebox_override("normal", style(Color("1c1f18e8") if primary else Color("202726e8"), edge, Vector2(12, 6)))
	result.add_theme_stylebox_override("hover", style(Color("344248"), GOLD, Vector2(12, 6)))
	result.add_theme_stylebox_override("pressed", style(Color("504a35"), GOLD, Vector2(12, 6)))
	result.add_theme_stylebox_override("hover_pressed", style(Color("504a35"), GOLD, Vector2(12, 6)))
	result.add_theme_stylebox_override("disabled", style(Color("1a201fd0"), Color("4b5143"), Vector2(12, 6)))
	result.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_disabled_color", Color("858b80"))
	# The original click first; an action's own sound then replaces it.
	result.pressed.connect(func(): play_sound(ELUiSounds.DEFAULT))
	if action.is_valid(): result.pressed.connect(action)
	if parent != null: parent.add_child(result)
	return result

static func draw_star(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2 + i * PI / 5
		points.append(at + Vector2.from_angle(angle) * (radius if i % 2 == 0 else radius * 0.45))
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, Color("302819"), 1.0, true)

static func draw_stars(canvas: CanvasItem, at: Vector2, count: int, color: Color, scale := 1.0) -> void:
	for i in clampi(count, 1, 3): draw_star(canvas, at + Vector2(6 + i * 14, 6) * scale, 6.0 * scale, color)

static func centered(canvas: CanvasItem, font: Font, text: String, baseline: Vector2, size: int, color: Color, outline_size := 0) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if outline_size > 0: canvas.draw_string_outline(font, baseline - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, Color("222222"))
	canvas.draw_string(font, baseline - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Stars drawn in a control's corner (offers, reserves, rows).
class Stars extends Control:
	var count := 1
	var color := ELAutochessHud.PAPER
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(44, 14)
	func _draw() -> void:
		ELAutochessHud.draw_stars(self, Vector2.ZERO, count, color)


## A panel with a thin gold frame: the round panel, inspector, notices.
class Frame extends PanelContainer:
	var surface := Color(0.045, 0.06, 0.065, 0.9)
	var edge := Color("716348")
	var accented := false
	func _init() -> void:
		var padding := StyleBoxEmpty.new()
		padding.content_margin_left = 12; padding.content_margin_right = 12
		padding.content_margin_top = 10; padding.content_margin_bottom = 10
		add_theme_stylebox_override("panel", padding)
		resized.connect(queue_redraw)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), surface)
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), edge, false, 2.0 if accented else 1.0)
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(edge, 0.35), false, 1.0)


## The small chamfered plate under an offer: price and alliances.
class Plate extends PanelContainer:
	var accent := ELAutochessHud.PAPER:
		set(value):
			accent = value
			queue_redraw()
	var highlighted := false:
		set(value):
			highlighted = value
			queue_redraw()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var padding := StyleBoxEmpty.new()
		padding.content_margin_left = 9; padding.content_margin_right = 9
		padding.content_margin_top = 3; padding.content_margin_bottom = 3
		add_theme_stylebox_override("panel", padding)
		resized.connect(queue_redraw)
	func _draw() -> void:
		var rect := Rect2(Vector2.ONE, size - Vector2(2, 2))
		var cut := minf(6.0, rect.size.y * 0.25)
		var a := rect.position
		var b := rect.end
		var points := PackedVector2Array([Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut),
			Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])
		var shadow := points.duplicate()
		for i in shadow.size(): shadow[i] += Vector2(0, 2)
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.22))
		draw_colored_polygon(points, Color(0.055, 0.075, 0.09, 0.76 if highlighted else 0.64))
		points.append(points[0])
		draw_polyline(points, accent.lerp(Color.WHITE, 0.35 if highlighted else 0.0), 2.0 if highlighted else 1.5, true)


## Round refresh / level button with a price badge and an experience ring.
class RoundButton extends Button:
	var kind := "refresh"
	var value := ""
	var caption := ""
	var price := -1
	var progress := -1.0
	func _init() -> void:
		custom_minimum_size = Vector2(80, 78)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for event in [mouse_entered, mouse_exited, button_down, button_up]: event.connect(queue_redraw)
	func _draw() -> void:
		var font := get_theme_default_font()
		var center := Vector2(size.x * 0.5, 33)
		var active := not disabled and is_hovered()
		var ink := ELAutochessHud.PAPER if not disabled else ELAutochessHud.MUTED
		draw_circle(center, 28, Color("344248") if active else Color("182321"))
		draw_arc(center, 28, 0, TAU, 64, ELAutochessHud.GOLD if active else Color("69716a"), 2, true)
		if progress >= 0:
			draw_arc(center, 24, -PI / 2, TAU - PI / 2, 64, Color("414b46"), 3, true)
			if progress > 0: draw_arc(center, 24, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 64, ELAutochessHud.GOLD if not disabled else ELAutochessHud.MUTED, 3, true)
		if kind == "refresh":
			# Two curved arrows.
			draw_arc(center, 11, deg_to_rad(200), deg_to_rad(340), 20, ink, 2.2, true)
			draw_arc(center, 11, deg_to_rad(20), deg_to_rad(160), 20, ink, 2.2, true)
			for angle: float in [deg_to_rad(340), deg_to_rad(160)]:
				var tip := center + Vector2.from_angle(angle) * 11
				var along := Vector2.from_angle(angle + PI / 2)
				draw_colored_polygon(PackedVector2Array([tip + along * 5, tip + along.rotated(PI / 2) * 4 - along * 1, tip - along.rotated(PI / 2) * 4 - along * 1]), ink)
		else:
			ELAutochessHud.centered(self, font, value, center + Vector2(0, 10), 27, ink)
		if price >= 0:
			var badge := center + Vector2(22, -23)
			draw_circle(badge, 11, ELAutochessHud.GOLD if not disabled else Color("8a8060"))
			draw_arc(badge, 11, 0, TAU, 32, Color("50462e"), 1, true)
			ELAutochessHud.centered(self, font, str(price), badge + Vector2(0, 5), 14, Color("19211e"))
		ELAutochessHud.centered(self, font, caption, Vector2(size.x * 0.5, 76), 13, ink, 3)


## One recruit offer: the live creature, stars, lock, and a price plate with
## its alliance colours. An offer that completes an evolution pulses with a
## cyan outline and shows ⇧ and its copy count.
class Offer extends Button:
	signal lock_toggled
	var profile: ELProfile
	var figure: ELAutochessFigure
	var plate: Plate
	var price: Label
	var copies: Label
	var traits: HBoxContainer
	var owned: Label
	var marker: Label
	var title: Label
	var stars: Stars
	var lock: Button
	var line := -1
	var rank := 0
	func _init() -> void:
		custom_minimum_size = Vector2(140, 150)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		add_child(box)
		figure = ELAutochessFigure.new()
		figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
		figure.custom_minimum_size.y = 84
		box.add_child(figure)
		plate = Plate.new()
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plate.custom_minimum_size.x = 84
		box.add_child(plate)
		var meta := VBoxContainer.new()
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meta.add_theme_constant_override("separation", 1)
		plate.add_child(meta)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		meta.add_child(row)
		price = ELAutochessHud.label(row, "", 17, ELAutochessHud.PAPER)
		copies = ELAutochessHud.label(row, "", 13, ELAutochessHud.PAPER)
		traits = HBoxContainer.new()
		traits.alignment = BoxContainer.ALIGNMENT_CENTER
		traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
		traits.add_theme_constant_override("separation", 3)
		meta.add_child(traits)
		owned = ELAutochessHud.label(box, "", 12, ELAutochessHud.PAPER)
		owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Always takes its line, so offers with and without copies line up.
		owned.custom_minimum_size.y = 17
		stars = Stars.new()
		stars.position = Vector2(4, 2)
		add_child(stars)
		marker = ELAutochessHud.label(self, "⇧", 23, ELAutochessHud.ACCENT)
		marker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		marker.offset_left = -28; marker.offset_right = -4
		marker.offset_top = 44; marker.offset_bottom = 72
		title = ELAutochessHud.label(self, "", 14, ELAutochessHud.PAPER)
		title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		title.offset_top = 4; title.offset_bottom = 40
		title.offset_left = -14; title.offset_right = 14
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.max_lines_visible = 2
		title.modulate.a = 0
		lock = Button.new()
		lock.focus_mode = Control.FOCUS_NONE
		lock.toggle_mode = true
		lock.flat = true
		lock.custom_minimum_size = Vector2(26, 26)
		lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -28; lock.offset_right = -2; lock.offset_top = 0; lock.offset_bottom = 26
		lock.draw.connect(_draw_lock)
		lock.toggled.connect(func(_on: bool): lock_toggled.emit())
		add_child(lock)
		mouse_entered.connect(func(): title.modulate.a = 1; plate.highlighted = not disabled)
		mouse_exited.connect(func(): title.modulate.a = 0; plate.highlighted = false)

	func _draw_lock() -> void:
		var color := ELAutochessHud.GOLD if lock.button_pressed else Color(ELAutochessHud.MUTED, 0.85 if lock.is_hovered() else 0.55)
		var body := Rect2(Vector2(7, 12), Vector2(12, 9))
		lock.draw_rect(body, color, false, 1.6)
		var center := Vector2(13, 12)
		if lock.button_pressed: lock.draw_arc(center, 4, PI, TAU, 12, color, 1.6, true)
		else: lock.draw_arc(center + Vector2(0, -1), 4, PI, TAU * 0.92, 12, color, 1.6, true)

	func show_offer(data: ELProfile, company: ELAutochessCompany, index: int, represented: Dictionary) -> void:
		profile = data
		var offer: Dictionary = company.shop[index]
		line = int(offer.family)
		rank = int(offer.get("rank", 0))
		var code := ELAutochessRules.form(line, rank)
		figure.show_code(profile, code)
		var tier := ELAutochessRules.tier(line)
		var upgrade := company.shop_completes_upgrade(index)
		disabled = not company.purchase_error(index).is_empty()
		price.text = "◈ %d" % company.offer_cost(offer)
		price.add_theme_color_override("font_color", ELAutochessHud.MUTED if disabled else ELAutochessHud.PAPER)
		var accent := ELAutochessHud.cost_accent(tier)
		plate.accent = accent.lerp(ELAutochessHud.MUTED, 0.55) if disabled else accent
		var matching := company.owned_counts(line)[rank]
		var needed := ELAutochessRules.evolution_copies(line, rank)
		copies.visible = (matching > 0 or upgrade) and needed > 0
		copies.text = "%d/%d" % [mini(matching, needed), needed]
		copies.add_theme_color_override("font_color", ELAutochessHud.ACCENT if upgrade else ELAutochessHud.PAPER)
		for child: Node in traits.get_children(): child.queue_free()
		for key: String in ELAutochessAlliances.traits(profile, line):
			var mark := TextureRect.new()
			mark.texture = ELAutochessAlliances.icon(profile, key)
			mark.custom_minimum_size = Vector2(17, 17)
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.modulate = Color.WHITE if int(represented.get(key, 0)) > 0 else Color(0.62, 0.62, 0.62, 0.8)
			traits.add_child(mark)
		var counts := company.owned_counts(line)
		var parts := PackedStringArray()
		for r in 3:
			if counts[r] > 0: parts.append("%s×%d" % ["★".repeat(r + 1), counts[r]])
		owned.text = "  ".join(parts)
		marker.visible = upgrade
		stars.count = rank + 1
		stars.color = accent
		stars.queue_redraw()
		title.text = ELAutochessRules.title(profile, code)
		ELAutochessHud.fit(title, title.text, size.x + 24, 14, 10)
		figure.modulate = Color(0.78, 0.78, 0.78, 0.8) if disabled else Color.WHITE
		if upgrade: figure.set_glow(ELAutochessHud.ACCENT, 0.95, true)
		elif tier >= 4: figure.set_glow(accent, 0.25, false)
		else: figure.set_glow(Color.WHITE, 0.0, false)
		lock.set_pressed_no_signal(bool(offer.locked))
		lock.queue_redraw()
		lock.disabled = not company.can_shop()


## A reserve: the live creature above a thin slot line.
class Reserve extends Button:
	var figure: ELAutochessFigure
	var stars: Stars
	var slot_line: ColorRect
	var item: TextureRect
	var uid := 0
	var active := false
	func _init() -> void:
		custom_minimum_size = Vector2(96, 120)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_NONE
		for state in ["normal", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		add_theme_stylebox_override("hover", ELAutochessHud.style(Color(0.12, 0.16, 0.17, 0.35), Color(0, 0, 0, 0), Vector2(3, 3)))
		slot_line = ColorRect.new()
		slot_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_line)
		slot_line.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		slot_line.offset_left = 10; slot_line.offset_right = -10
		slot_line.offset_bottom = -2
		figure = ELAutochessFigure.new()
		add_child(figure)
		figure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		figure.offset_top = 14; figure.offset_bottom = -8
		stars = Stars.new()
		stars.position = Vector2(4, 1)
		add_child(stars)
		item = TextureRect.new()
		item.custom_minimum_size = Vector2(24, 24)
		item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(item)
		item.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		item.offset_left = -26; item.offset_right = -2; item.offset_top = 0; item.offset_bottom = 24
	func show_entry(profile: ELProfile, entry: Dictionary, selected: bool, returning: bool) -> void:
		uid = int(entry.get("uid", 0))
		figure.show_code(profile, String(entry.get("code", "")))
		stars.visible = not entry.is_empty()
		if not entry.is_empty():
			stars.count = int(entry.rank) + 1
			stars.color = ELAutochessHud.line_accent(int(entry.family))
			stars.queue_redraw()
		var kind := String(entry.get("item", ""))
		item.texture = ELAutochessArtifacts.icon(profile, kind) if not kind.is_empty() else null
		active = selected if not entry.is_empty() else returning
		# The slot's line in the creature's rarity colour (gold while chosen).
		slot_line.color = ELAutochessHud.GOLD if active else (Color(ELAutochessHud.line_accent(int(entry.family)), 0.75) if not entry.is_empty() else Color(0.72, 0.75, 0.72, 0.32))
		slot_line.offset_top = -4 if active else -3


## An alliance: colour square with the signature creature, the count, and
## threshold pips that fill as different lines join.
class Badge extends Button:
	var key := ""
	var count := 0
	var picture: Texture2D
	func _init() -> void:
		custom_minimum_size = Vector2(70, 52)
		focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
	func _draw() -> void:
		var rule: Dictionary = ELAutochessAlliances.RULES[key]
		var active := ELAutochessAlliances.rank(key, count) > 0
		var ink: Color = ELAutochessHud.ALLIANCE[key]
		var box := Rect2(0, 2, 38, 38)
		draw_rect(box, Color(0.03, 0.04, 0.04, 0.8))
		if picture != null:
			# Kept in proportion (the faction emblems are wider than tall).
			var inner := box.grow(-2)
			var shape := picture.get_size()
			var fit := minf(inner.size.x / maxf(1.0, shape.x), inner.size.y / maxf(1.0, shape.y))
			var drawn := Rect2(inner.get_center() - shape * fit * 0.5, shape * fit)
			draw_texture_rect(picture, drawn, false, Color.WHITE if active else Color(0.55, 0.55, 0.55, 0.8))
		draw_rect(box, ink if active else Color("65706a"), false, 2.0 if active else 1.0)
		var thresholds: Array = rule.thresholds
		var x := 42.0
		for group in thresholds.size():
			var previous := 0 if group == 0 else int(thresholds[group - 1])
			var pips := int(thresholds[group]) - previous
			var height := (36.0 - (pips - 1) * 2.0) / pips
			for pip in pips:
				var r := Rect2(x, 40 - (pip + 1) * height - pip * 2, 4, height)
				draw_rect(r, ink if count > previous + pip else Color("3b403c"))
			x += 6
		ELAutochessHud.centered(self, get_theme_default_font(), str(count), Vector2(19, 52), 12, ELAutochessHud.PAPER, 3)


## "Evolved": the old and new forms side by side with their stats, for a
## few seconds after an evolution.
class Notice extends Frame:
	const DURATION := 3.4
	var profile: ELProfile
	var pending: Array[Dictionary] = []
	var age := 0.0
	var current := {}
	var _content: VBoxContainer
	func _init() -> void:
		super._init()
		surface.a = 0.96
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.x = 300
		hide()
	func present(event: Dictionary) -> void:
		pending.append(event)
		if current.is_empty(): _next()
	func clear() -> void:
		pending.clear()
		current.clear()
		if is_instance_valid(_content): _content.queue_free()
		hide()
	func _next() -> void:
		if is_instance_valid(_content):
			_content.hide()
			_content.queue_free()
		current = {}
		if pending.is_empty():
			hide()
			return
		current = pending.pop_front()
		age = 0.0
		_content = VBoxContainer.new()
		_content.add_theme_constant_override("separation", 6)
		add_child(_content)
		var heading := ELAutochessHud.label(_content, ELAutochessText.t(profile, "Evolved"), 20, ELAutochessHud.GOLD, true)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)
		var line := int(current.family)
		var rank := int(current.rank)
		_figure(row, line, rank - 1, false)
		var arrow := ELAutochessHud.label(row, "→", 24, ELAutochessHud.GOLD)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_figure(row, line, rank, true)
		var before := ELAutochessRules.stats(profile, ELAutochessRules.form(line, rank - 1), ELAutochessRules.tier(line), rank - 1, line)
		var after := ELAutochessRules.stats(profile, ELAutochessRules.form(line, rank), ELAutochessRules.tier(line), rank, line)
		var stats := ELAutochessHud.label(_content, ELAutochessText.t(profile, "Health %d → %d") % [int(before.health), int(after.health)] + "\n" + ELAutochessText.t(profile, "Attack %d → %d") % [roundi(float(before.damage)), roundi(float(after.damage))], 14)
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		show()
	func _figure(parent: Control, line: int, rank: int, upgraded: bool) -> void:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 2)
		parent.add_child(box)
		var stars := Stars.new()
		stars.count = rank + 1
		stars.color = ELAutochessHud.line_accent(line)
		stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(stars)
		var figure := ELAutochessFigure.new()
		figure.custom_minimum_size = Vector2(110, 84)
		box.add_child(figure)
		figure.show_code(profile, ELAutochessRules.form(line, rank))
		if upgraded: figure.act.call_deferred("usummon")
		var caption := ELAutochessHud.wrap(box, ELAutochessRules.title(profile, ELAutochessRules.form(line, rank)), 15, ELAutochessHud.GOLD if upgraded else ELAutochessHud.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.custom_minimum_size = Vector2(110, 40)
	func _process(delta: float) -> void:
		if not visible or current.is_empty(): return
		age += delta
		modulate.a = clampf(minf(age * 4.0, (DURATION - age) * 3.0), 0.0, 1.0)
		if age >= DURATION: _next()


## The three forms of a line with ownership marks.
class Path extends HBoxContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 2)
	func show_path(profile: ELProfile, portraits: ELAutochessPortraits, line: int, counts: Array[int]) -> void:
		for child: Node in get_children(): child.queue_free()
		for rank in 3:
			if rank > 0:
				var arrow := ELAutochessHud.label(self, "›", 14, ELAutochessHud.PAPER)
				arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 0)
			column.tooltip_text = "%s %s · %s" % [ELAutochessRules.title(profile, ELAutochessRules.form(line, rank)), "★".repeat(rank + 1), ELAutochessText.t(profile, "Owned: %d") % counts[rank]]
			add_child(column)
			var picture := TextureRect.new()
			picture.texture = portraits.texture(ELAutochessRules.form(line, rank))
			picture.custom_minimum_size = Vector2(44, 44)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(picture)
			if counts[rank] > 0:
				var mark := ELAutochessHud.label(picture, "✓" + (str(counts[rank]) if counts[rank] > 1 else ""), 12, ELAutochessHud.ACCENT)
				mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
				mark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				mark.grow_vertical = Control.GROW_DIRECTION_BEGIN
			var stars := ELAutochessHud.label(column, "★".repeat(rank + 1), 12, ELAutochessHud.line_accent(line))
			stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## An artifact or spell: its icon cut to a circle (the square art frame
## cropped away) inside a thin ring in its tier colour; gold when chosen.
class ItemCircle extends Button:
	var picture: Texture2D
	## With both set, the icon is resampled for its size on screen.
	var profile: ELProfile
	var kind := ""
	var accent := ELAutochessHud.PAPER
	var chosen := false
	var spare := false
	func _init() -> void:
		custom_minimum_size = Vector2(46, 46)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for event in [mouse_entered, mouse_exited]: event.connect(queue_redraw)
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(center + Vector2(0, 2), radius, Color(0, 0, 0, 0.35))
		draw_circle(center, radius, Color("10161a"))
		var inner := radius - 3.0
		if profile != null and not kind.is_empty():
			# Cut to the circle inside its painted frame, at the pixels it covers.
			var pixels := ceili(inner * 2.0 * get_global_transform_with_canvas().get_scale().x)
			draw_texture_rect(ELAutochessArtifacts.sized_icon(profile, kind, pixels, true), Rect2(center - Vector2.ONE * inner, Vector2.ONE * inner * 2.0), false)
		elif picture != null:
			# The icons carry their own square frame: sample inside it.
			var points := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 40:
				var direction := Vector2.from_angle(TAU * i / 40)
				points.append(center + direction * inner)
				uvs.append(Vector2(0.5, 0.5) + direction * 0.4)
			draw_colored_polygon(points, Color.WHITE, uvs, picture)
		var ring := ELAutochessHud.GOLD if chosen else accent.lerp(Color.WHITE, 0.25) if is_hovered() else accent
		draw_arc(center, radius - 1.5, 0, TAU, 48, Color("15110b"), 4.0, true)
		draw_arc(center, radius - 1.5, 0, TAU, 48, ring, 3.0 if chosen else 2.0, true)
		if spare: draw_circle(center + Vector2(radius * 0.72, -radius * 0.72), 4.0, ELAutochessHud.ACCENT)
