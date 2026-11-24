class_name ELBlazonArt
extends RefCounted

## All logo sheets use six columns of 41-pixel cells. The first custom
## sheet retains the starter logos' saved IDs and the second fills the picker.
const CELL := 41.0
const COLUMNS := 6
const STOCK_SHEET_SIZE := COLUMNS * COLUMNS
const EXTRA_LOGO_FIRST := ELPlayerProfile.STARTER_LOGO_FIRST + 12
const STARTER_ATLAS := preload("res://assets/blazon/el1_starter_logos.png")
const EXTRA_ATLAS := preload("res://assets/blazon/el1_extra_logos.png")

static func cell_rect(cell: int) -> Rect2:
	return Rect2(CELL * (cell % COLUMNS), CELL * (cell / COLUMNS), CELL, CELL)

static func logo_region(logo: int) -> Rect2:
	return cell_rect(logo - EXTRA_LOGO_FIRST if logo >= EXTRA_LOGO_FIRST else logo % STOCK_SHEET_SIZE)

static func logo_texture(profile: ELProfile, logo: int) -> Texture2D:
	if logo < 0 or logo >= ELPlayerProfile.LOGOS: return null
	if logo >= EXTRA_LOGO_FIRST: return EXTRA_ATLAS
	if logo >= ELPlayerProfile.STARTER_LOGO_FIRST: return STARTER_ATLAS
	return profile.texture("Interface/Blazon/logo%02d" % (logo / STOCK_SHEET_SIZE))

static func draw_logo(canvas: CanvasItem, profile: ELProfile, logo: int, at: Vector2) -> void:
	var texture := logo_texture(profile, logo)
	if texture != null:
		canvas.draw_texture_rect_region(texture, Rect2(at, Vector2(CELL, CELL)), logo_region(logo))
