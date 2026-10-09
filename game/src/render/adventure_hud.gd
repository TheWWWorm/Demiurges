class_name ELAdventureHud
extends Control
## First-game adventure screen composed from the mounted CutParts and Controls
## registries. Coordinates use the original 1024x768 layout: the side panel is
## right-anchored and the resource bar bottom-anchored, as the original 800x600
## controls are shifted for the larger resolution.
signal hero_selected(id: int)
## Double-click on a portrait opens that hero's HeroScreen (message 0x410).
signal hero_opened(id: int)
signal begin_requested
## Buildings list (BuildingsMode): a click centres the map, a double click
## opens the BuildingScreen (messages 0x40f/0x410).
signal building_selected(id: int)
signal building_opened(id: int)
signal minimap_clicked(cell: Vector2)
## Global spells list (GlobalSpellsMode): GSType1..4 list the available spells
## acting on heroes, castles, buildings or resources; a click orders that
## spell without extra ether and GSMode opens the global spells screen.
signal spell_ordered(code: String)
signal spells_opened
## DiplomacyMode opens the full Diplomacy screen and leaves the column alone.
signal diplomacy_opened
const DESIGN_HEIGHT := 768.0
const PANEL_SHIFT := 224
const BOTTOM_SHIFT := 168
const SLOT_COUNT := 8
const MODES := {"HeroesMode": "heroes", "BuildingsMode": "buildings", "GlobalSpellsMode": "spells", "DiplomacyMode": "diplomacy", "OptionsMode": "options"}
const COLUMN := {"heroes": ["NextHero", "HeroInTower", "RemoveHero"], "options": ["Save", "Load", "DisconnectButton", "QuitToMainMenu", "QuitToWindows"],
	"buildings": ["BuildingType1", "BuildingType2", "BuildingType3", "BuildingType4", "BuildingType5"], "spells": ["GSType1", "GSType2", "GSType3", "GSType4", "GSMode"], "diplomacy": []}
const PLAYER_COLORS := {"Red": Color("d23a22"), "Green": Color("4fbf3a"), "Blue": Color("3a78e0"), "Black": Color("9a8fb8")}
const RACES := {"Red": 1, "Green": 2, "Blue": 3, "Black": 4}

var profile: ELProfile
var state: ELAdventureSession
var canvas: Control
var art: Control
var minimap: Control
var minimap_texture: ImageTexture
## Markers above the fog overlay; the overlay shows ELFog for the local player.
var minimap_marks: Control
var minimap_fog: TextureRect
var _fog_textures: Array[ImageTexture] = []
var _fog_revision := -1
const MINIMAP_FOG := """shader_type canvas_item;
uniform sampler2D seen : filter_nearest;
uniform int bit = 1;
void fragment() {
	int known = int(texture(TEXTURE, UV).r * 255.0 + 0.5);
	int now = int(texture(seen, UV).r * 255.0 + 0.5);
	if (((now >> bit) & 1) != 0) COLOR = vec4(0.0);
	else if (((known >> bit) & 1) != 0) COLOR = vec4(0.5, 0.5, 0.5, 0.5);
	else COLOR = vec4(0.0, 0.0, 0.0, 1.0);
}
"""
var slots: Array[PortraitSlot] = []
var buttons: Dictionary = {}
var dial: Dictionary = {}
var income_labels: Array[Label] = []
var stock_labels: Array[Label] = []
var day_label: Label
var tooltip: PanelContainer
var tooltip_title: Label
var tooltip_picture: TextureRect
var tooltip_body: Label
var tooltip_subject := -1
var precombat: Control
var begin_button: CutButton
var precombat_labels: Dictionary = {}
var precombat_portraits: Array[TextureRect] = []
var precombat_pair: Array = []
var remake_strip: VBoxContainer
var mode := "heroes"
var tower_only := false
## BuildingType1..5 choice (0..4) or -1; the list shows that category only.
var building_kind := -1
var listing: Array[int] = []
## GSType filter (0..3) and the availability entries it lists.
var spell_kind := 0
var spell_listing: Array = []
var selected := -1
var roster: Array[int] = []
## First listed entry shown in slot 0: ScrollUp/ScrollDown move the column by
## one entry and are disabled at either end.
var first_entry := 0
var _scroll_key := ""
var _scroll_selected := -1
var scale_factor := 1.0
var right_shift := 0.0
var _paths: Dictionary = {}
var _rows: Dictionary = {}
var _pieces: Array[Dictionary] = []
var _precombat_pieces: Array[Dictionary] = []
var _cell_rects: Array[Rect2] = []
var _blockers: Array[Control] = []
var _italic: FontVariation
var _bold: FontVariation
var _signature := ""
var _art: ELAdventureArt

## Composes the panel and returns false when this edition has no matching art.
func build(source: ELAdventureSession) -> bool:
	state = source
	profile = state.map.profile
	_art = ELAdventureArt.new(state.map)
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		_paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", ""))
	for key: Variant in profile.table("CutParts"):
		var row: Dictionary = profile.table("CutParts")[key]
		var masks: Variant = row.get("Msk", [])
		row = row.duplicate()
		row.masks = masks if masks is Array else [masks]
		if not _rows.has(row.get("Ctrl", "")): _rows[row.get("Ctrl", "")] = []
		_rows[row.get("Ctrl", "")].append(row)
	if not _rows.has("AdvPanel") or not _rows.has("InfoFrame"): return false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var base := ThemeDB.fallback_font
	_italic = FontVariation.new()
	_italic.base_font = base
	_italic.variation_embolden = 0.5
	_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	_bold = FontVariation.new()
	_bold.base_font = base
	_bold.variation_embolden = 0.6
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	art.draw.connect(_draw_art)
	for blocker in 2:
		var stop := Control.new()
		stop.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.add_child(stop)
		_blockers.append(stop)
	remake_strip = VBoxContainer.new()
	remake_strip.add_theme_constant_override("separation", 4)
	canvas.add_child(remake_strip)
	_build_minimap()
	_build_slots()
	_build_buttons()
	_build_bar()
	_build_tooltip()
	_build_precombat()
	resized.connect(_layout)
	_layout()
	return true

func cut(row: Dictionary, offset := Vector2.ZERO) -> Dictionary:
	var texture := profile.texture(_paths.get(row.get("Txt", ""), ""))
	if texture == null: return {}
	return {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH), "rect": Rect2(Vector2(row.ScrL, row.ScrT) + offset, Vector2(row.TxtW, row.TxtH))}

func rows(control: String, required: Array = [], excluded: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows.get(control, []):
		if required.all(func(mask: String): return row.masks.has(mask)) and not excluded.any(func(mask: String): return row.masks.has(mask)): result.append(row)
	return result

## The static frame: every 1024-resolution AdvPanel and InfoFrame piece.
func _layout_pieces() -> void:
	_pieces.clear()
	var panel := Vector2(PANEL_SHIFT + right_shift, 0)
	var bottom := Vector2(0, BOTTOM_SHIFT)
	for row: Dictionary in rows("AdvPanel", [], ["Res1"]) + rows("InfoFrame", [], ["Res1"]):
		var piece := cut(row, panel if row.Ctrl == "AdvPanel" else bottom)
		if not piece.is_empty(): _pieces.append(piece)
	# Wider windows extend the resource bar with its own separator piece.
	var separators := rows("InfoFrame", ["Res2"]).filter(func(row: Dictionary): return row.TxtW == 32)
	if not separators.is_empty() and right_shift > 0 and not cut(separators[0]).is_empty():
		var x := 871.0
		while x < 871.0 + right_shift:
			var piece := cut(separators[0], bottom)
			piece.rect.position.x = x
			piece.rect.size.x = minf(32, 871.0 + right_shift - x)
			piece.source.size.x = piece.rect.size.x
			_pieces.append(piece)
			x += 32

func _draw_art() -> void:
	for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	# Positions without a command in the current mode keep their plugs.
	var used: int = COLUMN[mode].size()
	for row: Dictionary in rows("AdvZaglushki", [], ["Res1"]):
		var piece := cut(row, Vector2(PANEL_SHIFT + right_shift, 9))
		if piece.is_empty() or int((row.ScrT - 173) / 53) < used: continue
		art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)

func _layout() -> void:
	if size.y <= 0: return
	scale_factor = size.y / DESIGN_HEIGHT
	var width := size.x / scale_factor
	right_shift = width - 1024.0
	canvas.scale = Vector2(scale_factor, scale_factor)
	canvas.size = Vector2(width, DESIGN_HEIGHT)
	art.size = canvas.size
	_layout_pieces()
	var panel_x := 858.0 + right_shift
	_blockers[0].position = Vector2(panel_x, 0)
	_blockers[0].size = Vector2(width - panel_x, DESIGN_HEIGHT)
	_blockers[1].position = Vector2(0, 740)
	_blockers[1].size = Vector2(panel_x, 28)
	minimap.position = Vector2(859 + right_shift, 3)
	for index in slots.size(): slots[index].position = Vector2(883 + right_shift, 183 + 53 * index)
	for name: String in buttons: buttons[name].place(Vector2(right_shift, 0))
	for name: String in dial: dial[name].place(Vector2(right_shift, 0))
	for index in _cell_rects.size():
		var cell := _cell_rects[index]
		var top := income_labels[index]
		top.size = Vector2(46, top.get_combined_minimum_size().y)
		top.position = cell.position + Vector2(31, 8.5 - top.size.y * 0.5)
		# Bottom-aligned so the glyphs sit on the bar's lower row inside the screen.
		var stock := stock_labels[index]
		stock.size = Vector2(46, stock.get_combined_minimum_size().y)
		stock.position = cell.position + Vector2(31, minf(20.5 - stock.size.y * 0.5, cell.size.y - stock.size.y))
	day_label.size = Vector2(150, day_label.get_combined_minimum_size().y)
	day_label.position = Vector2(870 + right_shift, DESIGN_HEIGHT - day_label.size.y)
	precombat.position = Vector2(116 + right_shift * 0.5, 286)
	remake_strip.position = Vector2(8, 8)
	remake_strip.size.x = 0
	art.queue_redraw()

## Map area left of the panel and above the bar, in window units.
func map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(858 + right_shift, 740) * scale_factor)

func _build_minimap() -> void:
	minimap = Control.new()
	minimap.size = Vector2(160, 160)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(minimap)
	var map := state.map
	var image := Image.create(maxi(1, map.width), maxi(1, map.height), false, Image.FORMAT_RGB8)
	var colors := _terrain_colors()
	for y in map.height:
		for x in map.width:
			var color: Color = colors.get(map.tile(x, y), Color(0.25, 0.25, 0.22))
			if map.roads.size() > y * map.width + x and map.roads[y * map.width + x] != 0: color = color.lerp(Color("8a6a44"), 0.6)
			image.set_pixel(x, map.height - 1 - y, color)
	minimap_texture = ImageTexture.create_from_image(image)
	minimap.draw.connect(_draw_minimap)
	if ELFog.active(state, state.current_player):
		# The minimap image rows run north-up, so the fog masks are flipped.
		minimap_fog = TextureRect.new()
		minimap_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap_fog.stretch_mode = TextureRect.STRETCH_SCALE
		minimap_fog.flip_v = true
		minimap_fog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var area := _minimap_area()
		minimap_fog.position = area.position
		minimap_fog.size = area.size
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = MINIMAP_FOG
		material.set_shader_parameter("bit", state.current_player)
		minimap_fog.material = material
		minimap.add_child(minimap_fog)
		_sync_minimap_fog()
	minimap_marks = Control.new()
	minimap_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_marks.size = minimap.size
	minimap.add_child(minimap_marks)
	minimap_marks.draw.connect(_draw_minimap_marks)
	minimap.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var area := _minimap_area()
			if area.has_point(event.position):
				var at: Vector2 = (event.position - area.position) / area.size
				minimap_clicked.emit(Vector2(at.x * map.width, (1.0 - at.y) * map.height)))

func _minimap_area() -> Rect2:
	var map := state.map
	var fit := 160.0 / maxf(1, maxf(map.width, map.height))
	var area := Vector2(map.width, map.height) * fit
	return Rect2((Vector2(160, 160) - area) * 0.5, area)

func _terrain_colors() -> Dictionary:
	var result := {}
	var tiles := profile.terrain_tiles
	if tiles == null: return result
	for kind: int in tiles.types:
		var groups: Array = tiles.types[kind].full
		if groups.is_empty() or groups[0].ids.is_empty(): continue
		var id: int = groups[0].ids[0]
		if id < 0 or id >= tiles.pixels.size(): continue
		var bytes: PackedByteArray = tiles.pixels[id]
		var sum := Vector3.ZERO
		var count := 0
		for at in range(0, bytes.size() - 2, 3 * 37):
			sum += Vector3(bytes[at], bytes[at + 1], bytes[at + 2])
			count += 1
		if count > 0: result[kind] = Color(sum.x / count / 255.0, sum.y / count / 255.0, sum.z / count / 255.0)
	return result

func _sync_minimap_fog() -> void:
	if minimap_fog == null or ELFog.revision(state) == _fog_revision: return
	_fog_revision = ELFog.revision(state)
	var size := state.map.width * state.map.height
	var masks: Array[PackedByteArray] = [state.explored, state.fog.get("visible", PackedByteArray())]
	for index in masks.size():
		if masks[index].size() != size:
			masks[index] = PackedByteArray()
			masks[index].resize(size)
		var image := Image.create_from_data(maxi(1, state.map.width), maxi(1, state.map.height), false, Image.FORMAT_R8, masks[index])
		if _fog_textures.size() <= index: _fog_textures.append(ImageTexture.create_from_image(image))
		else: _fog_textures[index].update(image)
	minimap_fog.texture = _fog_textures[0]
	(minimap_fog.material as ShaderMaterial).set_shader_parameter("seen", _fog_textures[1])

func _draw_minimap() -> void:
	minimap.draw_rect(Rect2(Vector2.ZERO, minimap.size), Color.BLACK)
	minimap.draw_texture_rect(minimap_texture, _minimap_area(), false)

## Hero dots appear only on tiles the local player sees; building markers have
## no fog test in the original.
func _draw_minimap_marks() -> void:
	var area := _minimap_area()
	var map := state.map
	var cell := area.size / Vector2(maxf(1, map.width), maxf(1, map.height))
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false) or not item.get("visible", true) or not item.get("placed", true): continue
		var owned: bool = state.players.has(int(item.get("owner", 0)))
		var at := area.position + Vector2(float(item.x) + 0.5, map.height - float(item.y) - 0.5) * cell
		var color: Color = PLAYER_COLORS.get(state.players.get(int(item.get("owner", 0)), {}).get("color", ""), Color("c8c8b8"))
		if ELFirstScenario.is_castle(item): minimap_marks.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), color)
		elif item.get("type") == "hero" and not item.get("fortified", false):
			if ELFog.visible(state, state.current_player, Vector2i(item.x, item.y)): minimap_marks.draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), color)
		elif owned and item.get("group") in ["mines", "mana_nodes", "forts", "additional_buildings"]: minimap_marks.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), color)
	var hero := state.object(selected)
	if not hero.is_empty():
		var at := area.position + Vector2(float(hero.x) + 0.5, map.height - float(hero.y) - 0.5) * cell
		minimap_marks.draw_arc(at, 6, 0, TAU, 20, Color("d8b058"), 1.5)

func _build_slots() -> void:
	for index in SLOT_COUNT:
		var slot := PortraitSlot.new()
		slot.size = Vector2(70, 49)
		canvas.add_child(slot)
		slot.pressed.connect(func():
			if slot.hero < 0: return
			if mode == "buildings": building_selected.emit(slot.hero)
			elif mode == "spells":
				if slot.hero < spell_listing.size(): spell_ordered.emit(str(spell_listing[slot.hero].code))
			else: hero_selected.emit(slot.hero))
		slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.double_click and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and slot.hero >= 0 and not slot.disabled:
				if mode == "buildings": building_opened.emit(slot.hero)
				elif mode != "spells": hero_opened.emit(slot.hero))
		slots.append(slot)

func _build_buttons() -> void:
	for name: String in MODES:
		var button := CutButton.from_rows(self, name, Vector2(PANEL_SHIFT, BOTTOM_SHIFT))
		canvas.add_child(button)
		button.tooltip_text = profile.text("CtrlTt" + name)
		if name == "DiplomacyMode": button.pressed.connect(func(): diplomacy_opened.emit())
		else: button.pressed.connect(func(): set_mode(MODES[name]))
		dial[name] = button
	dial.NextTurn = CutButton.from_rows(self, "NextTurn", Vector2(PANEL_SHIFT, BOTTOM_SHIFT))
	dial.NextTurn.tooltip_text = profile.text("CtrlTtNextTurn") + "  [N]"
	canvas.add_child(dial.NextTurn)
	# The column's scroll arrows (AdvPanel children; ScrollDown sits on the
	# lower panel, 167 px down).
	for name: String in ["ScrollUp", "ScrollDown"]:
		var arrow := CutButton.from_rows(self, name, Vector2(PANEL_SHIFT - (2 if name == "ScrollUp" else 1), 0 if name == "ScrollUp" else 167))
		arrow.disabled = true
		canvas.add_child(arrow)
		buttons[name] = arrow
		arrow.pressed.connect(scroll.bind(-1 if name == "ScrollUp" else 1))
	for list: Array in COLUMN.values():
		for name: String in list:
			var button := CutButton.from_rows(self, name, Vector2(PANEL_SHIFT, 9))
			button.tooltip_text = profile.text("CtrlTt" + name)
			button.disabled = true
			canvas.add_child(button)
			buttons[name] = button
	for kind in ELBuildingScreen.CATEGORIES:
		buttons["BuildingType%d" % (kind + 1)].pressed.connect(func(): building_kind = kind)
	for kind in ELGlobalSpellsView.KINDS.size():
		buttons["GSType%d" % (kind + 1)].pressed.connect(func(): spell_kind = kind)
	buttons.GSMode.pressed.connect(func(): spells_opened.emit())
	set_mode("heroes")

func set_mode(value: String) -> void:
	# Entering the global spells mode selects GSType1 at once.
	if value == "spells" and mode != "spells": spell_kind = 0
	mode = value
	for name: String in dial: dial[name].active = MODES.get(name, "") == mode
	for list_mode: String in COLUMN:
		for name: String in COLUMN[list_mode]: buttons[name].visible = list_mode == mode
	art.queue_redraw()

func _build_bar() -> void:
	var cells := rows("InfoFrame", ["Res2"]).filter(func(row: Dictionary): return row.TxtW == 79)
	cells.sort_custom(func(a: Dictionary, b: Dictionary): return a.ScrL < b.ScrL)
	var kinds := ELResources.types(profile.id)
	for index in cells.size():
		var row: Dictionary = cells[index]
		var rect := Rect2(row.ScrL, row.ScrT + BOTTOM_SHIFT, row.TxtW, row.TxtH)
		_cell_rects.append(rect)
		for line in 2:
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 10)
			label.add_theme_font_override("font", _bold)
			label.add_theme_color_override("font_color", Color("e8e4dc"))
			label.add_theme_constant_override("line_spacing", 0)
			label.size = Vector2(46, 13)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			canvas.add_child(label)
			(income_labels if line == 0 else stock_labels).append(label)
		var hint := Control.new()
		hint.position = rect.position
		hint.size = rect.size
		hint.mouse_filter = Control.MOUSE_FILTER_PASS
		hint.tooltip_text = profile.text("CtrlTtInfoFrame_8") if index >= kinds.size() else profile.text("CtrlTtInfoFrame_1").replace("%s", profile.text("T_RESOURCE_NAME_%d" % (index + 1)))
		canvas.add_child(hint)
	day_label = Label.new()
	day_label.size = Vector2(150, 15)
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	day_label.add_theme_font_override("font", _italic)
	day_label.add_theme_font_size_override("font_size", 12)
	day_label.add_theme_color_override("font_color", Color("e8e4dc"))
	day_label.tooltip_text = profile.text("CtrlTtDayText")
	day_label.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(day_label)

## The original counter: day within a seven-day week, then the week number.
static func day_text(source: ELProfile, day: int) -> String:
	var number := maxi(1, day)
	var format := source.text("CtrlDayText")
	if format == "CtrlDayText": format = "%d Day, %d Week"
	return format % [(number - 1) % 7 + 1, (number - 1) / 7 + 1]

func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.add_theme_stylebox_override("panel", tooltip_style())
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(tooltip)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 3)
	tooltip.add_child(rows_box)
	tooltip_title = Label.new()
	tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_title.add_theme_font_override("font", _italic)
	tooltip_title.add_theme_font_size_override("font_size", 13)
	tooltip_title.add_theme_color_override("font_color", Color("e2d29a"))
	rows_box.add_child(tooltip_title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	rows_box.add_child(columns)
	tooltip_picture = TextureRect.new()
	tooltip_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tooltip_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	columns.add_child(tooltip_picture)
	tooltip_body = Label.new()
	tooltip_body.add_theme_font_override("font", _italic)
	tooltip_body.add_theme_font_size_override("font_size", 13)
	tooltip_body.add_theme_color_override("font_color", Color("e2d29a"))
	tooltip_body.add_theme_constant_override("line_spacing", -1)
	tooltip_body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(tooltip_body)
	tooltip.hide()

static func tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.145, 0.13, 0.94)
	style.border_color = Color("8a857a")
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 2
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 7
	return style

## Original tooltip content for a castle, hero or neutral creature.
func describe(item: Dictionary, art_row: Dictionary) -> Dictionary:
	if item.is_empty() or not item.get("alive", false): return {}
	var lines: Array[String] = []
	if ELFirstScenario.is_castle(item):
		var color := str(state.players.get(int(item.owner), {}).get("color", art_row.get("MagicColor", "")))
		var castle: Dictionary = state.scenario.get("castles", {}).get(int(item.owner), {})
		var race := profile.text("T_RACE_NAME_%d" % int(RACES.get(color, 1)))
		var income := int(item.node.get("attrs", {}).get("mana_income", 6))
		var body := profile.text("T_CASTLE_TT_2")
		if body == "T_CASTLE_TT_2": body = "Owner: %s\nEnergy: %d\nMaximum energy: %d\nEther income: %d"
		var icon := int(art_row.get("Icon", -1))
		return {"title": profile.text("T_CASTLE_TT_1").replace("%s", race), "text": body % [ELFirstScenario.player_name(state, int(item.owner)), int(castle.get("health", 0)), int(castle.get("max", 0)), income],
			"picture": building_icon(icon) if icon >= 0 else null, "picture_size": Vector2(70, 50)}
	if item.get("type") == "hero":
		lines.append("%s: %s" % [profile.text("T_OWNER"), ELFirstScenario.player_name(state, int(item.owner))])
		lines.append("%s: %d" % [profile.text("T_LEVEL"), int(item.get("level", 1))])
		lines.append("%s: %d" % [profile.text("T_LIFE"), int(item.get("health", 0))])
		lines.append("%s: %d" % [profile.text("T_SIGHT"), int(item.get("base_ap", 0))])
		return {"title": str(item.get("title", item.name)), "text": "\n".join(lines), "picture": profile.portrait(int(art_row.get("Face", 0))), "picture_size": Vector2(100, 70)}
	if item.get("group") == "additional_buildings" and profile.id == "el1":
		var row := ELAdditionalBuildings.definition(profile, item)
		var body := profile.text(str(row.get("ToolTip", "")))
		if body == str(row.get("ToolTip", "")): body = ""
		if item.get("addition_version") == ELAdditionalBuildings.VERSION and item.name in ELAdditionalBuildings.OWNED and int(item.owner) >= 0:
			body = ("%s\n%s: %s" % [body, profile.text("T_OWNER"), ELFirstScenario.player_name(state, int(item.owner))]).strip_edges()
		var icon := int(row.get("Icon", -1))
		return {"title": ELAdditionalBuildings.title(profile, item), "text": body, "picture": building_icon(icon) if icon >= 0 else null, "picture_size": Vector2(70, 50) if icon >= 0 else Vector2.ZERO}
	if profile.id == "el1":
		var site := describe_site(item, art_row)
		if not site.is_empty(): return site
	if item.get("group") == "artefacts" and profile.id == "el1":
		return {"title": ELMapPickups.artifact_title(profile, str(item.name)), "text": "", "picture": null, "picture_size": Vector2.ZERO}
	if item.get("group") == "global_spells" and profile.id == "el1":
		var kind := "T_GLOBAL_SPELL_PART" if item.name == ELMapPickups.PART else "T_GLOBAL_SPELL_FULL"
		return {"title": profile.text(kind), "text": "", "picture": null, "picture_size": Vector2.ZERO}
	if item.get("type") == "monster":
		lines.append("%s: %d" % [profile.text("T_LEVEL"), int(item.get("level", 1))])
		lines.append("%s: %d" % [profile.text("T_LIFE"), int(item.get("health", 0))])
		return {"title": str(item.get("title", item.name)), "text": "\n".join(lines), "picture": profile.portrait(int(art_row.get("Icon", 0))), "picture_size": Vector2(100, 70)}
	return {}

## First game: original tooltips of mines, mana nodes, forts, shops and
## resource piles (T_MINE_TT, T_MANA_NODE_TT, T_FORT_TT, T_PLUSHKA).
func describe_site(item: Dictionary, art_row: Dictionary) -> Dictionary:
	var icon := int(art_row.get("Icon", -1))
	var picture: Texture2D = building_icon(icon) if icon >= 0 else null
	var picture_size := Vector2(70, 50) if icon >= 0 else Vector2.ZERO
	match str(item.get("group", "")):
		"mines":
			var amounts := ELResourceSites.production(profile, item)
			var kinds := ELResources.types(profile.id)
			for index in kinds.size():
				if int(amounts[kinds[index]]) > 0:
					return {"title": ELResourceSites.title(profile, item), "text": _format(profile.text("T_MINE_TT"), [int(amounts[kinds[index]]), profile.text("T_RESOURCE_NAME_%d" % (index + 1))]),
						"picture": picture, "picture_size": picture_size}
			return {"title": ELResourceSites.title(profile, item), "text": "", "picture": picture, "picture_size": picture_size}
		"mana_nodes":
			# The amount is the node's yield for the player looking at it.
			var color := str(state.players.get(state.current_player, {}).get("color", ""))
			return {"title": ELResourceSites.title(profile, item), "text": _format(profile.text("T_MANA_NODE_TT"), [ELResourceSites.mana_production(item, color)]),
				"picture": picture, "picture_size": picture_size}
		"forts":
			var title := ELForts.title(profile, item)
			var lines: Array[String] = []
			if int(item.get("owner", -1)) > 0: lines.append("%s: %s" % [profile.text("T_OWNER"), ELFirstScenario.player_name(state, int(item.owner))])
			var hero := state.object(int(item.get("garrison", -1)))
			if not hero.is_empty() and hero.get("alive", false):
				lines.append(_format(profile.text("T_FORT_TT"), [title]))
				lines.append("%s: %d" % [profile.text("T_LEVEL"), int(hero.get("level", 1))])
				lines.append("%s: %d" % [profile.text("T_LIFE"), int(hero.get("health", 0))])
				lines.append("%s: %d" % [profile.text("T_SIGHT"), int(hero.get("base_ap", 0))])
			return {"title": title, "text": "\n".join(lines), "picture": picture, "picture_size": picture_size}
		"laboratories", "factories":
			var row := ELBuildings.definition(profile, item)
			if row.is_empty(): row = art_row
			var description := profile.text(str(row.get("ELKDesc", "")))
			if description == str(row.get("ELKDesc", "")): description = ""
			return {"title": profile.text(str(row.get("ELKName", row.get("Name", "")))), "text": description, "picture": picture, "picture_size": picture_size}
		"resource_cuts":
			var amounts := ELResources.read_node(profile.id, ELXml.child(item.node, "resources"))
			var kinds := ELResources.types(profile.id)
			var text := profile.text("T_PLUSHKA")
			for index in kinds.size():
				if int(amounts[kinds[index]]) > 0: text += "\n   %d %s" % [int(amounts[kinds[index]]), profile.text("T_RESOURCE_NAME_%d" % (index + 1))]
			return {"title": "", "text": text, "picture": null, "picture_size": Vector2.ZERO}
	return {}

## printf-style original text; a text with fewer fields keeps its own words.
static func _format(text: String, values: Array) -> String:
	var fields := text.count("%d") + text.count("%s")
	if fields == 0: return text
	return text % values.slice(0, fields) if fields <= values.size() else text

## Resource picture: the icon at the left of that resource's bar cell.
func resource_icon(kind: String) -> Texture2D:
	var index := ELResources.types(profile.id).find(kind)
	var cells := rows("InfoFrame", ["Res2"]).filter(func(row: Dictionary): return row.TxtW == 79)
	cells.sort_custom(func(a: Dictionary, b: Dictionary): return a.ScrL < b.ScrL)
	if index < 0 or index >= cells.size(): return null
	var row: Dictionary = cells[index]
	var texture := profile.texture(_paths.get(row.get("Txt", ""), ""))
	if texture == null: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(row.TxtL, row.TxtT, 30, row.TxtH)
	atlas.filter_clip = true
	return atlas

## Building pictures: five sheets of 3 x 5 cells of 70 x 50, row-major.
func building_icon(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = profile.texture("Interface/Buildings/Icon_%d" % (index / 15 + 1))
	atlas.region = Rect2((index % 15 % 3) * 70, (index % 15 / 3) * 50, 70, 50)
	atlas.filter_clip = true
	return atlas

## Shows the tooltip near a window position; an empty description hides it.
func show_tooltip(id: int, content: Dictionary, at: Vector2) -> void:
	if content.is_empty():
		tooltip.hide()
		tooltip_subject = -1
		return
	tooltip_subject = id
	tooltip_title.text = content.title
	tooltip_title.visible = not str(content.title).is_empty()
	tooltip_body.text = content.text
	tooltip_picture.texture = content.picture
	tooltip_picture.custom_minimum_size = content.picture_size
	tooltip.reset_size()
	tooltip.show()
	var local := at / scale_factor + Vector2(18, 18)
	var limit := Vector2(858 + right_shift, 740)
	var extent := tooltip.get_combined_minimum_size()
	if local.x + extent.x > limit.x: local.x = maxf(0, at.x / scale_factor - extent.x - 12)
	if local.y + extent.y > limit.y: local.y = maxf(0, at.y / scale_factor - extent.y - 12)
	tooltip.position = local

func _build_precombat() -> void:
	precombat = Control.new()
	precombat.mouse_filter = Control.MOUSE_FILTER_STOP
	precombat.size = Vector2(614, 182)
	canvas.add_child(precombat)
	for row: Dictionary in rows("PrecombatScreen", ["Res2"]):
		var piece := cut(row)
		if not piece.is_empty(): _precombat_pieces.append(piece)
	precombat.draw.connect(_draw_precombat)
	var heading := _text_label(Rect2(160, 0, 320, 25), 14, Color("b8b4aa"), ThemeDB.fallback_font)
	precombat.add_child(heading)
	precombat_labels.heading = heading
	precombat_labels.names = []
	precombat_labels.values = []
	precombat_labels.captions = []
	for side in 2:
		var name := _text_label(Rect2(12, 32, 320, 21) if side == 0 else Rect2(320, 32, 310, 21), 14, Color("f2eee4"), _bold)
		precombat.add_child(name)
		precombat_labels.names.append(name)
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = Vector2(39 if side == 0 else 334, 66)
		portrait.size = Vector2(100, 67)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		precombat.add_child(portrait)
		precombat_portraits.append(portrait)
		var values: Array[Label] = []
		var captions: Array[Label] = []
		for line in 3:
			var value := _text_label(Rect2(0, 0, 33, 17), 11, Color("f2eee4"), _bold)
			precombat.add_child(value)
			values.append(value)
			var caption := _text_label(Rect2(0, 0, 90, 17), 11, Color("f2eee4"), _bold)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			precombat.add_child(caption)
			captions.append(caption)
		precombat_labels.values.append(values)
		precombat_labels.captions.append(captions)
	begin_button = CutButton.new()
	begin_button.hud = self
	var free := rows("BeginCombat", ["Free", "Type1"], ["Light"])
	var push := rows("BeginCombat", ["Push", "Type1"], ["Light"])
	var light := rows("BeginCombat", ["Free", "Light"])
	begin_button.parts = {"normal": cut(free[0]) if not free.is_empty() else {}, "pressed": cut(push[0]) if not push.is_empty() else {}, "hover": cut(light[0]) if not light.is_empty() else {}}
	begin_button.tooltip_text = profile.text("CtrlTtBeginCombat")
	begin_button.place(Vector2.ZERO)
	begin_button.pressed.connect(func(): begin_requested.emit())
	precombat.add_child(begin_button)
	precombat.hide()

func _text_label(rect: Rect2, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _draw_precombat() -> void:
	for piece: Dictionary in _precombat_pieces: precombat.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	# A hero opponent needs the third (Sight) box the creature half omits.
	if precombat_pair.size() == 2 and state.object(precombat_pair[1]).get("type") == "hero":
		var texture := profile.texture(_paths.get("PRECOMBAT_PANEL_3", ""))
		if texture != null: precombat.draw_texture_rect_region(texture, Rect2(446, 62, 40, 73), Rect2(90, 62, 40, 73))

## The "Combat N of M" panel shown before a queued battle starts.
func show_precombat(hero_id: int, opponent_id: int, number: int, total: int) -> void:
	tooltip.hide()
	precombat_pair = [hero_id, opponent_id]
	var format := profile.text("CtrlBattleNumText")
	if format == "CtrlBattleNumText": format = "Combat %d of %d"
	precombat_labels.heading.text = format % [number, total]
	for side in 2:
		var actor := state.object(precombat_pair[side])
		var row: Dictionary = _art.resolve(actor).get("row", {})
		# A lair creature is off the map, so its picture comes from its template.
		if row.is_empty() and actor.get("type") == "monster": row = ELFirstMonsters.definition(profile, str(actor.get("name", "")), int(actor.get("monster_difficulty", 0)))
		precombat_labels.names[side].text = str(actor.get("title", actor.get("name", "")))
		precombat_portraits[side].texture = profile.portrait(int(row.get("Face" if actor.get("type") == "hero" else "Icon", 0)))
		var hero: bool = actor.get("type") == "hero"
		var entries: Array = [["T_LEVEL", int(actor.get("level", 1))], ["T_LIFE", int(actor.get("health", 0))]]
		if hero: entries.append(["T_SIGHT", int(actor.get("base_ap", 0))])
		var box_x := 156.0 if side == 0 else 449.0
		var top := 67.0 if side == 0 or hero else 77.0
		for line in 3:
			var value: Label = precombat_labels.values[side][line]
			var caption: Label = precombat_labels.captions[side][line]
			value.visible = line < entries.size()
			caption.visible = value.visible
			if not value.visible: continue
			value.position = Vector2(box_x, top + line * 23)
			caption.position = Vector2(box_x + 39, top + line * 23)
			value.text = str(entries[line][1])
			caption.text = profile.text(entries[line][0])
	precombat.show()
	precombat.queue_redraw()

func hide_precombat() -> void:
	precombat.hide()
	precombat_pair.clear()

## The map tooltip belongs to the world: leaving the map area hides it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and tooltip.visible:
		var local: Vector2 = event.position / scale_factor
		var strip := Rect2(remake_strip.position, remake_strip.size)
		if not map_rect().has_point(event.position) or strip.has_point(local) or (precombat.visible and Rect2(precombat.position, precombat.size).has_point(local)): show_tooltip(-1, {}, event.position)

## Moves the column by one entry (-1 up, +1 down) within the listed entries.
func scroll(step: int) -> void:
	first_entry = clampi(first_entry + step, 0, maxi(0, _entry_count() - SLOT_COUNT))

func _entry_count() -> int:
	match mode:
		"spells": return spell_listing.size()
		"buildings": return listing.size()
	return roster.size()

## Per-frame refresh; only rebuilds pieces when visible data changed.
func refresh(selected_hero: int, budget: Dictionary, can_act: bool) -> void:
	var player: int = state.current_player
	selected = selected_hero
	roster.clear()
	for actor: Dictionary in state.objects.values():
		if actor.type != "hero" or not actor.alive or not actor.visible or actor.owner != player: continue
		# The filter lists heroes inside a fort or a training camp.
		if tower_only and not ELGlobalSpells.held(actor): continue
		roster.append(int(actor.uid))
	var wallet: Dictionary = state.players.get(player, {}).get("resources", {})
	var income := ELResourceSites.income(state, player)
	var kinds := ELResources.types(profile.id)
	for index in income_labels.size():
		if index < kinds.size():
			income_labels[index].text = str(int(income.get(kinds[index], 0)))
			stock_labels[index].text = str(int(wallet.get(kinds[index], 0)))
		else:
			income_labels[index].text = str(int(budget.get("income", 0)))
			stock_labels[index].text = str(int(budget.get("available", 0)))
	day_label.text = day_text(profile, state.day)
	var hero := state.object(selected)
	buttons.NextHero.disabled = not can_act or roster.size() < 2
	buttons.HeroInTower.disabled = false
	buttons.HeroInTower.active = tower_only
	buttons.RemoveHero.disabled = not can_act or not (hero.get("fortified", false) or int(hero.get("camp", -1)) >= 0)
	buttons.Save.disabled = false
	buttons.Load.disabled = false
	buttons.QuitToMainMenu.disabled = false
	buttons.DisconnectButton.disabled = false
	dial.NextTurn.disabled = not can_act
	# Buildings mode lists the chosen category of the player's buildings.
	listing.clear()
	for kind in ELBuildingScreen.CATEGORIES:
		var button: CutButton = buttons["BuildingType%d" % (kind + 1)]
		var count := ELBuildingScreen.owned(state, player, kind).size()
		button.disabled = count == 0
		button.active = kind == building_kind
	if building_kind >= 0: listing = ELBuildingScreen.owned(state, player, building_kind)
	spell_listing.clear()
	var spells := ELGlobalSpells.applies(state)
	for kind in ELGlobalSpellsView.KINDS.size():
		var button: CutButton = buttons["GSType%d" % (kind + 1)]
		button.disabled = not spells
		button.active = kind == spell_kind
	buttons.GSMode.disabled = not spells
	if spells and mode == "spells":
		for entry: Dictionary in ELMapPickups.availability(state, player):
			if ELGlobalSpells.row(profile, str(entry.code)).get("Type") == ELGlobalSpellsView.KINDS[spell_kind]: spell_listing.append(entry)
	# A new list starts at its top; a newly selected hero is scrolled into view.
	var key := "%s/%d/%d/%s" % [mode, building_kind, spell_kind, tower_only]
	if key != _scroll_key:
		_scroll_key = key
		first_entry = 0
	var count := _entry_count()
	if selected != _scroll_selected:
		_scroll_selected = selected
		var at := roster.find(selected)
		if mode not in ["spells", "buildings"] and at >= 0 and (at < first_entry or at >= first_entry + SLOT_COUNT): first_entry = at - (SLOT_COUNT - 1 if at >= first_entry + SLOT_COUNT else 0)
	first_entry = clampi(first_entry, 0, maxi(0, count - SLOT_COUNT))
	buttons.ScrollUp.disabled = first_entry <= 0
	buttons.ScrollDown.disabled = first_entry + SLOT_COUNT >= count
	for slot_index in slots.size():
		var index := slot_index + first_entry
		if mode == "spells":
			var entry: Dictionary = spell_listing[index] if index < spell_listing.size() else {}
			var picture := ELGlobalSpellsView.entry_icon(profile, entry) if not entry.is_empty() else -1
			slots[slot_index].disabled = not can_act or entry.is_empty()
			if slots[slot_index].hero != (index if not entry.is_empty() else -1) or slots[slot_index].icon_index != picture:
				slots[slot_index].set_hero(-1, null, false)
				slots[slot_index].set_hero(index if not entry.is_empty() else -1, ELGlobalSpellsView.icon(profile, picture) if picture >= 0 else null, false)
				slots[slot_index].tooltip_text = ELGlobalSpells.title(profile, str(entry.code)) if not entry.is_empty() else ""
			slots[slot_index].icon_index = picture
			continue
		if mode == "buildings":
			var building: int = listing[index] if index < listing.size() else -1
			slots[slot_index].disabled = building < 0
			var picture := ELBuildingScreen.icon(profile, state.object(building)) if building >= 0 else -1
			if slots[slot_index].hero != building or slots[slot_index].icon_index != picture:
				slots[slot_index].set_hero(-1, null, false)
				slots[slot_index].set_hero(building, building_icon(picture) if picture >= 0 else null, false)
			slots[slot_index].icon_index = picture
			continue
		# A slot that showed a building or spell picture is cleared first.
		if slots[slot_index].icon_index >= 0: slots[slot_index].set_hero(-1, null, false)
		slots[slot_index].icon_index = -1
		var id: int = roster[index] if index < roster.size() else -1
		slots[slot_index].disabled = not can_act or id < 0
		slots[slot_index].set_hero(id, profile.portrait(int(_art.resolve(state.object(id)).get("row", {}).get("Face", 0))) if id >= 0 and slots[slot_index].hero != id else null, id == selected)
	_sync_minimap_fog()
	var signature := "%d/%d/%d/%d" % [selected, roster.size(), state.day, ELFog.revision(state)]
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero": signature += "/%d,%d,%s" % [item.x, item.y, item.alive]
	if signature != _signature:
		_signature = signature
		minimap_marks.queue_redraw()
	if tooltip.visible and tooltip_subject >= 0 and not state.object(tooltip_subject).get("alive", false): tooltip.hide()

## Original button art: optional normal, pushed and hover-light pieces.
class CutButton extends BaseButton:
	var hud: ELAdventureHud
	var parts: Dictionary = {}
	var active := false:
		set(value):
			active = value
			queue_redraw()
	var _origin := Vector2.ZERO

	static func from_rows(owner: ELAdventureHud, control: String, offset: Vector2) -> CutButton:
		var button := CutButton.new()
		button.hud = owner
		var free := owner.rows(control, ["Free"], ["Light", "Type2"])
		var push := owner.rows(control, ["Push"], ["Light", "Type2"])
		var light := owner.rows(control, ["Light", "Free"])
		var light_push := owner.rows(control, ["Light", "Push"])
		button.parts = {"normal": owner.cut(free[0], offset) if not free.is_empty() else {}, "pressed": owner.cut(push[0], offset) if not push.is_empty() else {},
			"hover": owner.cut(light[0], offset) if not light.is_empty() else {}, "hover_pressed": owner.cut(light_push[0], offset) if not light_push.is_empty() else {}}
		button.name = control
		ELUiSounds.bind(button, owner.profile, control)
		return button

	## Bounds follow the union of the pieces, shifted with the panel.
	func place(shift: Vector2) -> void:
		var bounds := Rect2()
		var first := true
		for part: Dictionary in parts.values():
			if part.is_empty(): continue
			bounds = part.rect if first else bounds.merge(part.rect)
			first = false
		_origin = bounds.position
		position = bounds.position + shift
		size = bounds.size
		queue_redraw()

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED or active
		var base: Dictionary = parts.get("pressed", {}) if pushed and not parts.get("pressed", {}).is_empty() else parts.get("normal", {})
		var tint := Color(0.55, 0.55, 0.55) if disabled else Color.WHITE
		if not base.is_empty(): draw_texture_rect_region(base.texture, Rect2(base.rect.position - _origin, base.rect.size), base.source, tint)
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED):
			var light: Dictionary = parts.get("hover_pressed", {}) if pushed and not parts.get("hover_pressed", {}).is_empty() else parts.get("hover", {})
			if not light.is_empty(): draw_texture_rect_region(light.texture, Rect2(light.rect.position - _origin, light.rect.size), light.source)

## Hero portrait in the side panel; the selected hero gets a light frame.
class PortraitSlot extends BaseButton:
	var hero := -1
	## Building-icon index while the slot lists a building.
	var icon_index := -1
	var picture: Texture2D
	var current := false

	func set_hero(id: int, texture: Texture2D, is_selected: bool) -> void:
		if id != hero:
			hero = id
			picture = texture
			tooltip_text = ""
			queue_redraw()
		if is_selected != current:
			current = is_selected
			queue_redraw()

	func _draw() -> void:
		if hero < 0 or picture == null: return
		draw_texture_rect(picture, Rect2(Vector2.ZERO, size), false)
		if current: draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("e8e0cc"), false, 1.5)
		elif get_draw_mode() == DRAW_HOVER: draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color("a09880"), false, 1.0)
