class_name ELRoundEndDuelView
extends Control
## Second-game round-end duel screen (CRoundEndDuel, Controls
## "RoundEndDuelScreen") in the read-only form the replay player opens from its
## Inventory button (with the replay flag):
## hero name, portrait, life and level, specialisation, five skills, two rows
## of artifacts, the reserve ("bag", 8x5 cells scrolled by row) and the
## 16-slot active deck, with Close in place of OK and Surrender.
## Close (0x1420) keeps nothing and reports back to the player, which then
## shows the other hero. Cards and artifacts show their tooltips.
## The panel is centred like the hero bag screen (InventoryScreen shift
## 112,14); its own registry row carries no shift for 1024x768.

signal closed

const DESIGN := Vector2(1024, 768)
const PANEL := "RoundEndDuelScreen"
const OFFSET := Vector2(112, 14)
const CELL := Vector2(53, 52)
const ICON := Vector2(50, 50)
const INSET := Vector2(2, 1)
const BAG_COLUMNS := 8
const BAG_ROWS := 5
const DECK_COLUMNS := 8
const DECK_SLOTS := 16
const ARTIFACT_COLUMNS := 5
const TAN := Color8(0xd6, 0xbb, 0x88)
const WHITE := Color(1, 1, 1)
const HEADERS := ["RED_HdrHero", "RED_HdrLife", "RED_HdrLevel", "RED_HdrSpec", "RED_HdrSkills", "RED_HdrArtifacts", "RED_HdrBag", "RED_HdrSpells", "RED_HdrDeck"]
const BUTTONS := ["RED_CloseBtn", "RED_DropBtn", "RED_ScrollUp1", "RED_ScrollDown1"]

var profile: ELProfile
## The shown hero: the battle's hero record (deck, skills, artifacts, ...).
var hero: Dictionary = {}
var bag: Array[String] = []
var deck: Array[String] = []
var top_row := 0
var canvas: Control
var surface: Control
var labels: Dictionary = {}
var buttons: Dictionary = {}
var serif_bold: Font
var _paths: Dictionary = {}
var _controls: Dictionary = {}
var _rows: Dictionary = {}
var _pieces: Array[Dictionary] = []

## Builds the screen for one hero. `reserve` is {code: count}; `title` the
## hero's name. Returns false when the original art is missing.
func build(source: ELProfile, shown: Dictionary, reserve: Dictionary, title: String) -> bool:
	profile = source
	hero = shown
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		_paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("Controls").values(): _controls[str(row.get("Name", ""))] = row
	for value: Variant in profile.table("CutParts").values():
		var row: Dictionary = value
		var masks: Variant = row.get("Msk", [])
		var copy := row.duplicate()
		copy.masks = masks if masks is Array else ([] if masks == null or str(masks) == "None" else [masks])
		var control := str(row.get("Ctrl", ""))
		if control == PANEL or control in BUTTONS:
			if not _rows.has(control): _rows[control] = []
			_rows[control].append(copy)
	if not _rows.has(PANEL) or not _controls.has(PANEL): return false
	# Type1 tiles carry the artifact cells (Type2 is the same frame without them).
	for row: Dictionary in _rows[PANEL]:
		if row.masks.has("Type2"): continue
		var piece := cut(row, OFFSET)
		if not piece.is_empty(): _pieces.append(piece)
	var cards: Array = shown.get("deck", [])
	for index in cards.size():
		if index < DECK_SLOTS: deck.append(str(cards[index]))
		else: bag.append(str(cards[index]))
	var codes: Array = reserve.keys()
	codes.sort()
	for code: Variant in codes:
		for copy in int(reserve[code]): bag.append(str(code))
	name = "RoundEndDuelScreen"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bold := SystemFont.new()
	# Arial Bold: RoundEndDuelScreen controls name no Times face.
	bold.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	bold.font_weight = 700
	serif_bold = bold
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = DESIGN
	add_child(canvas)
	surface = Surface.new()
	surface.view = self
	surface.name = "Surface"
	surface.size = DESIGN
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.tooltip_text = " "
	canvas.add_child(surface)
	for control: String in HEADERS:
		var align := HORIZONTAL_ALIGNMENT_RIGHT if control in ["RED_HdrLife", "RED_HdrLevel"] else HORIZONTAL_ALIGNMENT_CENTER
		_label(control, caption(control), 17, align, TAN)
	_label("RED_HdrHeroName", title, 18, HORIZONTAL_ALIGNMENT_CENTER, TAN)
	_label("RED_LifeText", str(int(shown.get("maximum", shown.get("health", 0)))), 17, HORIZONTAL_ALIGNMENT_CENTER, WHITE)
	_label("RED_LevelText", str(int(shown.get("level", 1))), 17, HORIZONTAL_ALIGNMENT_CENTER, WHITE)
	_label("RED_ActiveSpec", spec_name(str(shown.get("spec", "NONE"))), 17, HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	var skills: Array = shown.get("skills", {}).keys()
	for index in 5:
		var text := ""
		if index < skills.size():
			var code := str(skills[index])
			text = profile.text(str(ELHeroSkills.definition(profile, code, int(shown.skills[code])).get("Name", code)))
		_label("RED_Skill%d" % (index + 1), text, 16, HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	for control: String in BUTTONS:
		var button := PieceButton.make(self, control)
		var key := str(_controls.get(control, {}).get("ToolTip", ""))
		button.tooltip_text = "" if key.is_empty() else profile.text(key)
		canvas.add_child(button)
		buttons[control] = button
	buttons.RED_CloseBtn.pressed.connect(func(): closed.emit())
	# Choosing another specialisation would be discarded by Close; the remake
	# leaves the drop button disabled instead of offering a list with no effect.
	buttons.RED_DropBtn.disabled = true
	buttons.RED_ScrollUp1.pressed.connect(scroll_bag.bind(-1))
	buttons.RED_ScrollDown1.pressed.connect(scroll_bag.bind(1))
	_refresh_scroll()
	resized.connect(_layout)
	_layout()
	return true

func caption(control: String) -> String:
	return profile.text(str(_controls.get(control, {}).get("Text", "Ctrl" + control))).strip_edges()

func spec_name(code: String) -> String:
	if code == "NONE" or code.is_empty(): return ""
	return profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Name", code)))

func _label(control: String, value: String, font_size: int, align: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	label.name = control
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", serif_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := design(control)
	label.position = rect.position
	label.size = rect.size
	canvas.add_child(label)
	labels[control] = label
	return label

func cut(row: Dictionary, offset := Vector2.ZERO) -> Dictionary:
	var texture := profile.texture(_paths.get(row.get("Txt", ""), ""))
	if texture == null: return {}
	return {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH), "rect": Rect2(Vector2(row.ScrL, row.ScrT) + offset, Vector2(row.TxtW, row.TxtH))}

func design(control: String) -> Rect2:
	var row: Dictionary = _controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + OFFSET, Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _layout() -> void:
	if canvas == null or size.y <= 0: return
	var factor := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	canvas.scale = Vector2(factor, factor)
	canvas.position = ((size - DESIGN * factor) * 0.5).floor()
	queue_redraw()
	surface.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))

func scroll_bag(delta: int) -> void:
	top_row = clampi(top_row + delta, 0, _last_row())
	_refresh_scroll()
	surface.queue_redraw()

func _last_row() -> int:
	return maxi(0, ceili(bag.size() / float(BAG_COLUMNS)) - BAG_ROWS)

func _refresh_scroll() -> void:
	buttons.RED_ScrollUp1.disabled = top_row <= 0
	buttons.RED_ScrollDown1.disabled = top_row >= _last_row()

## Canvas rectangle of a bag item (empty when scrolled out), deck slot or artifact.
func cell_rect(zone: String, index: int) -> Rect2:
	match zone:
		"bag":
			var row := index / BAG_COLUMNS - top_row
			if row < 0 or row >= BAG_ROWS: return Rect2()
			return Rect2(design("RED_BagBounds").position + INSET + Vector2(index % BAG_COLUMNS, row) * CELL, ICON)
		"deck": return Rect2(design("RED_ASpellsBounds1").position + INSET + Vector2(index % DECK_COLUMNS, index / DECK_COLUMNS) * CELL, ICON)
		"artifact": return Rect2(design("RED_ArtifactsBounds1").position + INSET + Vector2(index % ARTIFACT_COLUMNS, index / ARTIFACT_COLUMNS) * CELL, ICON)
	return Rect2()

## [zone, index] under a canvas point; index -1 for an empty cell.
func hit(at: Vector2) -> Array:
	for zone: String in ["bag", "deck", "artifact"]:
		var count: int = {"bag": bag.size(), "deck": deck.size(), "artifact": artifacts().size()}[zone]
		for index in count:
			if cell_rect(zone, index).has_point(at): return [zone, index]
	return ["", -1]

func artifacts() -> Array:
	var items: Array = hero.get("artifacts", [])
	return items.slice(0, 2 * ARTIFACT_COLUMNS)

func draw_surface(target: Control) -> void:
	for piece: Dictionary in _pieces: target.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	_draw_portrait(target)
	_draw_skills(target)
	for index in bag.size():
		var rect := cell_rect("bag", index)
		if rect.size != Vector2.ZERO: _draw_icon(target, profile.card_icon(bag[index]), rect)
	for index in deck.size(): _draw_icon(target, profile.card_icon(deck[index]), cell_rect("deck", index))
	var items := artifacts()
	for index in items.size(): _draw_icon(target, profile.card_icon(_artifact_spell(items[index])), cell_rect("artifact", index))

func _draw_icon(target: Control, icon: Texture2D, rect: Rect2) -> void:
	if icon != null: target.draw_texture_rect(icon, rect, false)

func _artifact_spell(item: Variant) -> String:
	if item is Dictionary: return str(item.get("spell", ELSecondArtifacts.spell(profile, item)))
	return str(item)

func _draw_portrait(target: Control) -> void:
	var face := int(profile.table("HeroTemplates").get(str(hero.get("template", "")), {}).get("Face", -1))
	if face < 0: return
	var base := profile.portrait(face) as AtlasTexture
	if base == null or base.atlas == null: return
	var bounds := design("RED_PortraitBounds")
	# The hero bag's 75x53 crop from (14,8) of the 100x70 portrait cell.
	target.draw_texture_rect_region(base.atlas, bounds, Rect2(base.region.position + Vector2(14, 8), bounds.size))

func _draw_skills(target: Control) -> void:
	var skills: Array = hero.get("skills", {}).keys()
	var sheet := profile.texture("Interface/Skills/icon_1")
	if sheet == null: return
	for index in mini(5, skills.size()):
		var code := str(skills[index])
		var icon_index := int(ELHeroSkills.definition(profile, code, int(hero.skills[code])).get("Icon", -1))
		if icon_index < 0: continue
		var box := Rect2(Vector2(design("RED_SkillsBounds").position.x + 4, design("RED_Skill%d" % (index + 1)).position.y + 3), Vector2(20, 20))
		target.draw_texture_rect_region(sheet, box, Rect2((icon_index / 5) * 50, (icon_index % 5) * 50, 50, 50))

func tooltip_at(at: Vector2) -> String:
	var target := hit(at)
	match target[0]:
		"bag": return card_tooltip(bag[target[1]])
		"deck": return card_tooltip(deck[target[1]])
		"artifact":
			var item: Variant = artifacts()[target[1]]
			return ELSecondArtifacts.tooltip(profile, item) if item is Dictionary else card_tooltip(str(item))
	var skills: Array = hero.get("skills", {}).keys()
	for index in mini(5, skills.size()):
		if design("RED_Skill%d" % (index + 1)).has_point(at):
			var code := str(skills[index])
			return profile.text(str(ELHeroSkills.definition(profile, code, int(hero.skills[code])).get("Desc", "")))
	var spec := str(hero.get("spec", "NONE"))
	if design("RED_ActiveSpec").has_point(at) and spec != "NONE":
		return profile.text(str(profile.table("HeroesSpecs").get(spec, {}).get("Desc", "")))
	return ""

func card_tooltip(card: String) -> String:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	return profile.text(str(row.get("Name", card))) + "\n" + profile.card_description(card)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		closed.emit()

class Surface extends Control:
	var view

	func _draw() -> void:
		view.draw_surface(self)

	func _get_tooltip(at_position: Vector2) -> String:
		return view.tooltip_at(at_position)

## A button drawn from its CutParts rows (Free, Push, Light, Disabled); the
## scroll arrows are two strips each.
class PieceButton extends BaseButton:
	var parts: Dictionary = {}

	static func make(owner: ELRoundEndDuelView, control: String) -> PieceButton:
		var button := PieceButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		var states := {"normal": [["Free"], ["Light"]], "pressed": [["Push"], ["Light"]], "hover": [["Free", "Light"], []], "hover_pressed": [["Push", "Light"], []], "disabled": [["Disabled"], []]}
		var bounds := Rect2()
		var first := true
		for state: String in states:
			var list: Array = []
			for row: Dictionary in owner._rows.get(control, []):
				var required: Array = states[state][0]
				var excluded: Array = states[state][1]
				if not required.all(func(mask: String): return row.masks.has(mask)) or excluded.any(func(mask: String): return row.masks.has(mask)): continue
				var piece := owner.cut(row, ELRoundEndDuelView.OFFSET)
				if piece.is_empty(): continue
				list.append(piece)
				bounds = piece.rect if first else bounds.merge(piece.rect)
				first = false
			button.parts[state] = list
		if first: bounds = owner.design(control)
		button.position = bounds.position
		button.size = bounds.size
		for state: String in button.parts:
			for piece: Dictionary in button.parts[state]: piece.rect.position -= bounds.position
		return button

	func _draw() -> void:
		var mode := get_draw_mode()
		var list: Array = parts.normal
		if disabled: list = parts.disabled
		elif mode == DRAW_HOVER_PRESSED: list = parts.hover_pressed if not parts.hover_pressed.is_empty() else parts.pressed
		elif mode == DRAW_PRESSED: list = parts.pressed
		elif mode == DRAW_HOVER and not parts.hover.is_empty(): list = parts.hover
		for piece: Dictionary in list: draw_texture_rect_region(piece.texture, piece.rect, piece.source)
