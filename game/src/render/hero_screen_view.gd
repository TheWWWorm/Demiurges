class_name ELHeroScreenView
extends Control
## First-game HeroScreen and ExchangeScreen composed from the original
## CutParts (1024 set) and Controls coordinates. Both panels sit at the
## registry ShiftX/ShiftY. Each hero panel shows the portrait, name, Level/Life/Sight, the item bar (artifacts,
## then global-spell scrolls; five visible slots, one per scroll click),
## specialization and skills, and the spellbook. Items move by dragging between
## bars or within one bar; the HeroScreen adds level info, the hero's global
## spells with Dispell, the level-up offers and DismissHero.
signal closed
signal dismissed(id: int)
## Controls "HeroScreen"/"ExchangeScreen" ShiftX/ShiftY for 1024x768.
const ORIGIN := Vector2(70, 91)
## The exchange's right panel repeats the left one 317 px further right.
const RIGHT := Vector2(317, 0)
const SLOTS := 5
const STEP := 53.0
const ICON := Vector2(50, 50)
const BAR := Rect2(5, 134, 306, 56)
const TEXT := Color("f2eee4")
const CAPTION := Color("d8c89a")

var director: ELAdventureDirector
var state: ELAdventureSession
var hud: ELAdventureHud
var profile: ELProfile
var exchange := false
var heroes: Array[int] = []
var scroll: Array[int] = [0, 0]
var gs_scroll := 0
var gs_pick := 0
var offer_pick := -1
var sheet: Sheet
var buttons: Dictionary = {}
var drag: Dictionary = {}
var confirm: ELFirstMessageBox
## True while the press being handled is a double click.
var double_click := false
var _pieces: Array[Dictionary] = []
var _labels: Array[Dictionary] = []

func build(owner: ELAdventureDirector, panel: ELAdventureHud, ids: Array[int], is_exchange: bool) -> void:
	director = owner
	state = owner.state
	hud = panel
	profile = state.map.profile
	heroes = ids
	exchange = is_exchange
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	sheet = Sheet.new()
	sheet.view = self
	sheet.size = Vector2(645, 625)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	for row: Dictionary in hud.rows("ExchangeScreen" if exchange else "HeroScreen", [], ["Res1"]):
		var piece := hud.cut(row)
		if not piece.is_empty(): _pieces.append(piece)
	for side in heroes.size(): _build_side(side)
	if exchange: _button("ExchOK", Vector2.ZERO).pressed.connect(func(): closed.emit())
	else:
		_caption(Rect2(200, 0, 220, 23), "CtrlHeroScreenCaption", 18)
		_caption(Rect2(320, 110, 300, 17), "CtrlHeroText2", 15)
		_caption(Rect2(380, 197, 200, 17), "CtrlHeroText5", 15)
		for line in 3:
			_label(Rect2(430, 33 + 27 * line, 190, 18), "", 14, CAPTION, hud._bold, HORIZONTAL_ALIGNMENT_LEFT).text = profile.text("CtrlLevelInfo_%d" % (line + 1))
			_labels.append({"key": "level_info", "line": line, "label": _label(Rect2(354, 33 + 27 * line, 70, 18), "", 14, TEXT, hud._bold, HORIZONTAL_ALIGNMENT_LEFT)})
		_button("HeroScrOk", Vector2.ZERO).pressed.connect(func(): closed.emit())
		_button("DismissHero", Vector2.ZERO).pressed.connect(_ask_dismiss)
		_button("GlSpScrL", Vector2.ZERO).pressed.connect(func(): gs_scroll = maxi(0, gs_scroll - 1); refresh())
		_button("GlSpScrR", Vector2.ZERO).pressed.connect(func(): gs_scroll = clampi(gs_scroll + 1, 0, maxi(0, attached(heroes[0]).size() - 3)); refresh())
		_button("Dispell", Vector2.ZERO).pressed.connect(_dispel)
		_button("AcceptLevelUp", Vector2.ZERO).pressed.connect(_accept_skill)
		ELHeroSkills.prepare(profile, state.object(heroes[0]))
	resized.connect(_layout)
	_layout()
	refresh()

func _build_side(side: int) -> void:
	var at := RIGHT * side
	_labels.append({"key": "name", "side": side, "label": _label(Rect2(Vector2(15, 89) + at, Vector2(150, 15)), "", 12, TEXT, hud._italic)})
	for line in 3:
		_labels.append({"key": "stat", "side": side, "line": line, "label": _label(Rect2(Vector2(181, 25 + 27 * line) + at, Vector2(30, 18)), "", 14, TEXT, hud._bold)})
		_label(Rect2(Vector2(214, 25 + 27 * line) + at, Vector2(90, 18)), "", 13, CAPTION, hud._bold, HORIZONTAL_ALIGNMENT_LEFT).text = profile.text(["T_LEVEL", "T_LIFE", "T_SIGHT"][line])
	_caption(Rect2(Vector2(60, 110) + at, Vector2(200, 17)), "CtrlHeroText3", 15)
	_caption(Rect2(Vector2(40, 197) + at, Vector2(240, 17)), "CtrlHeroText4", 15)
	_caption(Rect2(Vector2(58, 355) + at, Vector2(202, 17)), "CtrlHeroText6", 15)
	_labels.append({"key": "spec", "side": side, "label": _label(Rect2(Vector2(40, 232) + at, Vector2(235, 17)), "", 14, TEXT, hud._bold)})
	var places := [Vector2(40, 269), Vector2(40, 299), Vector2(40, 326), Vector2(185, 269), Vector2(185, 299)]
	for index in places.size():
		_labels.append({"key": "skill", "side": side, "index": index, "label": _label(Rect2(places[index] + at, Vector2(120, 20)), "", 12, TEXT, hud._bold, HORIZONTAL_ALIGNMENT_LEFT)})
	var left := _button("EquipScrL", at)
	left.pressed.connect(func(): scroll[side] = maxi(0, scroll[side] - 1); refresh())
	var right := _button("EquipScrR", at)
	right.pressed.connect(func(): scroll[side] = clampi(scroll[side] + 1, 0, maxi(0, ELHeroExchange.count(state.object(heroes[side])) - SLOTS)); refresh())
	buttons["EquipScrL%d" % side] = left
	buttons["EquipScrR%d" % side] = right

func _button(control: String, offset: Vector2) -> ELAdventureHud.CutButton:
	var button := ELAdventureHud.CutButton.from_rows(hud, control, offset)
	var tip := profile.text("CtrlTt" + control)
	if tip != "CtrlTt" + control: button.tooltip_text = tip
	button.place(Vector2.ZERO)
	sheet.add_child(button)
	if not buttons.has(control): buttons[control] = button
	return button

func _caption(rect: Rect2, key: String, size: int) -> Label:
	var label := _label(rect, profile.text(key), size, CAPTION, hud._italic)
	return label

func _label(rect: Rect2, text: String, size: int, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(label)
	return label

func _layout() -> void:
	var factor := hud.scale_factor
	sheet.scale = Vector2(factor, factor)
	sheet.position = (ORIGIN + Vector2(hud.right_shift * 0.5, 0)) * factor

## Labels and equipment scrolling of the hero panels.
func _refresh_sides() -> void:
	for side in heroes.size():
		var hero := state.object(heroes[side])
		scroll[side] = clampi(scroll[side], 0, maxi(0, ELHeroExchange.count(hero) - SLOTS))
	for entry: Dictionary in _labels:
		var hero := state.object(heroes[int(entry.get("side", 0))])
		var label: Label = entry.label
		match entry.key:
			"name": label.text = str(hero.get("title", hero.get("name", "")))
			"stat": label.text = str(int([hero.get("level", 1), hero.get("health", 0), hero.get("base_ap", 0)][entry.line]))
			"spec":
				var code := str(hero.get("specialization", "NONE"))
				label.text = profile.text(str(profile.table("HeroesSpecs").get(code, {}).get("Name", ""))) if code != "NONE" and profile.table("HeroesSpecs").has(code) else ""
			"skill":
				var codes: Array = hero.get("skills", {}).keys()
				label.text = _skill_name(str(codes[entry.index]), int(hero.skills[codes[entry.index]])) if entry.index < codes.size() else ""
			"level_info":
				var level := int(hero.get("level", 1))
				label.text = str([ELStrategy.upkeep(profile, hero), ELHeroProgression.effective(hero), ELHeroProgression.threshold(profile, level + 1) if level < ELHeroProgression.MAX_LEVEL else 0][entry.line])
				if entry.line == 2 and level >= ELHeroProgression.MAX_LEVEL: label.text = "-"
	for side in heroes.size():
		var count := ELHeroExchange.count(state.object(heroes[side]))
		buttons["EquipScrL%d" % side].disabled = scroll[side] <= 0
		buttons["EquipScrR%d" % side].disabled = scroll[side] >= count - SLOTS

func refresh() -> void:
	_refresh_sides()
	var acting := director.can_move() and director.movement.is_empty()
	if not exchange:
		var hero := state.object(heroes[0])
		var spells := attached(heroes[0])
		gs_scroll = clampi(gs_scroll, 0, maxi(0, spells.size() - 3))
		gs_pick = clampi(gs_pick, 0, maxi(0, spells.size() - 1))
		buttons.GlSpScrL.disabled = gs_scroll <= 0
		buttons.GlSpScrR.disabled = gs_scroll >= spells.size() - 3
		buttons.Dispell.disabled = not acting or spells.is_empty() or int(spells[gs_pick].player) != state.current_player
		var offers: Array = hero.get("skill_offers", [])
		if offer_pick >= offers.size(): offer_pick = -1
		buttons.AcceptLevelUp.disabled = not acting or offer_pick < 0 or int(hero.get("skill_points", 0)) <= 0
		buttons.DismissHero.disabled = not ELHeroExchange.dismiss_problem(director, heroes[0]).is_empty()
	sheet.queue_redraw()

func _skill_name(code: String, rank: int) -> String:
	return profile.text(str(ELHeroSkills.definition(profile, code, rank).get("Name", code)))

## Global spells attached to a hero, in cast order, with their caster.
func attached(hero_id: int) -> Array:
	var result: Array = []
	if not ELGlobalSpells.applies(state): return result
	for player: int in state.players:
		for spell: Dictionary in state.players[player].get("global_spells", {}).get("active", []):
			if int(spell.get("hero", -1)) == hero_id: result.append({"code": str(spell.code), "serial": int(spell.serial), "player": player})
	return result

## Equipment slot rectangles of one side, in panel coordinates.
func slot_rect(side: int, slot: int) -> Rect2:
	return Rect2(Vector2(28 + STEP * slot, 138) + RIGHT * side, ICON)

func bar_rect(side: int) -> Rect2:
	return Rect2(BAR.position + RIGHT * side, BAR.size)

## (side, absolute bar index) of an occupied slot at a point, or [-1, -1].
func slot_at(point: Vector2) -> Array:
	for side in heroes.size():
		if not bar_rect(side).has_point(point): continue
		for slot in SLOTS:
			var index := scroll[side] + slot
			if slot_rect(side, slot).has_point(point) and index < ELHeroExchange.count(state.object(heroes[side])): return [side, index]
	return [-1, -1]

## Drops the dragged entry at a point; outside every bar cancels.
func drop(point: Vector2) -> bool:
	if drag.is_empty(): return false
	var source: int = drag.hero
	var index: int = drag.index
	drag = {}
	for side in heroes.size():
		var rect := bar_rect(side)
		if not rect.has_point(point): continue
		var hit := slot_at(point)
		var target := state.object(heroes[side])
		var position := ELHeroExchange.drop_position(target, int(hit[1]) if int(hit[0]) == side else -1, point.x < rect.get_center().x)
		var moved := ELHeroExchange.transfer(state, source, index, heroes[side], position)
		refresh()
		return moved
	refresh()
	return false

func icon_for(entry: Dictionary) -> Texture2D:
	if entry.kind == "artifact":
		var type := str(profile.table("Artefacts").get(str(entry.item.name), {}).get("SpellType", ""))
		return profile.card_icon(type) if not type.is_empty() else null
	var owner := state.object(heroes[0])
	return gs_icon(ELMapPickups.resolve(profile, entry.item.spells, str(state.players.get(int(owner.get("owner", 0)), {}).get("color", ""))))

## Global-spell pictures: 3 x 5 cells of 70 x 50 per sheet, row-major (the
## building-icon layout). The 50 px slot shows the cell's central square.
func gs_icon(code: String) -> Texture2D:
	var row: Dictionary = profile.table("GlobalSpells").get(code, {})
	if row.is_empty(): return null
	var index := int(row.get("Icon", 0))
	var sheet_texture := profile.texture("Interface/GlobalSpells/icon%02d" % (index / 15 + 1))
	if sheet_texture == null: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet_texture
	atlas.region = Rect2((index % 15 % 3) * 70 + 10, (index % 15 / 3) * 50, 50, 50)
	atlas.filter_clip = true
	return atlas

func tooltip_at(point: Vector2) -> String:
	var hit := slot_at(point)
	if int(hit[0]) >= 0:
		var entry: Dictionary = ELHeroExchange.bar(state.object(heroes[hit[0]]))[hit[1]]
		if entry.kind == "artifact":
			var row: Dictionary = profile.table("Artefacts").get(str(entry.item.name), {})
			var body := profile.text("T_ARTIFACT_TT")
			var details := body % [int(entry.item.charges), int(row.get("FirstUsage", 0)), int(row.get("UsageGap", 0)), int(row.get("RechargeDuration", 0))] if body.count("%d") == 4 else "%d" % int(entry.item.charges)
			return ELMapPickups.artifact_title(profile, str(entry.item.name)) + "\n" + details
		var code := ELMapPickups.resolve(profile, entry.item.spells, str(state.players.get(int(state.object(heroes[hit[0]]).get("owner", 0)), {}).get("color", "")))
		return ELMapPickups.spell_title(profile, code) + "\n" + profile.text("T_GLOBAL_SPELL_PART" if entry.item.kind == ELMapPickups.PART else "T_GLOBAL_SPELL_FULL")
	for side in heroes.size():
		var cards := book_cards(side)
		for index in mini(15, cards.size()):
			if Rect2(Vector2(29 + 53 * (index % 5), 389 + 52 * (index / 5)) + RIGHT * side, ICON).has_point(point): return profile.text(str(profile.table("CombatSpells").get(str(cards[index]), {}).get("Name", cards[index])))
	if not exchange:
		var spells := attached(heroes[0])
		for slot in 3:
			if Rect2(362 + STEP * slot, 138, 50, 50).has_point(point) and gs_scroll + slot < spells.size(): return ELGlobalSpells.title(profile, spells[gs_scroll + slot].code)
		var offers: Array = state.object(heroes[0]).get("skill_offers", [])
		for slot in mini(3, offers.size()):
			if Rect2(362 + STEP * slot, 233, 50, 50).has_point(point):
				var hero := state.object(heroes[0])
				var rank := int(hero.get("skills", {}).get(offers[slot], -1)) + 1
				return _skill_name(str(offers[slot]), rank) + "\n" + profile.text(str(ELHeroSkills.definition(profile, str(offers[slot]), rank).get("Description", "")))
	return ""

func press(point: Vector2) -> void:
	var hit := slot_at(point)
	if int(hit[0]) >= 0:
		drag = {"hero": heroes[hit[0]], "index": int(hit[1]), "at": point}
		sheet.queue_redraw()
		return
	if exchange: return
	var spells := attached(heroes[0])
	for slot in 3:
		if Rect2(362 + STEP * slot, 138, 50, 50).has_point(point) and gs_scroll + slot < spells.size():
			gs_pick = gs_scroll + slot
			refresh()
			return
	var offers: Array = state.object(heroes[0]).get("skill_offers", [])
	for slot in mini(3, offers.size()):
		if Rect2(362 + STEP * slot, 233, 50, 50).has_point(point):
			offer_pick = slot
			refresh()
			return

func _dispel() -> void:
	var spells := attached(heroes[0])
	if spells.is_empty() or gs_pick >= spells.size(): return
	var spell: Dictionary = spells[gs_pick]
	if int(spell.player) != state.current_player: return
	ELGlobalSpells.dispel(state, int(spell.player), int(spell.serial))
	refresh()

func _accept_skill() -> void:
	var hero := state.object(heroes[0])
	var offers: Array = hero.get("skill_offers", [])
	if offer_pick < 0 or offer_pick >= offers.size(): return
	if state.choose_skill(heroes[0], str(offers[offer_pick])): offer_pick = -1
	refresh()

## The original MessageBox asks T_MB_DISMISS_HERO with OK and Cancel.
func _ask_dismiss() -> void:
	if confirm != null or not ELHeroExchange.dismiss_problem(director, heroes[0]).is_empty(): return
	confirm = ELFirstMessageBox.new()
	add_child(confirm)
	confirm.setup(hud, profile.text("T_MB_DISMISS_HERO").strip_edges(), ELFirstMessageBox.OK_CANCEL)
	confirm.answered.connect(_answer_dismiss)

func _answer_dismiss(accepted: bool) -> void:
	if confirm == null: return
	confirm.queue_free()
	confirm = null
	if accepted and ELHeroExchange.dismiss(director, heroes[0]): dismissed.emit(heroes[0])

## Escape closes the confirmation first, then the screen.
func cancel() -> void:
	if confirm != null: _answer_dismiss(false)
	elif not drag.is_empty():
		drag = {}
		sheet.queue_redraw()
	else: closed.emit()

func _draw_sheet() -> void:
	for piece: Dictionary in _pieces: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var font: Font = hud._bold
	for side in heroes.size():
		var at := RIGHT * side
		var hero := state.object(heroes[side])
		var portrait := _portrait(hero)
		if portrait is AtlasTexture:
			var region: Rect2 = (portrait as AtlasTexture).region
			sheet.draw_texture_rect_region((portrait as AtlasTexture).atlas, Rect2(Vector2(51, 28) + at, Vector2(73, 52)), Rect2(region.position + Vector2(14, 8), Vector2(73, 52)))
		var entries := ELHeroExchange.bar(hero)
		for slot in SLOTS:
			var index := scroll[side] + slot
			if index >= entries.size(): break
			var rect := slot_rect(side, slot)
			var dragged := not drag.is_empty() and int(drag.hero) == heroes[side] and int(drag.index) == index
			var icon := icon_for(entries[index])
			if icon != null: sheet.draw_texture_rect(icon, rect, false, Color(1, 1, 1, 0.35) if dragged else Color.WHITE)
			if entries[index].kind == "artifact": _digits(rect, str(int(entries[index].item.charges)), font)
		var cards := book_cards(side)
		var uses := book_uses(side)
		for index in mini(15, cards.size()):
			var rect := Rect2(Vector2(29 + 53 * (index % 5), 389 + 52 * (index / 5)) + at, ICON)
			sheet.draw_texture_rect(profile.card_icon(str(cards[index])), rect, false)
			if index < uses.size() and int(uses[index]) >= 0: _digits(rect, str(int(uses[index])), font)
		# Skill ranks: one to three stars left of each skill name.
		var codes: Array = hero.get("skills", {}).keys()
		var places := [Vector2(40, 269), Vector2(40, 299), Vector2(40, 326), Vector2(185, 269), Vector2(185, 299)]
		for index in mini(places.size(), codes.size()):
			for star in int(hero.skills[codes[index]]) + 1: _star(places[index] + at + Vector2(-16, 4 + star * 6))
	if not exchange:
		var spells := attached(heroes[0])
		for slot in 3:
			if gs_scroll + slot >= spells.size(): break
			var rect := Rect2(362 + STEP * slot, 138, 50, 50)
			var icon := gs_icon(spells[gs_scroll + slot].code)
			if icon != null: sheet.draw_texture_rect(icon, rect, false)
			if gs_scroll + slot == gs_pick: sheet.draw_rect(rect.grow(1), Color("e8e0cc"), false, 2.0)
		var hero := state.object(heroes[0])
		var offers: Array = hero.get("skill_offers", []) if int(hero.get("skill_points", 0)) > 0 else []
		for slot in mini(3, offers.size()):
			var rect := Rect2(362 + STEP * slot, 233, 50, 50)
			var icon := ELBuildingMessageView.skill_icon(profile, str(offers[slot]), int(hero.get("skills", {}).get(offers[slot], -1)) + 1)
			if icon != null: sheet.draw_texture_rect(icon, rect, false)
			if slot == offer_pick: sheet.draw_rect(rect.grow(1), Color("e8e0cc"), false, 2.0)
	if not drag.is_empty():
		var entries := ELHeroExchange.bar(state.object(int(drag.hero)))
		if int(drag.index) < entries.size():
			var icon := icon_for(entries[drag.index])
			var rect := Rect2(drag.at - ICON * 0.5, ICON)
			if icon != null: sheet.draw_texture_rect(icon, rect, false)
			sheet.draw_rect(rect, Color("e8e0cc"), false, 1.5)

## Mouse wheel over the sheet; true when consumed.
func wheel(_point: Vector2, _direction: int) -> bool:
	return false

## The spellbook a side shows; the laboratory shows its draft instead.
func book_cards(side: int) -> Array:
	return state.object(heroes[side]).get("cards", [])

func book_uses(side: int) -> Array:
	return state.object(heroes[side]).get("rune_uses", [])

func _portrait(hero: Dictionary) -> Texture2D:
	return profile.portrait(int(hud._art.resolve(hero).get("row", {}).get("Face", 0)))

func _digits(rect: Rect2, text: String, font: Font) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var at := rect.end - Vector2(width + 3, 4)
	sheet.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.9))
	sheet.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6e7a8"))

func _star(center: Vector2) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var radius := 3.6 if index % 2 == 0 else 1.5
		var angle := -PI / 2 + index * PI / 5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	sheet.draw_colored_polygon(points, Color("e8c860"))

## Drawing, drag input and tooltips of the composed panel.
class Sheet extends Control:
	var view: ELHeroScreenView

	func _draw() -> void:
		view._draw_sheet()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if view.wheel(event.position, -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1): accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			view.double_click = event.double_click
			if event.pressed: view.press(event.position)
			elif not view.drag.is_empty(): view.drop(event.position)
			accept_event()
		elif event is InputEventMouseMotion and not view.drag.is_empty():
			view.drag.at = event.position
			queue_redraw()

	func _get_tooltip(at_position: Vector2) -> String:
		return view.tooltip_at(at_position)
