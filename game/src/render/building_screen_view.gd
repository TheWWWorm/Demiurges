class_name ELBuildingScreenView
extends Control
## First-game BuildingScreen composed from the original CutParts at the
## registry ShiftX/ShiftY. Opened by a double click on a building in the
## adventure panel's buildings list. Laboratories use the tall Type1 layout
## with their spell list; other buildings use the Type2 layout, shifted down
## by half the spell panel's height. The name and level are formatted by
## CtrlBuildingName. While the building has a next level, up to four upgrade
## costs are shown (red when above the stock); the upgrade button appears
## only when the owner can pay, and upgrades without a hero.
signal closed
signal upgraded(id: int)
const PANEL := "BuildingScreen"
const ORIGIN := Vector2(70, 91)
## Height of the BuildingSpells panel; Type2 moves down by half of it.
const SPELLS_HEIGHT := 214
const COST_ICON := Vector2(183, 206)
const COST_BOX := Rect2(212, 211, 31, 17)
const COST_STEP := 75.0
const ICON_SIZE := 23.0
const SPELL_CELL := Vector2(194, 306)
const SPELL_STEP := Vector2(53, 52)
const DESCRIPTION := Rect2(181, 95, 288, 54)
const TEXT := Color("f2eee4")
const CAPTION := Color("d8c89a")
const RED := Color(1, 0, 0)

var director: ELAdventureDirector
var state: ELAdventureSession
var hud: ELAdventureHud
var profile: ELProfile
var building_id := -1
var spells := false
var sheet: Sheet
var buttons: Dictionary = {}
var name_label: Label
var description_label: Label
var upgrade_label: Label
var _pieces: Array[Dictionary] = []
var _icons: Texture2D

func build(owner: ELAdventureDirector, panel: ELAdventureHud, id: int) -> void:
	director = owner
	state = owner.state
	hud = panel
	profile = state.map.profile
	building_id = id
	spells = ELBuildingScreen.has_spells(state.object(id))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet = Sheet.new()
	sheet.view = self
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	_icons = profile.texture(hud._paths.get("BUILDING_SCREEN_1", ""))
	_compose()
	name_label = _label(Rect2(212, 63, 227, 18), 18, CAPTION, hud._bold)
	description_label = _label(DESCRIPTION, 13, TEXT, hud._italic)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.clip_text = true
	var upgrade := _button("BuildUpgrade" if spells else "BuildUpgrade1")
	upgrade.pressed.connect(upgrade_building)
	buttons.Upgrade = upgrade
	# The upgrade button's art is only the pushed state; its normal face is
	# part of the panel, so the button's caption sits on that bar.
	upgrade_label = _label(Rect2(upgrade.position - sheet_offset(), upgrade.size), 15, TEXT, hud._bold)
	upgrade_label.text = profile.text("CtrlBuildUpgrade" if spells else "CtrlBuildUpgrade1")
	var ok := _button("BuildOk1" if spells else "BuildOk")
	ok.pressed.connect(func(): closed.emit())
	buttons.Ok = ok
	sheet.size = Vector2(500, 520)
	resized.connect(_layout)
	_layout()
	refresh()

## Type2 sits lower by half the spell panel's height.
func sheet_offset() -> Vector2:
	return Vector2.ZERO if spells else Vector2(0, SPELLS_HEIGHT / 2)

func _compose() -> void:
	_pieces.clear()
	var table := profile.table("CutParts")
	var keys: Array = table.keys()
	keys.sort_custom(func(a: Variant, b: Variant): return int(a) < int(b))
	var type := "Type1" if spells else "Type2"
	for key: Variant in keys:
		var row: Dictionary = table[key]
		if str(row.get("Ctrl", "")) != PANEL: continue
		var masks: Variant = row.get("Msk", [])
		if not masks is Array: masks = [masks]
		if masks.has("Res1") or ((masks.has("Type1") or masks.has("Type2")) and not masks.has(type)): continue
		var piece := hud.cut(row, sheet_offset())
		if not piece.is_empty(): _pieces.append(piece)

func _label(rect: Rect2, size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.position = rect.position + sheet_offset()
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

func _button(control: String) -> ELAdventureHud.CutButton:
	var button := ELAdventureHud.CutButton.from_rows(hud, control, sheet_offset())
	var tip := profile.text("CtrlTt" + control)
	if tip != "CtrlTt" + control: button.tooltip_text = tip
	button.place(Vector2.ZERO)
	sheet.add_child(button)
	buttons[control] = button
	return button

func _layout() -> void:
	var factor := hud.scale_factor
	sheet.scale = Vector2(factor, factor)
	sheet.position = (ORIGIN + Vector2(hud.right_shift * 0.5, 0)) * factor

func building() -> Dictionary:
	return state.object(building_id)

## Upgrade costs in resource order; empty when there is no next level.
func costs() -> Array[Dictionary]:
	var item := building()
	if not ELBuildingScreen.upgradable(state, item): return [] as Array[Dictionary]
	return ELBuildingScreen.cost_entries(state, item)

func stock() -> Dictionary:
	return state.players.get(int(building().get("owner", -1)), {}).get("resources", {})

func can_upgrade() -> bool:
	var acting := director.can_move() and director.movement.is_empty()
	return acting and ELBuildingScreen.upgrade_problem(state, state.current_player, building_id).is_empty()

func refresh() -> void:
	var item := building()
	var text := profile.text("CtrlBuildingName")
	var title := ELBuildingScreen.title(profile, item)
	name_label.text = text.replace("%s", title).replace("%d", str(ELBuildingScreen.level(item) + 1)) if text.contains("%s") else "%s %d" % [title, ELBuildingScreen.level(item) + 1]
	# Reduced until the name fits its original box.
	var size := 18
	while size > 11 and hud._bold.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > name_label.size.x: size -= 1
	name_label.add_theme_font_size_override("font_size", size)
	description_label.text = ELBuildingScreen.description(profile, item)
	var available := can_upgrade()
	buttons.Upgrade.visible = available
	upgrade_label.visible = available
	sheet.queue_redraw()

func upgrade_building() -> void:
	if not can_upgrade(): return
	if ELBuildingScreen.upgrade(state, state.current_player, building_id): upgraded.emit(building_id)
	refresh()

## Spells of the laboratory's three tiers; tiers above the level are dimmed.
func spell_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not spells: return result
	var tiers := ELBuildingScreen.spell_tiers(state, building())
	for tier in tiers.size():
		for code: String in tiers[tier]: result.append({"code": code, "open": tier <= ELBuildingScreen.level(building())})
	return result

func spell_rect(index: int) -> Rect2:
	return Rect2(SPELL_CELL + Vector2(SPELL_STEP.x * (index % 5), SPELL_STEP.y * (index / 5)), Vector2(50, 50))

func cost_rect(index: int) -> Rect2:
	return Rect2(COST_ICON + Vector2(COST_STEP * index, 0) + sheet_offset(), Vector2(COST_BOX.end.x - COST_ICON.x, ICON_SIZE))

func draw_sheet() -> void:
	for piece: Dictionary in _pieces: sheet.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var font: Font = hud._bold
	var kinds := ELResources.types("el1")
	var money := stock()
	var entries := costs()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var at := COST_ICON + Vector2(COST_STEP * index, 0) + sheet_offset()
		if _icons != null: sheet.draw_texture_rect_region(_icons, Rect2(at, Vector2(ICON_SIZE, ICON_SIZE)), Rect2(74 + 23 * kinds.find(entry.kind), 0, 23, 23))
		var box := Rect2(COST_BOX.position + Vector2(COST_STEP * index, 0) + sheet_offset(), COST_BOX.size)
		var text := str(int(entry.amount))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var position := Vector2(box.get_center().x - width * 0.5, box.position.y + 14)
		sheet.draw_string(font, position + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
		sheet.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED if int(entry.amount) > int(money.get(entry.kind, 0)) else Color.WHITE)
	var list := spell_entries()
	for index in mini(15, list.size()):
		var icon := profile.card_icon(str(list[index].code))
		if icon != null: sheet.draw_texture_rect(icon, spell_rect(index), false, Color.WHITE if list[index].open else Color(0.45, 0.45, 0.45))

func tooltip_at(point: Vector2) -> String:
	var entries := costs()
	for index in entries.size():
		if cost_rect(index).has_point(point): return profile.text("T_RESOURCE_NAME_%d" % (ELResources.types("el1").find(entries[index].kind) + 1))
	var list := spell_entries()
	for index in mini(15, list.size()):
		if spell_rect(index).has_point(point):
			var row: Dictionary = profile.table("CombatSpells").get(str(list[index].code), {})
			return profile.text(str(row.get("Name", list[index].code))) + "\n" + profile.text(str(row.get("ToolTip", "")))
	return ""

func panel_rect() -> Rect2:
	var top := Vector2(152, 62) + sheet_offset()
	return Rect2(top, Vector2(344, 450 - (0 if spells else SPELLS_HEIGHT)))

class Sheet extends Control:
	var view: ELBuildingScreenView

	func _draw() -> void:
		view.draw_sheet()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and view.panel_rect().has_point(event.position): accept_event()

	func _has_point(point: Vector2) -> bool:
		return view.panel_rect().has_point(point)

	func _get_tooltip(at_position: Vector2) -> String:
		return view.tooltip_at(at_position)
