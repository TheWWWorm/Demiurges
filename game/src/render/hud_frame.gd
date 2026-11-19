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
## The card rail's own end: its right arrow housing closes here, and the knot
## after it belongs to the caption.
const RAIL_CLOSE := 488.0

## Battle interface sizes (setting "battle_interface": 0 automatic, then
## these in order): screen pixels per pixel of the original art. Whole sizes
## draw each original pixel as a sharp square; 1.5 is the one in-between size.
## A smaller size keeps the panel's pieces at their own size; the card rail
## keeps the original's slots and the extra width between the rail and the
## caption holds the remake's readouts (ELCombatGapPanel).
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
## linear filtering; a size up to a tenth over a whole one of at least 2 (see
## `snap_scale`) stays sharp too.
static func interface_filter(scale: float) -> CanvasItem.TextureFilter:
	var whole := floorf(scale + 0.001)
	return CanvasItem.TEXTURE_FILTER_NEAREST if is_equal_approx(scale, roundf(scale)) or (whole >= 2.0 and scale - whole <= 0.1 * whole) else CanvasItem.TEXTURE_FILTER_LINEAR

## A panel a little wider than the 800 layout would leave a stub of a gap too
## narrow for the caption (under CAPTION_GAP): such a panel is drawn a little
## bigger instead, exactly 800 wide (at most 9%). The 1024 layout widens its
## caption oval instead (`caption_stretch`).
static func snap_scale(profile: ELProfile, screen: Vector2, pixels: float) -> float:
	var width := ceilf(screen.x / pixels - 0.001)
	var base := base_width(profile, width)
	if base >= WIDE: return pixels
	var gap := rail_trim(profile, width)
	return screen.x / base if gap > 0.0 and gap < CAPTION_GAP else pixels

## Card slots the hand rail shows at once: the original's six, whatever the
## panel's width (the rail runs from its left arrow to its right one).
static func rail_slots(_profile: ELProfile, _width: float) -> int:
	return int((RAIL_RIGHT - RAIL_LEFT + ELListLook.ITEM_GAP) / ELListLook.PITCH)

## Extra panel width past the original layout. The rail keeps its original
## length and its right arrow follows it; this much is left before the
## caption and buttons for ELCombatGapPanel (0 at 800 and 1024).
static func rail_trim(profile: ELProfile, width: float) -> float:
	var rail := maxf(0.0, width - base_width(profile, width)) + RAIL_RIGHT - RAIL_LEFT
	return maxf(0.0, rail + ELListLook.ITEM_GAP - rail_slots(profile, width) * ELListLook.PITCH - 1.0)

## The gap's place on a panel of `size` (empty at the original widths): from
## the rail's closed right end to the caption's frame, as tall as the rail.
## Empty too when the caption takes the extra width (caption_stretch).
static func gap_rect(profile: ELProfile, size: Vector2) -> Rect2:
	var trim := rail_trim(profile, size.x)
	var right := RAIL_CLOSE + size.x - base_width(profile, size.x)
	if caption_stretch(profile, size.x) > 0.0: return Rect2(right - trim, size.y - RAIL_TILE.size.y, 0.0, RAIL_TILE.size.y)
	return Rect2(right - trim, size.y - RAIL_TILE.size.y, trim, RAIL_TILE.size.y)

## The narrowest gap the phase caption moves into (see `caption_in_gap`).
const CAPTION_GAP := 72.0
## The 800 layout's caption box above the buttons and the frame end to its left.
const CAPTION_BOX := Rect2(499, -119, 181, 58)
const CAPTION_BRACKET := Rect2(479, -119, 20, 58)
## Where that frame end goes when the box is not drawn: against the right
## hero's box, as the 1024 layout's own end piece stands.
const HERO_BOX_LEFT := 680.0

## Whether the phase caption is shown in the gap instead of the 800 layout's
## box above the buttons: on a panel a little wider than 800 (a phone at a
## large interface size) whose gap shows no readout, the box goes and the
## buttons' row stands at the rail's height, as in the 1024 layout.
static func caption_in_gap(profile: ELProfile, size: Vector2, readout: bool) -> bool:
	return not wide_layout(profile, size.x) and not readout and gap_rect(profile, size).size.x >= CAPTION_GAP

## The 1024 layout's phase caption oval: its piece and the column at which
## it is widened (the oval's straight middle, under the caption's centre).
const CAPTION_LEFT := 488.0
const CAPTION_RIGHT := 729.0
const CAPTION_MIDDLE := 120.0
## The slice of the oval's middle drawn across the added width.
const CAPTION_SLICE := 8.0

## Extra width too narrow for the readouts (ELCombatGapPanel.MIN_WIDTH: at
## 1600x900 and 1600x1200 the 1.5 size leaves 42 px, at 1680x1050 96, at
## 1152x864 128) went to an empty dark strip (#164). It widens the phase
## caption's oval from its middle instead, so the rail meets the caption as
## in the original and the caption has room for its longest phase names.
static func caption_stretch(profile: ELProfile, width: float) -> float:
	if not wide_layout(profile, width): return 0.0
	var trim := rail_trim(profile, width)
	return trim if trim > 0.0 and trim < ELCombatGapPanel.MIN_WIDTH else 0.0

var pieces: Array[Dictionary] = []
var panel_texture: Texture2D
var has_wide := false
## Set by the view: the caption is in the gap (see `caption_in_gap`).
var caption_moved := false
var _profile: ELProfile

func build(profile: ELProfile) -> void:
	_profile = profile
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
	# Only whole bays: the rails' right ends (their arrow housings, the pieces
	# starting between x 374 and the arrow) close right after the last whole
	# bay, and the leftover is ELCombatGapPanel's.
	var trim := rail_trim(_profile, size.x) if _profile != null else 0.0
	var stretch := caption_stretch(_profile, size.x) if _profile != null and wide else 0.0
	for piece: Dictionary in pieces:
		if piece.layout == (1 if wide else 2):
			continue
		var destination: Rect2 = piece.destination
		destination.position.y += size.y
		var source: Rect2 = piece.source
		if stretch > 0.0 and is_equal_approx(piece.destination.position.x, CAPTION_LEFT) and is_equal_approx(piece.destination.end.x, CAPTION_RIGHT):
			_draw_caption(piece, destination.position + Vector2(extra - stretch, 0), stretch)
			continue
		if destination.position.x < 374:
			draw_texture_rect_region(piece.texture, destination, source)
			continue
		if not wide and caption_moved:
			if piece.destination == CAPTION_BOX: continue
			if piece.destination == CAPTION_BRACKET: destination.position.x = HERO_BOX_LEFT - CAPTION_BRACKET.size.x
		destination.position.x += extra
		var left: float = piece.destination.position.x
		# The rail's part of a bottom-row piece follows the rail (it ends with
		# its arrow housing); the rest, and everything standing taller than
		# the rail, stays with the caption, so the frame end above the rail's
		# end keeps against the caption box.
		var bottom: bool = piece.destination.position.y > -70.0
		if bottom and left < RAIL_CLOSE and trim > 0.0 and piece.destination.position.y >= -RAIL_TILE.size.y:
			var cut := minf(RAIL_CLOSE - left, destination.size.x)
			var scale_x := source.size.x / destination.size.x
			draw_texture_rect_region(piece.texture, Rect2(destination.position - Vector2(trim, 0), Vector2(cut, destination.size.y)), Rect2(source.position, Vector2(cut * scale_x, source.size.y)))
			if cut >= destination.size.x: continue
			destination = Rect2(destination.position + Vector2(cut, 0), destination.size - Vector2(cut, 0))
			source = Rect2(source.position + Vector2(cut * scale_x, 0), source.size - Vector2(cut * scale_x, 0))
		draw_texture_rect_region(piece.texture, destination, source)
	# Continue the original bays at their own pitch between the fixed end caps.
	var at := Vector2(RAIL_LEFT - 2, size.y - RAIL_TILE.size.y)
	var bays := RAIL_RIGHT - RAIL_LEFT + maxf(0.0, extra) + 4.0 - trim
	draw_rail_backing(self, panel_texture, at, bays, RAIL_TILE)

## The caption oval piece at `at`, `stretch` wider: its left part, a slice
## of its middle drawn across the added width, then its right part.
func _draw_caption(piece: Dictionary, at: Vector2, stretch: float) -> void:
	var source: Rect2 = piece.source
	var height: float = piece.destination.size.y
	var scale_x: float = source.size.x / piece.destination.size.x
	var middle := CAPTION_MIDDLE
	draw_texture_rect_region(piece.texture, Rect2(at, Vector2(middle, height)), Rect2(source.position, Vector2(middle * scale_x, source.size.y)))
	var slice := Rect2(source.position + Vector2((middle - CAPTION_SLICE * 0.5) * scale_x, 0), Vector2(CAPTION_SLICE * scale_x, source.size.y))
	draw_texture_rect_region(piece.texture, Rect2(at + Vector2(middle, 0), Vector2(stretch, height)), slice)
	var rest: float = piece.destination.size.x - middle
	draw_texture_rect_region(piece.texture, Rect2(at + Vector2(middle + stretch, 0), Vector2(rest, height)), Rect2(source.position + Vector2(middle * scale_x, 0), Vector2(rest * scale_x, source.size.y)))

static func draw_rail_backing(canvas: CanvasItem, texture: Texture2D, at: Vector2, width: float, tile: Rect2) -> void:
	if texture == null: return
	var end := at.x + width
	while at.x < end:
		var tile_size := Vector2(minf(tile.size.x, end - at.x), tile.size.y)
		canvas.draw_texture_rect_region(texture, Rect2(at, tile_size), Rect2(tile.position, tile_size))
		at.x += tile_size.x
