class_name ELHudFrame
extends Control
## Original interface pieces are composed directly from the mounted CutParts registry.
## The original has two combat panel layouts: the 800x600 one (Res1), with
## the phase caption in a box above the three buttons, and the 1024x768 one
## (Res2), a single row with the caption in an oval beside the buttons and
## nothing over them. A panel at least 1024 wide uses the second when the
## content has its pieces.
const WIDE := 1024.0
const RAIL_LEFT := 151.0
const RAIL_RIGHT := 467.0
## A complete 53 px bay between the original left arrow and the next bay.
const RAIL_TILE := Rect2(31, 0, ELListLook.PITCH, 61)

## Battle interface sizes (setting "battle_interface": 0 automatic, then
## these in order): screen pixels per pixel of the original art. Whole sizes
## draw each original pixel as a sharp square; 1.5 is the one in-between size.
## A smaller size keeps the panel's pieces at their own size and fills the
## width with more card slots instead of stretching.
const SIZES := [1.0, 1.5, 2.0, 3.0]
## The original's narrowest panel layout has to fit across the screen.
const NARROWEST := 800.0
## Automatic: about the size the panel had before the choice (the screen
## width over 1100 original pixels, at most the height over 600), rounded
## down to a listed size (5% leeway).
const AUTO_WIDTH := 1100.0
const AUTO_HEIGHT := 600.0
## On a touch screen a card slot stays at least this wide (millimetres).
const TOUCH_SLOT_MM := 7.0

## Screen pixels per original pixel for `choice` on a `screen` of physical
## pixels; `touch_dpi` > 0 is a touch screen's density (its slots stay big
## enough for a finger).
static func interface_scale(choice: int, screen: Vector2, touch_dpi := 0.0) -> float:
	var wanted: float = SIZES[0]
	if choice >= 1 and choice <= SIZES.size(): wanted = SIZES[choice - 1]
	else:
		var limit := minf(screen.x / AUTO_WIDTH, screen.y / AUTO_HEIGHT) * 1.05
		for size: float in SIZES:
			if size <= limit: wanted = size
	if touch_dpi > 0.0:
		var least := TOUCH_SLOT_MM / 25.4 * touch_dpi / ELListLook.PITCH
		for size: float in SIZES:
			if size * 1.05 >= least:
				wanted = maxf(wanted, size)
				break
	# Never so big that the panel no longer fits across.
	var fit: float = SIZES[0]
	for size: float in SIZES:
		if screen.x / size >= NARROWEST: fit = size
	return minf(wanted, fit)

## Whole sizes draw the art with nearest sampling (sharp squares), 1.5 with
## linear filtering.
static func interface_filter(scale: float) -> CanvasItem.TextureFilter:
	return CanvasItem.TEXTURE_FILTER_NEAREST if is_equal_approx(scale, roundf(scale)) else CanvasItem.TEXTURE_FILTER_LINEAR

## Card slots the hand rail shows at once on a panel `width` original pixels
## wide (the rail runs from its left arrow to its right one).
static func rail_slots(profile: ELProfile, width: float) -> int:
	var rail := maxf(0.0, width - base_width(profile, width)) + RAIL_RIGHT - RAIL_LEFT
	return int((rail + ELListLook.ITEM_GAP) / ELListLook.PITCH)

var pieces: Array[Dictionary] = []
var panel_texture: Texture2D
var has_wide := false

func build(profile: ELProfile) -> void:
	pieces.clear()
	has_wide = false
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", ""))
	for definition: Dictionary in profile.table("CutParts").values():
		if definition.get("Ctrl", "") != "CombatScreen":
			continue
		var masks: String = str(definition.get("Msk", ""))
		if "Res3" in masks or "Type2" in masks:
			continue
		var texture := profile.texture(paths.get(definition.Txt, ""))
		if texture == null:
			continue
		var layout := 2 if "Res2" in masks else (1 if "Res1" in masks else 0)
		has_wide = has_wide or layout == 2
		pieces.append({"texture": texture, "layout": layout,
			"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
			"destination": Rect2(definition.ScrL, definition.ScrT - 600, definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH))})
	panel_texture = profile.texture("Interface/black/combat_panel_1")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

## True when the panel uses the original's 1024 layout at this width.
static func wide_layout(profile: ELProfile, width: float) -> bool:
	if profile == null or width < WIDE: return false
	if not profile.has_meta("combat_panel_wide"):
		var found := false
		for definition: Dictionary in profile.table("CutParts").values():
			if definition.get("Ctrl", "") == "CombatScreen" and "Res2" in str(definition.get("Msk", "")) and not "Type2" in str(definition.get("Msk", "")):
				found = true
				break
		profile.set_meta("combat_panel_wide", found)
	return bool(profile.get_meta("combat_panel_wide"))

## The width the current layout was drawn for: 1024 or 800.
static func base_width(profile: ELProfile, width: float) -> float:
	return WIDE if wide_layout(profile, width) else 800.0

## Moves a point of the original layout to this panel: the bottom rows follow
## the bottom edge; parts the original shifts right in 1024 mode (`shifted`,
## its ShiftX 224 controls) follow the right edge, the rest of the right-hand
## side moves by the extra width over the layout's own.
static func place(rect: Rect2, panel: Vector2, base: float, shifted: bool) -> Rect2:
	rect.position.y += panel.y - 600.0
	if rect.position.x >= 374: rect.position.x += panel.x - (800.0 if shifted else base)
	return rect

func _draw() -> void:
	var wide := has_wide and size.x >= WIDE
	var extra := size.x - (WIDE if wide else 800.0)
	for piece: Dictionary in pieces:
		if piece.layout == (1 if wide else 2):
			continue
		var destination: Rect2 = piece.destination
		destination.position.y += size.y
		if destination.position.x >= 374:
			destination.position.x += extra
		draw_texture_rect_region(piece.texture, destination, piece.source)
	# Continue the original bays at their own pitch between the fixed end caps.
	draw_rail_backing(self, panel_texture, Vector2(RAIL_LEFT - 2, size.y - RAIL_TILE.size.y),
		RAIL_RIGHT - RAIL_LEFT + maxf(0.0, extra) + 4.0, RAIL_TILE)

static func draw_rail_backing(canvas: CanvasItem, texture: Texture2D, at: Vector2, width: float, tile: Rect2) -> void:
	if texture == null: return
	var end := at.x + width
	while at.x < end:
		var tile_size := Vector2(minf(tile.size.x, end - at.x), tile.size.y)
		canvas.draw_texture_rect_region(texture, Rect2(at, tile_size), Rect2(tile.position, tile_size))
		at.x += tile_size.x
