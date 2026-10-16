class_name ELSecondAdventureHud
extends Control
## Second-game strategic screen composed from the mounted Controls and CutParts
## registries: the bottom-left hero panel (AdvPanelLB: portrait, health, level,
## experience bar, name, three resources, hero bag and notebook buttons), the
## bottom-right panel (AdvPanelRB: minimap, day counter, options button) and the
## Esc menu. Coordinates follow the original 1024x768 layout: each panel adds
## its registry shift to the 800x600 positions; the right panel is anchored to
## the right edge and the Esc menu centred, as ELAdventureHud does for the
## first game. The original defines AdvPanelEndTurnBtn below the screen and
## never creates it, so the remake's next-day command lives in the remake strip
## (without a key: N opens the Notebook, as in the original).
signal inventory_requested
signal notebook_requested
signal options_requested
## Esc menu Options: the original Options screen.
signal original_options_requested
signal centre_requested
signal minimap_clicked(cell: Vector2)
signal save_requested
signal load_requested
signal exit_requested
signal quit_requested
signal menu_closed
## EscEncyclopaedia (0x636): the Encyclopaedia opens over the Esc menu.
signal encyclopaedia_requested
const DESIGN_HEIGHT := 768.0
const LEFT := "AdvPanelLB"
const RIGHT := "AdvPanelRB"
const MENU := "EscMenu"
const MENU_BUTTONS := ["EscSave", "EscLoad", "EscEncyclopaedia", "EscOptions", "EscExitMM", "EscExitWin"]
const UNAVAILABLE := "Not available in the remake yet."
const INK := Color("e6dcc0")
const INK_HOVER := Color("fff4d6")
const INK_DISABLED := Color("8a8478")
const PLAYER_COLORS := {"Red": Color("d23a22"), "Green": Color("4fbf3a"), "Blue": Color("3a78e0"), "Black": Color("9a8fb8"), "White": Color("e8e4dc")}
## CMiniMapA6 (fog colours): unexplored cells are opaque black,
## explored ones are drawn normally; there is no remembered dimming.
const MINIMAP_FOG := """shader_type canvas_item;
uniform int bit = 1;
void fragment() {
	int known = int(texture(TEXTURE, UV).r * 255.0 + 0.5);
	COLOR = ((known >> bit) & 1) != 0 ? vec4(0.0) : vec4(0.0, 0.0, 0.0, 1.0);
}
"""

var profile: ELProfile
var state: ELAdventureSession
var canvas: Control
var art: Control
var minimap: Control
var minimap_texture: ImageTexture
var minimap_fog: TextureRect
var minimap_marks: Control
var portrait: Control
var portrait_texture: Texture2D
var experience_bar: Control
var buttons: Dictionary = {}
var labels: Dictionary = {}
var hints: Dictionary = {}
var remake_strip: VBoxContainer
var menu: Control
var menu_art: Control
var menu_buttons: Dictionary = {}
var scale_factor := 1.0
var right_shift := 0.0
var hero_id := -1
## Times New Roman: only the menu buttons (Controls FontType "Times").
var serif: Font
var serif_bold: Font
## Arial: every other control. The Controls FontType keywords
## pick face 0 (Arial) unless Courier or Times is named; Header, Dark and
## Bold make it bold (``, face table).
var face: Font
var face_bold: Font
var _controls: Dictionary = {}
var _rows: Dictionary = {}
var _paths: Dictionary = {}
var _pieces: Array[Dictionary] = []
var _menu_pieces: Array[Dictionary] = []
var _blockers: Array[Control] = []
var _fog_texture: ImageTexture
var _fog_revision := -1
var _progress := 0.0
var _signature := ""
var _marks := ""
var _art: ELAdventureArt
## Map hover tooltip (ELSecondMapTooltips); above the panel art.
var map_tooltip: ELSecondMapTooltip
var _tooltip_content: Dictionary = {}
## ExBlinkElement on the panel (E_ADV_INVENTORY_BTN, E_ADV_LEVEL, E_ADV_LIFE,
## E_ADV_EXPERIENCE): each toggles every 500 ms and starts lit when set.
const BLINK_PERIOD := 0.5
const BLINK_TINT := Color8(0xff, 0x64, 0x00)
var blinking: Dictionary = {}
var blink_lit := false
var _blink_clock := 0.0

## Composes the panels; returns false when this edition has no matching art.
func build(source: ELAdventureSession) -> bool:
	state = source
	profile = state.map.profile
	_art = ELAdventureArt.new(state.map)
	script_tint = script_transparency(profile)
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		_paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("Controls").values(): _controls[str(row.get("Name", ""))] = row
	for value: Variant in profile.table("CutParts").values():
		var row: Dictionary = value
		var masks: Variant = row.get("Msk", [])
		var copy := row.duplicate()
		copy.masks = masks if masks is Array else [masks]
		if not _rows.has(row.get("Ctrl", "")): _rows[row.get("Ctrl", "")] = []
		_rows[row.get("Ctrl", "")].append(copy)
	if not _rows.has(LEFT) or not _rows.has(RIGHT) or not _controls.has("AdvPanelMapBounds"): return false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
	serif = system
	var bold := SystemFont.new()
	bold.font_names = system.font_names
	bold.font_weight = 700
	serif_bold = bold
	face = ELArtDropList.row_font()
	face.font_weight = 400
	face_bold = ELArtDropList.row_font()
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	art.draw.connect(_draw_art)
	# Clicks on the panel art do not reach the map.
	for blocker in 4:
		var stop := Control.new()
		stop.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.add_child(stop)
		_blockers.append(stop)
	remake_strip = VBoxContainer.new()
	remake_strip.add_theme_constant_override("separation", 4)
	canvas.add_child(remake_strip)
	_build_minimap()
	_build_hero_panel()
	_build_right_panel()
	_build_menu()
	map_tooltip = ELSecondMapTooltip.new()
	map_tooltip.setup(profile, face)
	canvas.add_child(map_tooltip)
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

## The top-level panel a control belongs to (AdvPanelLB, AdvPanelRB, EscMenu).
func family(control: String) -> String:
	var name := control
	for depth in 8:
		var parent := str(_controls.get(name, {}).get("Parent", ""))
		if parent.is_empty() or parent == "Desktop": return name
		name = parent
	return name

## 1024x768 offset of a control: its own and its parents' registry shifts, plus
## the extra width of a wider window (right panel) or half of it (Esc menu).
func shift(control: String) -> Vector2:
	var result := Vector2.ZERO
	var name := control
	for depth in 8:
		var row: Dictionary = _controls.get(name, {})
		if row.is_empty(): break
		result += Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))
		name = str(row.get("Parent", ""))
	match family(control):
		RIGHT: result.x += right_shift
		MENU: result.x += right_shift * 0.5
	return result

func control_rect(control: String) -> Rect2:
	var row: Dictionary = _controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + shift(control), Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func text(key: String) -> String:
	return profile.text(key)

func tooltip_of(control: String) -> String:
	var key := str(_controls.get(control, {}).get("ToolTip", ""))
	return "" if key.is_empty() else text(key)

func _layout_pieces() -> void:
	_pieces.clear()
	for panel: String in [LEFT, RIGHT]:
		for row: Dictionary in rows(panel):
			var piece := cut(row, shift(panel))
			if not piece.is_empty(): _pieces.append(piece)
	_menu_pieces.clear()
	for row: Dictionary in rows(MENU):
		var piece := cut(row, shift(MENU))
		if not piece.is_empty(): _menu_pieces.append(piece)

func _draw_art() -> void:
	for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)

func _layout() -> void:
	if size.y <= 0: return
	scale_factor = size.y / DESIGN_HEIGHT
	var width := maxf(1024.0, size.x / scale_factor)
	right_shift = width - 1024.0
	canvas.scale = Vector2(scale_factor, scale_factor)
	canvas.size = Vector2(width, DESIGN_HEIGHT)
	art.size = canvas.size
	_layout_pieces()
	var left := shift(LEFT)
	var right := shift(RIGHT)
	# Lower strips and the statue columns above them (800x600 art bounds).
	var areas := [Rect2(Vector2(0, 539) + left, Vector2(335, 61)), Rect2(Vector2(0, 384) + left, Vector2(150, 155)),
		Rect2(Vector2(465, 539) + right, Vector2(335, 61)), Rect2(Vector2(649, 386) + right, Vector2(151, 153))]
	for index in _blockers.size():
		_blockers[index].position = areas[index].position
		_blockers[index].size = areas[index].size
	var bounds := control_rect("AdvPanelMapBounds")
	minimap.position = bounds.position
	minimap.size = bounds.size
	minimap_marks.size = bounds.size
	if minimap_fog != null:
		var area := minimap_area()
		minimap_fog.position = area.position
		minimap_fog.size = area.size
	portrait.position = control_rect("AdvPanelHeroPortrait").position
	portrait.size = control_rect("AdvPanelHeroPortrait").size
	experience_bar.position = control_rect("AdvPanelBarBounds").position
	experience_bar.size = control_rect("AdvPanelBarBounds").size
	for control: String in labels:
		labels[control].position = control_rect(control).position
		labels[control].size = control_rect(control).size
	for control: String in hints:
		hints[control].position = control_rect(control).position
		hints[control].size = control_rect(control).size
	for control: String in buttons: buttons[control].place(shift(control))
	menu.size = canvas.size
	menu_art.size = canvas.size
	for control: String in menu_buttons: menu_buttons[control].place(shift(control))
	var header: Label = menu.get_node("EscHdr")
	header.position = control_rect("EscHdr").position
	header.size = control_rect("EscHdr").size
	remake_strip.position = Vector2(8, 8)
	remake_strip.size.x = 0
	art.queue_redraw()
	menu_art.queue_redraw()

# --- Minimap ------------------------------------------------------------------

func _build_minimap() -> void:
	minimap = Control.new()
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.name = "Minimap"
	canvas.add_child(minimap)
	# The map's authored picture (<map>.bm1). Without one the original draws
	# nothing here: no picture, fog or markers over the panel artwork.
	var image := ELMinimapPicture.load_for(state.map)
	minimap_texture = ImageTexture.create_from_image(image) if image != null else null
	minimap.draw.connect(_draw_minimap)
	if minimap_texture != null and ELFog.active(state, state.current_player):
		# The minimap image rows run north-up, so the explored mask is flipped.
		minimap_fog = TextureRect.new()
		minimap_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap_fog.stretch_mode = TextureRect.STRETCH_SCALE
		minimap_fog.flip_v = true
		minimap_fog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = MINIMAP_FOG
		material.set_shader_parameter("bit", state.current_player)
		minimap_fog.material = material
		minimap.add_child(minimap_fog)
	minimap_marks = Control.new()
	minimap_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.add_child(minimap_marks)
	minimap_marks.draw.connect(_draw_minimap_marks)
	minimap.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell := minimap_cell(event.position)
			if cell.x >= 0: minimap_clicked.emit(cell))

## Fitted map image inside the minimap bounds (centred, aspect kept).
func minimap_area() -> Rect2:
	var map := state.map
	var bounds := minimap.size if minimap.size.x > 0 else Vector2(130, 130)
	var fit := minf(bounds.x, bounds.y) / maxf(1, maxf(map.width, map.height))
	var area := Vector2(map.width, map.height) * fit
	return Rect2((bounds - area) * 0.5, area)

## Map cell under a minimap point, or (-1, -1) outside the image.
func minimap_cell(point: Vector2) -> Vector2:
	var area := minimap_area()
	if not area.has_point(point): return Vector2(-1, -1)
	var at := (point - area.position) / area.size
	return Vector2(at.x * state.map.width, (1.0 - at.y) * state.map.height)

func _sync_minimap_fog() -> void:
	if minimap_fog == null or ELFog.revision(state) == _fog_revision: return
	_fog_revision = ELFog.revision(state)
	var cells := state.map.width * state.map.height
	var mask := state.explored
	if mask.size() != cells:
		mask = PackedByteArray()
		mask.resize(cells)
	var image := Image.create_from_data(maxi(1, state.map.width), maxi(1, state.map.height), false, Image.FORMAT_R8, mask)
	if _fog_texture == null: _fog_texture = ImageTexture.create_from_image(image)
	else: _fog_texture.update(image)
	minimap_fog.texture = _fog_texture

func _draw_minimap() -> void:
	if minimap_texture == null: return
	minimap.draw_rect(Rect2(Vector2.ZERO, minimap.size), Color.BLACK)
	minimap.draw_texture_rect(minimap_texture, minimap_area(), false)

## Hero and owned-site markers are drawn only on cells the local player sees
## (the original second-game markers test the visible bit).
func _draw_minimap_marks() -> void:
	if minimap_texture == null: return
	var area := minimap_area()
	var map := state.map
	var cell := area.size / Vector2(maxf(1, map.width), maxf(1, map.height))
	var player := state.current_player
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false) or not item.get("visible", true) or not item.get("placed", true): continue
		var at := area.position + Vector2(float(item.x) + 0.5, map.height - float(item.y) - 0.5) * cell
		var owner := int(item.get("owner", 0))
		var color: Color = PLAYER_COLORS.get(str(state.players.get(owner, {}).get("color", "")), Color("c8c8b8"))
		if not ELFog.visible(state, player, Vector2i(int(item.x), int(item.y))): continue
		if item.get("type") == "hero": minimap_marks.draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), color)
		elif state.players.has(owner) and owner > 0 and ELResourceSites.TYPES.has(str(item.get("group", ""))): minimap_marks.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), color)
	var hero := state.object(hero_id)
	if not hero.is_empty():
		var at := area.position + Vector2(float(hero.x) + 0.5, map.height - float(hero.y) - 0.5) * cell
		minimap_marks.draw_arc(at, 5, 0, TAU, 20, Color("d8b058"), 1.5)

# --- Hero panel ---------------------------------------------------------------

func _label(control: String, font: Font, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var row: Dictionary = _controls.get(control, {})
	var label := Label.new()
	label.name = control
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", font)
	# Registry font sizes are cell heights; the glyphs fit a slightly smaller size.
	label.add_theme_font_size_override("font_size", maxi(10, int(row.get("FontSize", 16)) - 3))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.tooltip_text = tooltip_of(control)
	# Tooltip areas sit on the panel art: they keep the pointer off the map.
	label.mouse_filter = Control.MOUSE_FILTER_STOP if not label.tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	labels[control] = label
	return label

## Tooltip-only areas (the heart, level and resource icons).
func _hint(control: String) -> void:
	var hint := Control.new()
	hint.name = control
	hint.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.tooltip_text = tooltip_of(control)
	canvas.add_child(hint)
	hints[control] = hint

func _build_hero_panel() -> void:
	for control: String in ["AdvPanelLifeTT", "AdvPanelLevelTT", "AdvPanelRes1TT", "AdvPanelRes2TT", "AdvPanelRes3TT"]: _hint(control)
	portrait = Control.new()
	portrait.name = "AdvPanelHeroPortrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(portrait)
	portrait.draw.connect(func():
		if portrait_texture != null: portrait.draw_texture_rect(portrait_texture, Rect2(Vector2.ZERO, portrait.size), false))
	# A double-click on the portrait centres the view on the hero (0x203).
	portrait.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.double_click and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: centre_requested.emit())
	experience_bar = Control.new()
	experience_bar.name = "AdvPanelBarBounds"
	experience_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(experience_bar)
	experience_bar.draw.connect(func():
		var rect := Rect2(Vector2.ZERO, experience_bar.size)
		experience_bar.draw_rect(rect, Color(0.05, 0.05, 0.04, 0.9))
		var fill := BLINK_TINT if blink_lit and blinking.has("E_ADV_EXPERIENCE") else Color("c9a24a")
		experience_bar.draw_rect(Rect2(Vector2(1, 1), Vector2(maxf(0, (rect.size.x - 2) * _progress), rect.size.y - 2)), fill))
	_label("AdvPanelLifeDig", face_bold, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_label("AdvPanelLevelDig", face_bold, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_label("AdvPanelHeroNameText", face_bold, INK)
	for index in 3: _label("AdvPanelRes%dText" % (index + 1), face_bold, INK)
	_label("AdvPanelDayText", face_bold, INK)
	buttons.AdvPanelHandBagBtn = PanelButton.make(self, "AdvPanelHandBagBtn")
	buttons.AdvPanelHandBagBtn.pressed.connect(func(): inventory_requested.emit())
	# Notebook (id 0x7c, accelerator N): ELSecondNotebookView.
	buttons.AdvPanelNotesBtn = PanelButton.make(self, "AdvPanelNotesBtn")
	buttons.AdvPanelNotesBtn.pressed.connect(func(): notebook_requested.emit())
	for control: String in ["AdvPanelHandBagBtn", "AdvPanelNotesBtn"]: canvas.add_child(buttons[control])

func _build_right_panel() -> void:
	buttons.AdvPanelOptionsBtn = PanelButton.make(self, "AdvPanelOptionsBtn")
	buttons.AdvPanelOptionsBtn.pressed.connect(func(): options_requested.emit())
	canvas.add_child(buttons.AdvPanelOptionsBtn)

## The day counter: T_ADV_PANEL_DAY_TEXT with the zero-based date plus one.
static func day_text(source: ELProfile, day: int) -> String:
	var format := source.text("T_ADV_PANEL_DAY_TEXT")
	if format == "T_ADV_PANEL_DAY_TEXT" or not format.contains("%d"): format = "Day: %d"
	return format % (day + 1)

## Experience tooltip: this level's threshold, the current amount and
## the next level's threshold.
func level_tooltip(hero: Dictionary) -> String:
	var format := text("T_ADV_PANEL_TT_LEVEL")
	var level := int(hero.get("level", 1))
	var values := [level, ELHeroProgression.threshold(profile, level), ELHeroProgression.effective(hero), level + 1, ELHeroProgression.threshold(profile, level + 1)]
	if format == "T_ADV_PANEL_TT_LEVEL" or format.count("%d") != 5: return "Experience %d / %d" % [values[2], values[4]]
	return format % values

func refresh(hero_uid: int, can_act: bool) -> void:
	hero_id = hero_uid
	var hero := state.object(hero_id)
	var level := int(hero.get("level", 1))
	labels.AdvPanelLifeDig.text = str(int(hero.get("health", 0)))
	labels.AdvPanelLevelDig.text = str(level)
	labels.AdvPanelHeroNameText.text = str(hero.get("title", hero.get("name", "")))
	var wallet: Dictionary = state.players.get(state.current_player, {}).get("resources", {})
	var kinds := ELResources.types(profile.id)
	for index in 3: labels["AdvPanelRes%dText" % (index + 1)].text = str(int(wallet.get(kinds[index], 0))) if index < kinds.size() else ""
	labels.AdvPanelDayText.text = day_text(profile, state.day)
	var low := ELHeroProgression.threshold(profile, level)
	var high := ELHeroProgression.threshold(profile, level + 1)
	var progress := clampf(float(ELHeroProgression.effective(hero) - low) / float(maxi(1, high - low)), 0, 1) if level < ELHeroProgression.MAX_LEVEL else 1.0
	var tip := level_tooltip(hero) if not hero.is_empty() else ""
	experience_bar.tooltip_text = tip
	labels.AdvPanelLevelDig.tooltip_text = tip
	if progress != _progress:
		_progress = progress
		experience_bar.queue_redraw()
	var face: Texture2D = null
	if not hero.is_empty():
		var row: Dictionary = _art.resolve(hero).get("row", {})
		if row.has("Face"): face = profile.portrait(int(row.Face))
	var signature := "%d/%d/%s" % [hero_id, int(_art.resolve(hero).get("row", {}).get("Face", -1)) if not hero.is_empty() else -1, hero.get("alive", false)]
	if signature != _signature:
		_signature = signature
		portrait_texture = face
		portrait.queue_redraw()
	buttons.AdvPanelHandBagBtn.disabled = not can_act or hero.is_empty()
	_sync_minimap_fog()
	var marks := "%d/%d" % [hero_id, ELFog.revision(state)]
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero": marks += "/%d,%d,%s" % [item.x, item.y, item.alive]
	if marks != _marks:
		_marks = marks
		minimap_marks.queue_redraw()

# --- Highlights ---------------------------------------------------------------

func set_blink(element: String, on: bool) -> void:
	if on:
		blinking[element] = true
		blink_lit = true
		_blink_clock = 0.0
	else: blinking.erase(element)
	_apply_blink()

## ScriptTransparency: while a script holds the map (exclusive flag or queued
## commands) the two panels draw in this colour (settings.ini, ARGB hex,
## shipped 80FFFFFF = half-transparent white), at once, without a fade. A
## value that is not eight hex digits gives opaque red, as in the original.
const SCRIPT_TINT_FALLBACK := Color(1, 0, 0, 1)
var script_tint := Color(1, 1, 1, 128.0 / 255.0)
var script_tinted := false

static func script_transparency(source: ELProfile) -> Color:
	var path := source.file("settings.ini")
	if path.is_empty() or not FileAccess.file_exists(path): return SCRIPT_TINT_FALLBACK
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("ScriptTransparency="): continue
		var value := line.get_slice("=", 1).strip_edges()
		if value.length() != 8 or not value.is_valid_hex_number(): return SCRIPT_TINT_FALLBACK
		var argb := value.hex_to_int()
		return Color8((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff, (argb >> 24) & 0xff)
	return SCRIPT_TINT_FALLBACK

func sync_script_tint() -> void:
	var busy := state != null and (state.exclusive or not state.commands.is_empty())
	if busy == script_tinted: return
	script_tinted = busy
	for child: Node in canvas.get_children():
		if child == menu or child == map_tooltip or child == remake_strip or not child is CanvasItem: continue
		(child as CanvasItem).modulate = script_tint if busy else Color.WHITE

func _process(delta: float) -> void:
	if canvas != null: sync_script_tint()
	if blinking.is_empty(): return
	_blink_clock += delta
	if _blink_clock < BLINK_PERIOD: return
	_blink_clock = fmod(_blink_clock, BLINK_PERIOD)
	blink_lit = not blink_lit
	_apply_blink()

func _apply_blink() -> void:
	if labels.has("AdvPanelLifeDig"): labels.AdvPanelLifeDig.add_theme_color_override("font_color", BLINK_TINT if blink_lit and blinking.has("E_ADV_LIFE") else INK)
	if labels.has("AdvPanelLevelDig"): labels.AdvPanelLevelDig.add_theme_color_override("font_color", BLINK_TINT if blink_lit and blinking.has("E_ADV_LEVEL") else INK)
	if buttons.has("AdvPanelHandBagBtn"):
		buttons.AdvPanelHandBagBtn.blink = blink_lit and blinking.has("E_ADV_INVENTORY_BTN")
		buttons.AdvPanelHandBagBtn.queue_redraw()
	if experience_bar != null: experience_bar.queue_redraw()

# --- Esc menu -----------------------------------------------------------------

func _build_menu() -> void:
	menu = Control.new()
	menu.name = "EscMenu"
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(menu)
	menu_art = Control.new()
	menu_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(menu_art)
	menu_art.draw.connect(func():
		menu_art.draw_rect(Rect2(Vector2.ZERO, menu_art.size), Color(0, 0, 0, 0.45))
		for piece: Dictionary in _menu_pieces: menu_art.draw_texture_rect_region(piece.texture, piece.rect, piece.source))
	var header := Label.new()
	header.name = "EscHdr"
	header.text = text("CtrlEscHdr")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", serif_bold)
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", INK)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(header)
	var widest := 0.0
	for control: String in MENU_BUTTONS: widest = maxf(widest, serif.get_string_size(_caption(control), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x)
	var width := clampf(ceilf(widest + 64.0), 140.0, 400.0)
	for control: String in MENU_BUTTONS:
		var button := EscButton.make(self, control, width)
		if button == null: continue
		menu.add_child(button)
		menu_buttons[control] = button
	menu_buttons.EscCancel = PanelButton.make(self, "EscCancel")
	menu.add_child(menu_buttons.EscCancel)
	if menu_buttons.has("EscOptions"): menu_buttons.EscOptions.pressed.connect(func(): original_options_requested.emit())
	if menu_buttons.has("EscEncyclopaedia"): menu_buttons.EscEncyclopaedia.pressed.connect(func(): encyclopaedia_requested.emit())
	if menu_buttons.has("EscSave"): menu_buttons.EscSave.pressed.connect(func(): save_requested.emit())
	if menu_buttons.has("EscLoad"): menu_buttons.EscLoad.pressed.connect(func(): load_requested.emit())
	if menu_buttons.has("EscExitMM"): menu_buttons.EscExitMM.pressed.connect(func(): exit_requested.emit())
	if menu_buttons.has("EscExitWin"): menu_buttons.EscExitWin.pressed.connect(func(): quit_requested.emit())
	menu_buttons.EscCancel.pressed.connect(func(): menu_closed.emit())
	menu.hide()

func _caption(control: String) -> String:
	return text(str(_controls.get(control, {}).get("Text", "Ctrl" + control))).replace("  ", " ")

func show_menu(value: bool) -> void:
	menu.visible = value
	if value:
		menu.move_to_front()
		hide_map_tooltip()

## Shows the map tooltip for a cursor position in window pixels.
func show_map_tooltip(id: int, content: Dictionary, at: Vector2) -> void:
	if content.is_empty():
		hide_map_tooltip()
		return
	if id != map_tooltip.subject or not map_tooltip.visible or content != _tooltip_content:
		_tooltip_content = content
		map_tooltip.set_content(id, content)
	map_tooltip.place(at / scale_factor, size / scale_factor)
	if not map_tooltip.visible:
		map_tooltip.move_to_front()
		map_tooltip.show()

func hide_map_tooltip() -> void:
	if map_tooltip == null: return
	map_tooltip.hide()
	map_tooltip.subject = -1
	_tooltip_content = {}

## Original button art: normal, pushed, lit and disabled pieces.
class PanelButton extends BaseButton:
	var parts: Dictionary = {}
	## ExBlinkElement lit phase: the lit piece is drawn as on hover (state bit
	##  of the button blinker).
	var blink := false
	var _origin := Vector2.ZERO

	static func make(owner: ELSecondAdventureHud, control: String) -> PanelButton:
		var button := PanelButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		var pick := func(required: Array, excluded: Array) -> Dictionary:
			var found := owner.rows(control, required, excluded)
			return owner.cut(found[0]) if not found.is_empty() else {}
		button.parts = {"normal": pick.call(["Free"], ["Light"]), "pressed": pick.call(["Push"], ["Light"]),
			"hover": pick.call(["Free", "Light"], []), "hover_pressed": pick.call(["Push", "Light"], []), "disabled": pick.call(["Disabled"], [])}
		button.tooltip_text = owner.tooltip_of(control)
		return button

	## Bounds follow the union of the pieces, moved by the control's shift.
	func place(offset: Vector2) -> void:
		var bounds := Rect2()
		var first := true
		for part: Dictionary in parts.values():
			if part.is_empty(): continue
			bounds = part.rect if first else bounds.merge(part.rect)
			first = false
		_origin = bounds.position
		position = bounds.position + offset
		size = bounds.size
		queue_redraw()

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var base: Dictionary = parts.normal
		if disabled: base = parts.disabled if not parts.disabled.is_empty() else parts.normal
		elif pushed and not parts.pressed.is_empty(): base = parts.pressed
		_piece(base, Color(0.6, 0.6, 0.6) if disabled and parts.disabled.is_empty() else Color.WHITE)
		# Lit pieces are whole lit buttons on the hero panel and an overlay on
		# the Esc menu's cancel button; drawing them over the base serves both.
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED):
			_piece(parts.hover_pressed if pushed and not parts.hover_pressed.is_empty() else parts.hover, Color.WHITE)
		elif blink: _piece(parts.hover, Color.WHITE)

	func _piece(part: Dictionary, tint: Color) -> void:
		if not part.is_empty(): draw_texture_rect_region(part.texture, Rect2(part.rect.position - _origin, part.rect.size), part.source, tint)

## Esc-menu text button: left cap, stretched middle and right cap (Type5/6/7),
## with the caption from the text tables, centred on the panel like the original.
class EscButton extends BaseButton:
	var hud: ELSecondAdventureHud
	var caption := ""
	var states: Dictionary = {}
	var design := Rect2()

	static func make(owner: ELSecondAdventureHud, control: String, width: float) -> EscButton:
		var lefts := owner.rows(control, ["Free", "Type5"], ["Light"])
		if lefts.is_empty(): return null
		var button := EscButton.new()
		button.hud = owner
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		button.caption = owner._caption(control)
		var row: Dictionary = owner._controls.get(control, {})
		button.design = Rect2(float(row.get("Left", lefts[0].ScrL)), float(row.get("Top", lefts[0].ScrT)), width, 57)
		for state: String in ["normal", "pressed", "hover", "hover_pressed"]:
			var required: Array = {"normal": ["Free"], "pressed": ["Push"], "hover": ["Free", "Light"], "hover_pressed": ["Push", "Light"]}[state]
			var excluded: Array = [] if state.begins_with("hover") else ["Light"]
			var parts: Array[Dictionary] = []
			for type: String in ["Type5", "Type6", "Type7"]:
				var found := owner.rows(control, required + [type], excluded)
				if found.is_empty(): continue
				var piece := owner.cut(found[0])
				if piece.is_empty(): continue
				piece.type = type
				parts.append(piece)
			button.states[state] = parts
		return button

	## The column stays centred on the original 140-unit button.
	func place(offset: Vector2) -> void:
		size = Vector2(design.size.x, 57)
		position = Vector2(design.position.x + 70.0 - design.size.x * 0.5, design.position.y) + offset
		queue_redraw()

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var tint := Color(0.6, 0.6, 0.6) if disabled else Color.WHITE
		_parts(states.get("pressed" if pushed else "normal", []), tint)
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED): _parts(states.get("hover_pressed" if pushed else "hover", []), Color.WHITE)
		var color := INK_DISABLED if disabled else (INK_HOVER if mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED else INK)
		var font := hud.serif
		var font_size := 22
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := Vector2((size.x - text_size.x) * 0.5, (size.y - text_size.y) * 0.5 + font.get_ascent(font_size) + (1.0 if pushed else 0.0))
		draw_string(font, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.85))
		draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _parts(parts: Array, tint: Color) -> void:
		var left := design.position.x
		for part: Dictionary in parts:
			var rect: Rect2 = part.rect
			var x: float = rect.position.x - left
			var width: float = rect.size.x
			if part.type == "Type6": width += size.x - 140.0
			elif part.type == "Type7": x = size.x - (left + 140.0 - rect.position.x)
			draw_texture_rect_region(part.texture, Rect2(Vector2(x, rect.position.y - design.position.y), Vector2(width, rect.size.y)), part.source, tint)
