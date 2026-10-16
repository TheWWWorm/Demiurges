class_name ELSecondInventoryView
extends ELSpellbookView
## Second-game hero bag (InventoryScreen) on the original art: hero card
## (portrait, name, life, level bar), active specialisation drop-down, five
## skills and two rows of five artifacts on the left; the reserve ("bag", 8x5
## cells, scrolled by row) and the 16-slot active deck on the right; OK and
## Cancel. Cards are picked with a click (the icon follows the cursor) and
## placed with a second click; the right button puts a carried card back.
## Layout from Controls/CutParts (panel "InventoryScreen", shift 112,14 at
## 1024x768); behaviour in ELSecondInventory.
const PANEL := "InventoryScreen"
const CELL := Vector2(53, 52)
const ICON := Vector2(50, 50)
## Icon inset inside a 53x52 cell, measured on the cell frames of the
## background art (the list views' own margin fields are unconfirmed).
const INSET := Vector2(2, 1)
const BAG_COLUMNS := 8
const BAG_ROWS := 5
const DECK_COLUMNS := 8
const ARTIFACT_COLUMNS := 5
const TAN := Color8(0xd6, 0xbb, 0x88)
const WHITE := Color(1, 1, 1)
## Overlay tints (ARGB picked-slot highlight is not
## drawn: the carried card leaves its slot; banned colour).
const BANNED_TINT := Color8(0x55, 0x11, 0x11, 0xa0)
const HEADERS := ["InvScrHdrHero", "InvScrHdrLife", "InvScrHdrLevel", "InvScrHdrSpec", "InvScrHdrSkills", "InvScrHdrArtifacts", "InvScrHdrBag", "InvScrHdrSpells", "InvScrHdrDeck"]

var hud: ELSecondAdventureHud
var profile: ELProfile
var model := ELSecondInventory.new()
var root_control: Control
var canvas: Control
var surface: Surface
var cursor: Control
var labels: Dictionary = {}
var buttons: Dictionary = {}
var spec_popup: ELArtDropList
## Refusals (T_MB_SHOP_DECK_NOT_FULL, ...) in the original MessageBox.
var message_box: ELSecondDialogueBox
var message_text: RichTextLabel
var sound: AudioStreamPlayer
var top_row := 0
var _pieces: Array[Dictionary] = []
var _offset := Vector2.ZERO
var _specs: Array[String] = []
var _mouse := Vector2(-1000, -1000)

static func make(source_hud: ELSecondAdventureHud) -> ELSecondInventoryView:
	var view := ELSecondInventoryView.new()
	view.hud = source_hud
	return view

func build(session: ELAdventureSession, id: int) -> void:
	state = session
	hero_id = id
	profile = state.map.profile
	name = "InventoryScreen"
	model.open(state, hero_id)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_STOP
	root_control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_control)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(canvas)
	surface = Surface.new()
	surface.view = self
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.tooltip_text = " "
	canvas.add_child(surface)
	for control: String in HEADERS:
		var align := HORIZONTAL_ALIGNMENT_RIGHT if control in ["InvScrHdrLife", "InvScrHdrLevel"] else HORIZONTAL_ALIGNMENT_CENTER
		labels[control] = _label(hud.text(str(hud._controls.get(control, {}).get("Text", ""))), 17, align)
	labels.InvScrNameText = _label("", 18, HORIZONTAL_ALIGNMENT_CENTER)
	labels.InvScrLifeText = _label("", 17, HORIZONTAL_ALIGNMENT_CENTER, WHITE)
	labels.InvScrLevelText = _label("", 17, HORIZONTAL_ALIGNMENT_CENTER, WHITE)
	labels.InvScrActiveSpec = _label("", 17, HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	for index in 5: labels["InvScrSkill%d" % (index + 1)] = _label("", 16, HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	for control: String in labels: labels[control].name = control
	for control: String in ["InvScrOkBtn", "InvScrCancelBtn", "InvScrDropBtn", "InvScrScrollUp1", "InvScrScrollDown1"]:
		var button := ELSecondNotebookView.ArtButton.make(hud, control)
		button.tooltip_text = hud.tooltip_of(control)
		canvas.add_child(button)
		buttons[control] = button
	buttons.InvScrOkBtn.pressed.connect(accept)
	buttons.InvScrCancelBtn.pressed.connect(cancel)
	buttons.InvScrDropBtn.pressed.connect(func(): show_specs(not spec_popup.visible))
	buttons.InvScrScrollUp1.pressed.connect(scroll_bag.bind(-1))
	buttons.InvScrScrollDown1.pressed.connect(scroll_bag.bind(1))
	_build_spec_popup()
	_build_message_box()
	cursor = Control.new()
	cursor.name = "CarriedCard"
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cursor)
	cursor.draw.connect(_draw_cursor)
	# Leaving or hiding the screen gives the cursor back.
	tree_exiting.connect(func(): ELCursorDriver.carry(profile, null))
	visibility_changed.connect(func(): if not is_visible_in_tree(): ELCursorDriver.carry(profile, null))
	sound = AudioStreamPlayer.new()
	add_child(sound)
	root_control.resized.connect(_layout)
	refresh()

func _label(value: String, font_size: int, align: HorizontalAlignment, color := TAN) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", hud.face_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

## SpecPopUpDialog on its own cut parts and SpecPopupUp/Down arrows.
func _build_spec_popup() -> void:
	spec_popup = ELArtDropList.new()
	spec_popup.name = "InvScrSpecList"
	canvas.add_child(spec_popup)
	var pieces: Array = []
	for row: Dictionary in hud.rows("SpecPopupTexturesCtrl"): pieces.append(hud.cut(row))
	spec_popup.setup(pieces, ELArtDropList.row_font(), ELSecondNotebookView.ArtButton.make(hud, "SpecPopupUp"), ELSecondNotebookView.ArtButton.make(hud, "SpecPopupDown"))
	spec_popup.thumb_texture = ELArtDropList.thumb_art(profile)
	spec_popup.chosen.connect(_choose_listed)
	spec_popup.hide()

func _build_message_box() -> void:
	message_box = ELSecondDialogueBox.new()
	root_control.add_child(message_box)
	message_box.setup(hud)
	message_box.name = "InvScrMessage"
	message_text = message_box.body
	message_box.answered.connect(func(_answer: String): message_box.hide())

# --- Layout -------------------------------------------------------------------

func design(control: String) -> Rect2:
	var row: Dictionary = hud._controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + _offset, Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _layout() -> void:
	var area := root_control.size
	if area.y <= 0: return
	var factor := area.y / ELSecondAdventureHud.DESIGN_HEIGHT
	var width := maxf(1024.0, area.x / factor)
	canvas.scale = Vector2(factor, factor)
	canvas.size = Vector2(width, ELSecondAdventureHud.DESIGN_HEIGHT)
	surface.size = canvas.size
	cursor.size = canvas.size
	var row: Dictionary = hud._controls.get(PANEL, {})
	_offset = Vector2(float(row.get("ShiftX", 112)) + (width - 1024.0) * 0.5, float(row.get("ShiftY", 14)))
	_pieces.clear()
	for piece_row: Dictionary in hud._rows.get(PANEL, []):
		var piece := hud.cut(piece_row, _offset)
		if not piece.is_empty(): _pieces.append(piece)
	for control: String in labels:
		labels[control].position = design(control).position
		labels[control].size = design(control).size
	for control: String in buttons: buttons[control].place(_offset)
	spec_popup.place(design("SpecPopUpDialog"))
	message_box.layout()
	surface.queue_redraw()
	cursor.queue_redraw()

func refresh() -> void:
	if surface == null: return
	var hero := state.object(hero_id)
	labels.InvScrNameText.text = str(hero.get("title", hero.get("name", "")))
	labels.InvScrLifeText.text = str(int(hero.get("health", 0)))
	labels.InvScrLevelText.text = str(int(hero.get("level", 1)))
	labels.InvScrLifeText.tooltip_text = hud.tooltip_of("InvScrLifeText")
	labels.InvScrActiveSpec.text = spec_name(model.specialization)
	_specs = state.specializations(hero)
	# the drop button is enabled when the hero owns a specialisation.
	buttons.InvScrDropBtn.disabled = _specs.is_empty()
	var skills: Array = hero.get("skills", {}).keys()
	for index in 5:
		var label: Label = labels["InvScrSkill%d" % (index + 1)]
		label.text = ""
		if index < skills.size():
			var code := str(skills[index])
			label.text = profile.text(str(ELHeroSkills.definition(profile, code, int(hero.skills[code])).get("Name", code)))
	_refresh_scroll()
	_layout()

func spec_name(code: String) -> String:
	if code == "NONE" or code.is_empty(): return ""
	return profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Name", code)))

## SpecPopUpDialog under the drop button: opened only
## when the hero owns a specialisation; the current one is in the brighter ink.
func show_specs(value: bool) -> void:
	if spec_popup == null: return
	if value:
		var names: Array = []
		var tips: Array = []
		for code: String in _specs:
			names.append(spec_name(code))
			tips.append(profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Desc", ""))))
		spec_popup.fill(names, tips, _specs.find(model.specialization))
	spec_popup.visible = value and not _specs.is_empty()
	if spec_popup.visible: spec_popup.move_to_front()

func _choose_listed(index: int) -> void:
	if index >= 0 and index < _specs.size(): choose_spec(_specs[index])

## Staged until OK (writes hero from the screen's copy).
func choose_spec(code: String) -> void:
	if _specs.has(code): model.specialization = code
	labels.InvScrActiveSpec.text = spec_name(model.specialization)
	show_specs(false)

func scroll_bag(delta: int) -> void:
	top_row = clampi(top_row + delta, 0, _last_row())
	_refresh_scroll()
	surface.queue_redraw()

func _last_row() -> int:
	return maxi(0, ceili(model.bag.size() / float(BAG_COLUMNS)) - BAG_ROWS)

func _refresh_scroll() -> void:
	top_row = clampi(top_row, 0, _last_row())
	buttons.InvScrScrollUp1.disabled = top_row <= 0
	buttons.InvScrScrollDown1.disabled = top_row >= _last_row()

# --- Hit testing ----------------------------------------------------------------

## Zone and index under a canvas point: ["bag", i] (-1 = empty bag space),
## ["deck", slot], ["artifact", i] or ["", -1].
func hit(at: Vector2) -> Array:
	var bag := design("InvScrBagBounds")
	if bag.has_point(at):
		var cell := Vector2i((at - bag.position) / CELL)
		if cell.x >= BAG_COLUMNS or cell.y >= BAG_ROWS: return ["bag", -1]
		var index := (top_row + cell.y) * BAG_COLUMNS + cell.x
		return ["bag", index if index < model.bag.size() else -1]
	var deck := design("InvScrASpellsBounds1")
	if deck.has_point(at):
		var cell := Vector2i((at - deck.position) / CELL)
		if cell.x >= DECK_COLUMNS or cell.y >= 2: return ["deck", -1]
		return ["deck", cell.y * DECK_COLUMNS + cell.x]
	for row in 2:
		var bounds := design("InvScrArtifactsBounds%d" % (row + 1))
		if bounds.has_point(at):
			var column := int((at.x - bounds.position.x) / CELL.x)
			return ["artifact", row * ARTIFACT_COLUMNS + column] if column < ARTIFACT_COLUMNS else ["", -1]
	return ["", -1]

## Canvas rectangle of a bag item (null when scrolled out), deck slot or artifact.
func cell_rect(zone: String, index: int) -> Rect2:
	match zone:
		"bag":
			var row := index / BAG_COLUMNS - top_row
			if row < 0 or row >= BAG_ROWS: return Rect2()
			return Rect2(design("InvScrBagBounds").position + INSET + Vector2(index % BAG_COLUMNS, row) * CELL, ICON)
		"deck": return Rect2(design("InvScrASpellsBounds1").position + INSET + Vector2(index % DECK_COLUMNS, index / DECK_COLUMNS) * CELL, ICON)
		"artifact": return Rect2(design("InvScrArtifactsBounds%d" % (index / ARTIFACT_COLUMNS + 1)).position + INSET + Vector2((index % ARTIFACT_COLUMNS) * CELL.x, 0), ICON)
	return Rect2()

func surface_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if not model.carried().is_empty(): cursor.queue_redraw()
		return
	if not event is InputEventMouseButton or not event.pressed: return
	_mouse = event.position
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: scroll_bag(-1)
		MOUSE_BUTTON_WHEEL_DOWN: scroll_bag(1)
		MOUSE_BUTTON_RIGHT:
			if model.right_click(): _changed()
		MOUSE_BUTTON_LEFT:
			show_specs(false)
			var target := hit(event.position)
			var result := ""
			var returning := model.picked_zone == "deck"
			match target[0]:
				"bag": result = model.click_bag(target[1])
				"deck": result = model.click_deck(target[1])
				_: return
			if returning and target[0] == "bag":
				# A card returned to the bag is appended and scrolled into view.
				top_row = maxi(top_row, (model.bag.size() - 1) / BAG_COLUMNS - BAG_ROWS + 1)
			_play(result)
			_changed()

func _changed() -> void:
	_refresh_scroll()
	surface.queue_redraw()
	cursor.queue_redraw()

func _play(path: String) -> void:
	if path.is_empty(): return
	var stream := ELAudio.sound(profile, path)
	if stream == null: return
	sound.stream = stream
	sound.play()

# --- Commands -------------------------------------------------------------------

func accept() -> void:
	show_specs(false)
	var result := model.accept()
	if result.is_empty():
		closed.emit()
		return
	_changed()
	if result != "forbidden": show_message(profile.text(result))

func cancel() -> void:
	show_specs(false)
	_changed()
	if model.cancel(): closed.emit()

func show_message(value: String) -> void:
	message_box.present({"box": "message", "text": value, "question": false}, state)
	message_box.move_to_front()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE, KEY_I:
			if message_box.visible: message_box.hide()
			elif spec_popup.visible: show_specs(false)
			else: cancel()
		KEY_ENTER, KEY_KP_ENTER:
			if message_box.visible: message_box.hide()
			else: accept()
		_: return
	get_viewport().set_input_as_handled()

# --- Drawing --------------------------------------------------------------------

func draw_surface(target: Control) -> void:
	target.draw_rect(Rect2(Vector2.ZERO, target.size), Color(0, 0, 0, 0.35))
	for piece: Dictionary in _pieces: target.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var hero := state.object(hero_id)
	_draw_portrait(target, hero)
	_draw_bar(target, hero)
	_draw_skills(target, hero)
	for index in model.bag.size():
		if model.picked_zone == "bag" and model.picked == index: continue
		var rect := cell_rect("bag", index)
		if rect.size != Vector2.ZERO: _draw_card(target, model.bag[index], rect, hero)
	for slot in ELSecondInventory.DECK_SLOTS:
		if model.deck[slot].is_empty() or model.picked_zone == "deck" and model.picked == slot: continue
		_draw_card(target, model.deck[slot], cell_rect("deck", slot), hero)
	var items: Array = hero.get("artifacts", [])
	for index in mini(items.size(), 2 * ARTIFACT_COLUMNS):
		var icon := profile.card_icon(ELSecondArtifacts.spell(profile, items[index]))
		if icon != null: target.draw_texture_rect(icon, cell_rect("artifact", index), false)

func _draw_card(target: Control, card: String, rect: Rect2, hero: Dictionary) -> void:
	var icon := profile.card_icon(card)
	if icon != null: target.draw_texture_rect(icon, rect, false)
	if ELSecondInventory.banned(hero, card, profile): target.draw_rect(rect, BANNED_TINT)

func _draw_portrait(target: Control, hero: Dictionary) -> void:
	var face := int(hud._art.resolve(hero).get("row", {}).get("Face", -1)) if not hero.is_empty() else -1
	if face < 0: return
	var base := profile.portrait(face) as AtlasTexture
	if base == null or base.atlas == null: return
	var bounds := design("InvScrPortraitBounds")
	# a 75x53 crop from (14,8) of the 100x70 portrait cell.
	target.draw_texture_rect_region(base.atlas, bounds, Rect2(base.region.position + Vector2(14, 8), bounds.size))

func _draw_bar(target: Control, hero: Dictionary) -> void:
	var rect := design("InvScrBarBounds")
	var level := int(hero.get("level", 1))
	var low := ELHeroProgression.threshold(profile, level)
	var high := ELHeroProgression.threshold(profile, level + 1)
	var progress := clampf(float(ELHeroProgression.effective(hero) - low) / float(maxi(1, high - low)), 0, 1) if level < ELHeroProgression.MAX_LEVEL else 1.0
	target.draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(maxf(0, (rect.size.x - 2) * progress), rect.size.y - 2)), Color("c9a24a"))

func _draw_skills(target: Control, hero: Dictionary) -> void:
	var skills: Array = hero.get("skills", {}).keys()
	var origin := design("InvScrSkill1").position
	for index in mini(5, skills.size()):
		var code := str(skills[index])
		var icon_index := int(ELHeroSkills.definition(profile, code, int(hero.skills[code])).get("Icon", -1))
		var sheet := profile.texture("Interface/Skills/icon_1")
		if icon_index < 0 or sheet == null: continue
		var box := Rect2(Vector2(design("InvScrSkillsBounds").position.x + 4, origin.y + 3 + index * 26), Vector2(20, 20))
		target.draw_texture_rect_region(sheet, box, Rect2((icon_index / 5) * 50, (icon_index % 5) * 50, 50, 50))

func _draw_cursor() -> void:
	var card := model.carried()
	var icon: Texture2D = profile.card_icon(card) if not card.is_empty() else null
	# The original's cursor becomes the icon; drawn here only without one.
	if ELCursorDriver.carry(profile, icon) or icon == null or _mouse.x < -500: return
	cursor.draw_texture_rect(icon, Rect2(_mouse - ICON * 0.5, ICON), false)

# --- Tooltips -------------------------------------------------------------------

func tooltip_at(at: Vector2) -> String:
	var hero := state.object(hero_id)
	var target := hit(at)
	match target[0]:
		"bag", "deck":
			var card := ""
			if target[0] == "bag" and target[1] >= 0: card = model.bag[target[1]]
			elif target[0] == "deck" and target[1] >= 0: card = model.deck[target[1]]
			if not card.is_empty(): return card_tooltip(card)
		"artifact":
			var items: Array = hero.get("artifacts", [])
			if target[1] < items.size(): return ELSecondArtifacts.tooltip(profile, items[target[1]])
	if design("InvScrBarBounds").grow(2).has_point(at) or design("InvScrLevelText").has_point(at): return hud.level_tooltip(hero)
	if design("InvScrLifeText").has_point(at): return hud.tooltip_of("InvScrLifeText")
	for index in 5:
		if design("InvScrSkill%d" % (index + 1)).has_point(at):
			var skills: Array = hero.get("skills", {}).keys()
			if index < skills.size():
				var code := str(skills[index])
				return profile.text(str(ELHeroSkills.definition(profile, code, int(hero.skills[code])).get("Desc", "")))
	if design("InvScrActiveSpec").has_point(at) and model.specialization != "NONE":
		return profile.text(str(profile.table("HeroesSpecs").get(model.specialization, {}).get("Desc", "")))
	return ""

func card_tooltip(card: String) -> String:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	return profile.text(str(row.get("Name", card))) + "\n" + profile.card_description(card)

class Surface extends Control:
	var view

	func _draw() -> void:
		view.draw_surface(self)

	func _gui_input(event: InputEvent) -> void:
		view.surface_input(event)

	func _get_tooltip(at_position: Vector2) -> String:
		return view.tooltip_at(at_position)

