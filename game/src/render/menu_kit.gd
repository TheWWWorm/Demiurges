class_name ELMenuKit
extends RefCounted
## Pieces of the original interface for the remake's own screens. The kit reads
## the mounted game's CutParts, Controls and InterfaceTextures tables once and
## cuts frames, buttons, check boxes, sliders and drop-down bars from them, so
## a screen the originals never had can still look like one of theirs.
##
## `theme()` dresses stock Godot controls (AcceptDialog, Button, OptionButton,
## CheckButton, HSlider, TabContainer, ScrollContainer) at once; `section()`
## gives a titled group in the Options screen's header strip. A game without
## the pieces a look needs returns null from `theme()`, and the caller keeps
## its own look.

## Header and body text of the original panels.
const TITLE_INK := Color("d6bb88")
const BODY_INK := Color("d8d2c0")
const NOTE_INK := Color("a39674")
const HOVER_INK := Color("fff4d6")
const DISABLED_INK := Color("8a8478")

## Pieces per game. Rectangles in "panel" are in the composed panel's own
## pixels (its top-left piece at 0,0); the others are texture regions.
const ART := {
	"el1": {
		# The Options screen, its Type1 pieces (right tab lit).
		"panel": "Options",
		"panel_exclude": ["Type2"],
		# Inside the outer chain border: the inner double line and the bottom
		# corner flourishes go to stone, so the sides tile cleanly.
		"frame_inside": Rect2i(12, 20, 540, 501),
		"frame_margins": [56, 26, 56, 16],
		# The clean middle of the right column box.
		"stone": Rect2i(296, 100, 232, 352),
		"tab": Rect2i(15, 22, 267, 37),
		"tab_lit": Rect2i(282, 22, 267, 37),
		"strip": Rect2i(17, 59, 266, 29),
		# The bottom-left column box: no junction ticks on its sides.
		"box": Rect2i(16, 325, 267, 143),
		# The lobby's Create plate.
		"button": "MuCreateHost",
		"close": "OptionsOK",
		"back": "MuBack",
		"check": "AmbientSounds",
		"slider_texture": "OPTIONS_PANEL_12",
		"slider_track": Rect2i(107, 91, 145, 28),
		"slider_thumb": Rect2i(241, 123, 6, 24),
		"scroll_up": "MuChatU",
		"scroll_down": "MuChatD",
		# The first game has no drop-down lists or text field art: those get
		# plain slots (see theme()).
	},
	"el2": {
		# The Options screen, Combat page (its Type1 pieces): frame, tabs,
		# column boxes and the section header strips.
		"panel": "Options",
		"panel_exclude": ["Type2"],
		"frame_inside": Rect2i(16, 22, 532, 490),
		# Left, top, right, bottom: past the corner ornaments (50 px along
		# the top, 46 px up the sides), and leaving straight edges of 462 px,
		# a whole number of the braid's 33 px repeats.
		"frame_margins": [51, 22, 51, 50],
		"edge_period": 33,
		"stone": Rect2i(70, 98, 205, 360),
		"tab": Rect2i(16, 22, 266, 37),
		"tab_lit": Rect2i(282, 22, 268, 37),
		"strip": Rect2i(19, 61, 262, 28),
		"box": Rect2i(16, 87, 266, 380),
		# The online lobby's Create plate: a text button that stretches.
		"button": "MP_A6_CreateHost",
		"close": "OP_OK",
		"check": "OPG_AmbientSounds",
		"slider_texture": "OPTIONS_PANEL_12",
		"slider_track": Rect2i(107, 91, 144, 28),
		"slider_thumb": Rect2i(241, 123, 6, 24),
		# The preset editor's drop-down bars: down arrow lit, plain and dark,
		# then the up arrow (open); a plain bar for the open list's hovered row.
		"dropdown_texture": "A6-Int-Invent-10",
		"dropdown": [Rect2i(1, 0, 254, 18), Rect2i(1, 20, 254, 18), Rect2i(1, 40, 254, 18), Rect2i(1, 60, 254, 18)],
		"dropdown_row": Rect2i(73, 140, 177, 18),
		# In a cut bar: the arrow spans these columns, and the last
		# `dropdown_cap` columns are the bar's right end.
		"dropdown_arrow_start": 208,
		"dropdown_arrow_end": 229,
		"dropdown_cap": 6,
		"scroll_up": "MP_A6_ChatU",
		"scroll_down": "MP_A6_ChatD",
		# The online lobby's Back (a dialog's way out).
		"back": "MP_A6_Back",
		# Text fields: the drop-down texture's plain bar, lit while typing.
		# ("field_texture" names another sheet; the default is the drop-downs'.)
		"field": Rect2i(73, 140, 177, 18),
		"field_lit": Rect2i(73, 120, 177, 18),
	},
}

## The stone behind panels: copies of the swatch, enlarged by this much and
## flipped at random, laid into one field of this size so that each overlaps
## its neighbours by STONE_FEATHER pixels and fades into them. Large panels
## then show no seam and no regular repeat.
const STONE_SCALE := 1.6
const STONE_FIELD := Vector2i(1600, 1200)
const STONE_FEATHER := 48

var profile: ELProfile
var art: Dictionary = {}
var _paths := {}
var _rows := {}
var _controls := {}
var _images := {}
var _theme: Theme
var _section_styles := {}

## `art` replaces the game's ART entry (for trying out new measurements).
static func for_profile(source: ELProfile, art_override := {}) -> ELMenuKit:
	if source == null: return null
	var kit := ELMenuKit.new()
	kit.profile = source
	kit.art = art_override if not art_override.is_empty() else ART.get(source.id, {})
	for row: Dictionary in source.table("InterfaceTextures").values():
		kit._paths[str(row.get("Name", ""))] = "Interface/" + str(row.get("Path", "")).replace("\\", "/")
	for row: Dictionary in source.table("Controls").values():
		kit._controls[str(row.get("Name", ""))] = row
	for row: Dictionary in source.table("CutParts").values():
		var control := str(row.get("Ctrl", ""))
		var entry := row.duplicate()
		entry.masks = masks_of(row)
		if not kit._rows.has(control): kit._rows[control] = []
		kit._rows[control].append(entry)
	return kit

static func masks_of(row: Dictionary) -> Array:
	var raw: Variant = row.get("Msk", [])
	if raw is Array: return raw
	return [] if str(raw).is_empty() else [str(raw)]

# --- Registry ---------------------------------------------------------------

func rows(control: String, required: Array = [], excluded: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows.get(control, []):
		if required.all(func(mask: String) -> bool: return row.masks.has(mask)) and not excluded.any(func(mask: String) -> bool: return row.masks.has(mask)):
			result.append(row)
	return result

func has_control(control: String) -> bool:
	return _rows.has(control)

## A control's rectangle in its panel (Controls Left, Top, Width, Height).
func control_rect(control: String) -> Rect2:
	var row: Dictionary = _controls.get(control, {})
	return Rect2(float(row.get("Left", 0)), float(row.get("Top", 0)), float(row.get("Width", 0)), float(row.get("Height", 0)))

## Where a panel sits on the 1024x768 screen (Controls ShiftX, ShiftY).
func control_shift(control: String) -> Vector2:
	var row: Dictionary = _controls.get(control, {})
	return Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))

## A control's Controls row ({} when the game has no such control).
func control_row(control: String) -> Dictionary:
	return _controls.get(control, {})

## A texture of the interface as an RGBA8 image (null when missing).
func image(texture_name: String) -> Image:
	if _images.has(texture_name): return _images[texture_name]
	var picture: Image = null
	var texture := profile.texture(str(_paths.get(texture_name, ""))) if _paths.has(texture_name) else null
	if texture != null:
		picture = texture.get_image()
		if picture != null:
			picture = picture.duplicate()
			if picture.is_compressed(): picture.decompress()
			picture.convert(Image.FORMAT_RGBA8)
	_images[texture_name] = picture
	return picture

func cut(texture_name: String, region: Rect2i) -> Image:
	var sheet := image(texture_name)
	return sheet.get_region(region) if sheet != null else null

static func _source(row: Dictionary) -> Rect2i:
	return Rect2i(int(row.TxtL), int(row.TxtT), int(row.TxtW), int(row.TxtH))

static func _at(row: Dictionary) -> Vector2i:
	return Vector2i(int(row.ScrL), int(row.ScrT))

static func _layer(row: Dictionary) -> int:
	for index in [3, 2, 1]:
		if row.masks.has("Last%d" % index): return index
	return 2 if row.masks.has("Last") else 0

## A control's own pieces drawn together, in the order the original layers
## them. Returns {"image", "origin"} (origin: the top-left piece's screen
## position), or {} when nothing is there.
func compose(control: String, excluded: Array = []) -> Dictionary:
	var list := rows(control, [], ["Res1", "Res3"] + excluded)
	if list.is_empty(): return {}
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _layer(a) < _layer(b))
	var bounds := Rect2i()
	var started := false
	for row: Dictionary in list:
		var rect := Rect2i(_at(row), _source(row).size)
		bounds = rect if not started else bounds.merge(rect)
		started = true
	var picture := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	var drawn := 0
	for row: Dictionary in list:
		var sheet := image(str(row.get("Txt", "")))
		if sheet == null: continue
		picture.blend_rect(sheet, _source(row), _at(row) - bounds.position)
		drawn += 1
	return {"image": picture, "origin": bounds.position} if drawn > 0 else {}

## A button's looks from its pieces: "normal" (Free), "hover" (Free with the
## Light pieces over it), "pressed" (Push) and "disabled" (Disabled, else the
## normal look dimmed). All share one size, so the pieces keep their places.
func plates(control: String) -> Dictionary:
	var all := rows(control, [], ["Res1", "Res3"])
	if all.is_empty(): return {}
	var bounds := Rect2i()
	for i in all.size():
		var rect := Rect2i(_at(all[i]), _source(all[i]).size)
		bounds = rect if i == 0 else bounds.merge(rect)
	var paint := func(pieces: Array) -> Image:
		var picture := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		for row: Dictionary in pieces:
			var sheet := image(str(row.get("Txt", "")))
			if sheet != null: picture.blend_rect(sheet, _source(row), _at(row) - bounds.position)
		return picture
	var normal := rows(control, ["Free"], ["Light", "Disabled"])
	if normal.is_empty(): normal = all.filter(func(row: Dictionary) -> bool: return row.masks.is_empty())
	if normal.is_empty(): return {}
	var glow := rows(control, ["Light"], ["Push"])
	var pressed := rows(control, ["Push"], ["Light", "Disabled"])
	var disabled := rows(control, ["Disabled"])
	var result := {"normal": paint.call(normal), "hover": paint.call(normal + glow),
		"pressed": paint.call(pressed if not pressed.is_empty() else normal)}
	if not disabled.is_empty(): result.disabled = paint.call(disabled)
	else: result.disabled = _dim(result.normal, 0.55)
	return result

static func _dim(picture: Image, amount: float, alpha := 1.0) -> Image:
	var result := picture.duplicate() as Image
	for y in result.get_height():
		for x in result.get_width():
			var colour := result.get_pixel(x, y)
			result.set_pixel(x, y, Color(colour.r * amount, colour.g * amount, colour.b * amount, colour.a * alpha))
	return result

static func _brighten(picture: Image, amount: float) -> Image:
	var result := picture.duplicate() as Image
	for y in result.get_height():
		for x in result.get_width():
			var colour := result.get_pixel(x, y)
			result.set_pixel(x, y, Color(minf(1.0, colour.r * amount), minf(1.0, colour.g * amount), minf(1.0, colour.b * amount), colour.a))
	return result

## `picture` with `inside` made transparent (a border to draw over a fill).
static func _hollow(picture: Image, inside: Rect2i) -> Image:
	var result := picture.duplicate() as Image
	result.fill_rect(inside, Color(0, 0, 0, 0))
	return result

## Rebuilds the four straight edges of a frame from one `period` of their
## pattern each, so the tiled copies of a nine-patch meet without a mark. The
## edges' lengths (the frame less its corner margins) should be whole
## multiples of `period`.
static func _even_edges(picture: Image, inside: Rect2i, margins: Array, period: int) -> void:
	var size := picture.get_size()
	var middle := Vector2i(size.x - margins[0] - margins[2], size.y - margins[1] - margins[3])
	_repeat(picture, Rect2i(0, margins[1], inside.position.x, middle.y), period, true)
	_repeat(picture, Rect2i(inside.end.x, margins[1], size.x - inside.end.x, middle.y), period, true)
	_repeat(picture, Rect2i(margins[0], 0, middle.x, inside.position.y), period, false)
	_repeat(picture, Rect2i(margins[0], inside.end.y, middle.x, size.y - inside.end.y), period, false)

## Fills `band` with copies of the `period` of it whose end best meets its
## start (along y when `vertical`, else along x).
static func _repeat(picture: Image, band: Rect2i, period: int, vertical: bool) -> void:
	var length := band.size.y if vertical else band.size.x
	var across := band.size.x if vertical else band.size.y
	if length <= period or across <= 0: return
	var at := func(along: int, side: int) -> Vector2i:
		return band.position + (Vector2i(side, along) if vertical else Vector2i(along, side))
	var best := 0
	var best_score := INF
	for start in length - period:
		var score := 0.0
		for side in across:
			var a := picture.get_pixelv(at.call(start, side))
			var b := picture.get_pixelv(at.call(start + period, side))
			score += (a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2
		if score < best_score:
			best_score = score
			best = start
	var piece_rect := Rect2i(at.call(best, 0), Vector2i(across, period) if vertical else Vector2i(period, across))
	var piece := picture.get_region(piece_rect)
	var done := 0
	while done < length:
		var step := mini(period, length - done)
		var source := Rect2i(Vector2i.ZERO, Vector2i(across, step) if vertical else Vector2i(step, across))
		picture.blit_rect(piece, source, at.call(done, 0))
		done += step

## One large stone field from a small swatch: enlarged copies, each flipped at
## random (a fixed seed, so the field is the same every time), overlap their
## left and upper neighbours and fade in over the overlap.
static func _stone_field(swatch: Image, field: Vector2i) -> Image:
	var tile := swatch.duplicate() as Image
	tile.resize(roundi(tile.get_width() * STONE_SCALE), roundi(tile.get_height() * STONE_SCALE), Image.INTERPOLATE_CUBIC)
	var size := tile.get_size()
	var variants: Array[Image] = []
	for k in 4:
		var copy := tile.duplicate() as Image
		if k & 1: copy.flip_x()
		if k & 2: copy.flip_y()
		_feather(copy, STONE_FEATHER)
		variants.append(copy)
	var step := size - Vector2i.ONE * STONE_FEATHER
	var random := RandomNumberGenerator.new()
	random.seed = 1999
	var result := Image.create_empty(field.x, field.y, false, Image.FORMAT_RGBA8)
	# Starting one overlap outside the field keeps the faded edges off it.
	for row in ceili(float(field.y + STONE_FEATHER) / step.y):
		for column in ceili(float(field.x + STONE_FEATHER) / step.x):
			var at := Vector2i(column * step.x, row * step.y) - Vector2i.ONE * STONE_FEATHER
			result.blend_rect(variants[random.randi() % 4], Rect2i(Vector2i.ZERO, size), at)
	return result

## Fades `picture`'s left and upper `width` pixels in from transparent.
static func _feather(picture: Image, width: int) -> void:
	for y in picture.get_height():
		for x in picture.get_width():
			if x >= width and y >= width: break
			var colour := picture.get_pixel(x, y)
			colour.a *= smoothstep(0.0, 1.0, minf(float(x) / width, 1.0)) * smoothstep(0.0, 1.0, minf(float(y) / width, 1.0))
			picture.set_pixel(x, y, colour)

## `picture` without the columns between `keep` and its last `cap` columns.
static func _close_up(picture: Image, keep: int, cap: int) -> Image:
	var height := picture.get_height()
	var result := Image.create_empty(keep + cap, height, false, Image.FORMAT_RGBA8)
	result.blit_rect(picture, Rect2i(0, 0, keep, height), Vector2i.ZERO)
	result.blit_rect(picture, Rect2i(picture.get_width() - cap, 0, cap, height), Vector2i(keep, 0))
	return result

static func _texture(picture: Image) -> ImageTexture:
	return ImageTexture.create_from_image(picture) if picture != null else null

## A nine-patch box: `margins` are left, top, right, bottom texture margins;
## the middle and edges repeat (`tile`) or stretch.
static func _nine(picture: Image, margins: Array, content := Vector4(8, 6, 8, 6), tile := true) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _texture(picture)
	style.texture_margin_left = margins[0]
	style.texture_margin_top = margins[1]
	style.texture_margin_right = margins[2]
	style.texture_margin_bottom = margins[3]
	if tile:
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.content_margin_left = content.x
	style.content_margin_top = content.y
	style.content_margin_right = content.z
	style.content_margin_bottom = content.w
	return style

## A panel: one stone field cut to the panel's size (never repeated or
## stretched while the panel fits in it), with a nine-patch border over it.
## Exported, so a duplicate (a screen's own padding) keeps the art.
class FrameBox extends StyleBox:
	@export var fill: Texture2D
	@export var fill_tint := Color.WHITE
	## Left, top, right, bottom: where the stone starts inside the border.
	@export var fill_inset := [0, 0, 0, 0]
	@export var border: Texture2D
	@export var margins := [0, 0, 0, 0]

	func _draw(item: RID, rect: Rect2) -> void:
		var inside := rect.grow_individual(-fill_inset[0], -fill_inset[1], -fill_inset[2], -fill_inset[3])
		if fill != null and inside.has_area():
			var source := Rect2(Vector2.ZERO, inside.size.min(Vector2(fill.get_size())))
			RenderingServer.canvas_item_add_texture_rect_region(item, inside, fill.get_rid(), source, fill_tint)
		if border != null:
			RenderingServer.canvas_item_add_nine_patch(item, rect, Rect2(Vector2.ZERO, border.get_size()), border.get_rid(),
				Vector2(margins[0], margins[1]), Vector2(margins[2], margins[3]),
				RenderingServer.NINE_PATCH_TILE_FIT, RenderingServer.NINE_PATCH_TILE_FIT, false)

static func _frame_box(border: Image, margins: Array, inset: Array, fill: Texture2D, tint: Color, content: Vector4) -> FrameBox:
	var style := FrameBox.new()
	style.border = _texture(border)
	style.margins = margins
	style.fill_inset = inset
	style.fill = fill
	style.fill_tint = tint
	style.content_margin_left = content.x
	style.content_margin_top = content.y
	style.content_margin_right = content.z
	style.content_margin_bottom = content.w
	return style

# --- Theme ------------------------------------------------------------------

## The look for stock controls, or null when this game lacks the pieces.
func theme() -> Theme:
	if _theme != null: return _theme
	if art.is_empty() or not has_control(art.panel): return null
	var panel := compose(art.panel, art.get("panel_exclude", []))
	if panel.is_empty(): return null
	var sheet: Image = panel.image
	var stone := _texture(_stone_field(sheet.get_region(art.stone), STONE_FIELD))
	var look := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	font.font_weight = 700
	look.default_font = font
	look.default_font_size = 15

	# Dialog: the Options frame over darker stone.
	var inside: Rect2i = art.frame_inside
	var frame := _hollow(sheet, inside)
	if art.has("edge_period"): _even_edges(frame, inside, art.frame_margins, art.edge_period)
	var inset := [inside.position.x, inside.position.y, sheet.get_width() - inside.end.x, sheet.get_height() - inside.end.y]
	var window := _frame_box(frame, art.frame_margins, inset, stone, Color(0.62, 0.62, 0.62), Vector4(26, 28, 26, 30))
	look.set_stylebox("panel", "AcceptDialog", window)
	look.set_stylebox("panel", "PopupPanel", window)
	look.set_constant("buttons_separation", "AcceptDialog", 12)

	# Text.
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "PopupMenu", "LineEdit", "TabContainer", "ItemList"]:
		look.set_color("font_color", type, BODY_INK)

	# Push buttons on the lobby plate.
	var plate := plates(art.get("button", ""))
	if not plate.is_empty():
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			look.set_stylebox(state, "Button", _nine(plate[state], [12, 9, 12, 9], Vector4(16, 7, 16, 8), false))
		look.set_stylebox("hover_pressed", "Button", look.get_stylebox("pressed", "Button"))
		look.set_color("font_color", "Button", TITLE_INK)
		look.set_color("font_hover_color", "Button", HOVER_INK)
		look.set_color("font_pressed_color", "Button", HOVER_INK)
		look.set_color("font_hover_pressed_color", "Button", HOVER_INK)
		look.set_color("font_focus_color", "Button", TITLE_INK)
		look.set_color("font_disabled_color", "Button", DISABLED_INK)
	var none := StyleBoxEmpty.new()
	for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox", "HSlider", "TabContainer"]:
		look.set_stylebox("focus", type, none)

	# Drop-down lists: the bar without its painted arrow, and the arrow as the
	# button's own icon, so a taller bar never stretches it. (The original
	# leaves room after the arrow for a separate drop button; that stretch is
	# cut out too, so the arrow sits by the bar's right end.)
	var bars: Array = []
	for region: Rect2i in art.get("dropdown", []):
		var bar := cut(art.dropdown_texture, region)
		bars.append(_close_up(bar, art.dropdown_arrow_end, art.dropdown_cap) if bar != null else null)
	if not bars.is_empty() and not bars.has(null):
		var start: int = art.dropdown_arrow_start
		var span: int = art.dropdown_arrow_end - start
		var height: int = bars[1].get_height()
		var arrow: Image = bars[1].get_region(Rect2i(start, 2, span, height - 4))
		var bodies: Array = []
		for bar: Image in bars:
			var body := bar.duplicate() as Image
			# Plain bar from just left of the arrow over the arrow's columns.
			body.blit_rect(bar, Rect2i(start - span, 0, span, height), Vector2i(start, 0))
			bodies.append(body)
		var cap: int = art.dropdown_cap
		var margins := [8, 4, cap + 2, 4]
		var content := Vector4(10, 2, 4, 2)
		look.set_stylebox("normal", "OptionButton", _nine(bodies[1], margins, content, false))
		look.set_stylebox("hover", "OptionButton", _nine(bodies[0], margins, content, false))
		look.set_stylebox("pressed", "OptionButton", _nine(bodies[3], margins, content, false))
		look.set_stylebox("hover_pressed", "OptionButton", look.get_stylebox("pressed", "OptionButton"))
		look.set_stylebox("disabled", "OptionButton", _nine(bodies[2], margins, content, false))
		# The right-to-left looks count towards the button's width too.
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			look.set_stylebox(state + "_mirrored", "OptionButton", look.get_stylebox(state, "OptionButton"))
		look.set_icon("arrow", "OptionButton", _texture(arrow))
		look.set_constant("arrow_margin", "OptionButton", cap)
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			look.set_color(key, "OptionButton", BODY_INK)
		look.set_color("font_disabled_color", "OptionButton", DISABLED_INK)
	# Up and down arrows (scroll bars, spin boxes, plain drop-downs).
	var up := plates(art.get("scroll_up", ""))
	var down := plates(art.get("scroll_down", ""))
	if not look.has_stylebox("normal", "OptionButton"):
		# No drop-down art: a plain slot with the scroll bar's down arrow.
		var states := {"normal": _slot(Color("5c4c36")), "hover": _slot(Color("8a7350")), "pressed": _slot(Color("a88c5c")),
			"disabled": _slot(Color("3a3226"), Color("0a0a0a90"))}
		states.hover_pressed = states.pressed
		for state: String in states:
			var style: StyleBoxFlat = states[state]
			style.content_margin_left = 8
			look.set_stylebox(state, "OptionButton", style)
			look.set_stylebox(state + "_mirrored", "OptionButton", style)
		if not down.is_empty(): look.set_icon("arrow", "OptionButton", _texture(down.normal))
		look.set_constant("arrow_margin", "OptionButton", 6)
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			look.set_color(key, "OptionButton", BODY_INK)
		look.set_color("font_disabled_color", "OptionButton", DISABLED_INK)
	var list := StyleBoxFlat.new()
	list.bg_color = Color("101210f4")
	list.border_color = Color("6c5a40")
	list.set_border_width_all(1)
	list.set_content_margin_all(4)
	look.set_stylebox("panel", "PopupMenu", list)
	var row := cut(art.dropdown_texture, art.dropdown_row) if art.has("dropdown_row") else null
	if row != null: look.set_stylebox("hover", "PopupMenu", _nine(row, [6, 4, 6, 4], Vector4(6, 2, 6, 2), false))
	look.set_color("font_hover_color", "PopupMenu", HOVER_INK)
	look.set_color("font_disabled_color", "PopupMenu", DISABLED_INK)
	look.set_constant("v_separation", "PopupMenu", 6)

	# Check boxes: the Options box with its tick drawn over it.
	var check := plates(art.get("check", ""))
	if not check.is_empty():
		var empty_box: Image = check.normal
		var ticked := empty_box.duplicate() as Image
		ticked.blend_rect(check.pressed, Rect2i(Vector2i.ZERO, check.pressed.get_size()), Vector2i.ZERO)
		for type: String in ["CheckButton", "CheckBox"]:
			look.set_icon("unchecked", type, _texture(empty_box))
			look.set_icon("checked", type, _texture(ticked))
			look.set_icon("unchecked_disabled", type, _texture(_dim(empty_box, 0.6, 0.6)))
			look.set_icon("checked_disabled", type, _texture(_dim(ticked, 0.6, 0.6)))
			for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]: look.set_stylebox(state, type, none)
			look.set_color("font_hover_color", type, HOVER_INK)
			look.set_color("font_pressed_color", type, BODY_INK)

	# Sliders: the Options volume bar and its thumb.
	var track := cut(art.slider_texture, art.slider_track) if art.has("slider_track") else null
	var thumb := cut(art.slider_texture, art.slider_thumb) if art.has("slider_thumb") else null
	if track != null and thumb != null:
		var bar := _nine(track, [4, 4, 4, 4], Vector4(0, 0, 0, 0), false)
		bar.content_margin_top = track.get_height() * 0.5
		bar.content_margin_bottom = track.get_height() * 0.5
		look.set_stylebox("slider", "HSlider", bar)
		look.set_stylebox("grabber_area", "HSlider", none)
		look.set_stylebox("grabber_area_highlight", "HSlider", none)
		look.set_icon("grabber", "HSlider", _texture(thumb))
		look.set_icon("grabber_highlight", "HSlider", _texture(_brighten(thumb, 1.35)))
		look.set_icon("grabber_disabled", "HSlider", _texture(_dim(thumb, 0.6)))

	# Tabs: the Options page tabs, lit for the open page.
	var tab := sheet.get_region(art.tab)
	var tab_lit := sheet.get_region(art.tab_lit)
	var tab_content := Vector4(22, 8, 22, 8)
	look.set_stylebox("tab_selected", "TabContainer", _nine(tab_lit, [18, 6, 18, 4], tab_content, false))
	look.set_stylebox("tab_unselected", "TabContainer", _nine(tab, [18, 6, 18, 4], tab_content, false))
	look.set_stylebox("tab_hovered", "TabContainer", _nine(_brighten(tab, 1.5), [18, 6, 18, 4], tab_content, false))
	look.set_stylebox("tab_disabled", "TabContainer", _nine(_dim(tab, 0.7), [18, 6, 18, 4], tab_content, false))
	look.set_stylebox("tabbar_background", "TabContainer", none)
	look.set_color("font_selected_color", "TabContainer", HOVER_INK)
	look.set_color("font_unselected_color", "TabContainer", NOTE_INK)
	look.set_color("font_hovered_color", "TabContainer", TITLE_INK)
	look.set_constant("side_margin", "TabContainer", 0)
	look.set_font_size("font_size", "TabContainer", 16)
	# The page: a column box's border of the Options screen over clean stone.
	var box := sheet.get_region(art.box)
	look.set_stylebox("panel", "TabContainer", _frame_box(_hollow(box, Rect2i(Vector2i(4, 4), box.get_size() - Vector2i(8, 8))),
		[6, 6, 6, 6], [4, 4, 4, 4], stone, Color.WHITE, Vector4(4, 4, 4, 4)))

	# Text fields (and the field of a spin box): the plain bar.
	var field_sheet := str(art.get("field_texture", art.get("dropdown_texture", "")))
	var field := cut(field_sheet, art.field) if art.has("field") else null
	if field != null:
		var lit := cut(field_sheet, art.get("field_lit", art.field))
		var plain := _nine(field, [6, 4, 6, 4], Vector4(8, 3, 8, 3), false)
		look.set_stylebox("normal", "LineEdit", plain)
		look.set_stylebox("focus", "LineEdit", _nine(lit, [6, 4, 6, 4], Vector4(8, 3, 8, 3), false))
		look.set_stylebox("read_only", "LineEdit", _nine(_dim(field, 0.7), [6, 4, 6, 4], Vector4(8, 3, 8, 3), false))
	else:
		look.set_stylebox("normal", "LineEdit", _slot(Color("5c4c36")))
		look.set_stylebox("focus", "LineEdit", _slot(Color("a88c5c")))
		look.set_stylebox("read_only", "LineEdit", _slot(Color("3a3226"), Color("0a0a0a90")))
	look.set_color("font_color", "LineEdit", BODY_INK)
	look.set_color("font_placeholder_color", "LineEdit", NOTE_INK)
	look.set_color("caret_color", "LineEdit", HOVER_INK)
	look.set_color("selection_color", "LineEdit", Color(0.55, 0.42, 0.24, 0.6))

	# Lists: a black slot in a bronze line, the chosen row on the plain bar.
	var slot_list := StyleBoxFlat.new()
	slot_list.bg_color = Color("060606e8")
	slot_list.border_color = Color("5c4c36")
	slot_list.set_border_width_all(1)
	slot_list.set_content_margin_all(4)
	look.set_stylebox("panel", "ItemList", slot_list)
	look.set_stylebox("focus", "ItemList", none)
	if row == null:
		var picked := _slot(Color("8a7350"), Color("3a3020"))
		for state: String in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]: look.set_stylebox(state, "ItemList", picked)
		look.set_stylebox("hovered", "ItemList", _slot(Color("5c4c36"), Color("201c16")))
	else:
		var chosen := _nine(_brighten(row, 1.3), [6, 4, 6, 4], Vector4(6, 2, 6, 2), false)
		for state: String in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]: look.set_stylebox(state, "ItemList", chosen)
		look.set_stylebox("hovered", "ItemList", _nine(row, [6, 4, 6, 4], Vector4(6, 2, 6, 2), false))
	look.set_color("font_hovered_color", "ItemList", HOVER_INK)
	look.set_color("font_selected_color", "ItemList", HOVER_INK)
	look.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))

	# Scroll bars: the lobby chat's arrows over a black slot.
	var slot := StyleBoxFlat.new()
	slot.bg_color = Color("050505")
	slot.border_color = Color("3c3428")
	slot.set_border_width_all(1)
	slot.content_margin_left = 13
	look.set_stylebox("scroll", "VScrollBar", slot)
	look.set_stylebox("scroll_focus", "VScrollBar", slot)
	var grip := StyleBoxFlat.new()
	grip.bg_color = Color("4b3f2e")
	grip.border_color = Color("8a7350")
	grip.set_border_width_all(1)
	grip.content_margin_left = 11
	look.set_stylebox("grabber", "VScrollBar", grip)
	var grip_lit := grip.duplicate() as StyleBoxFlat
	grip_lit.bg_color = Color("66553c")
	look.set_stylebox("grabber_highlight", "VScrollBar", grip_lit)
	look.set_stylebox("grabber_pressed", "VScrollBar", grip_lit)
	if not up.is_empty() and not down.is_empty():
		look.set_icon("decrement", "VScrollBar", _texture(up.normal))
		look.set_icon("decrement_highlight", "VScrollBar", _texture(up.hover))
		look.set_icon("decrement_pressed", "VScrollBar", _texture(up.pressed))
		look.set_icon("increment", "VScrollBar", _texture(down.normal))
		look.set_icon("increment_highlight", "VScrollBar", _texture(down.hover))
		look.set_icon("increment_pressed", "VScrollBar", _texture(down.pressed))

	# Spin boxes: the same arrows, stacked at the field's right end.
	if not up.is_empty() and not down.is_empty():
		var blank := StyleBoxEmpty.new()
		for part: String in ["up", "down"]:
			var looks: Dictionary = up if part == "up" else down
			look.set_icon(part, "SpinBox", _texture(looks.normal))
			look.set_icon(part + "_hover", "SpinBox", _texture(looks.hover))
			look.set_icon(part + "_pressed", "SpinBox", _texture(looks.pressed))
			look.set_icon(part + "_disabled", "SpinBox", _texture(looks.disabled))
			for state: String in ["", "_hovered", "_pressed", "_disabled"]: look.set_stylebox(part + "_background" + state, "SpinBox", blank)
		look.set_stylebox("field_and_buttons_separator", "SpinBox", blank)
		look.set_constant("buttons_vertical_separation", "SpinBox", 0)
		look.set_constant("field_and_buttons_separation", "SpinBox", 2)
		look.set_constant("buttons_width", "SpinBox", up.normal.get_width())
		look.set_constant("set_min_buttons_width_from_icons", "SpinBox", 1)

	_section_styles = {"strip": _nine(sheet.get_region(art.strip), [6, 6, 6, 6], Vector4(10, 4, 10, 4))}
	_theme = look
	return _theme

## A plain field: a dark slot in a bronze line.
static func _slot(border: Color, fill := Color("0a0a0ae8")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

static func _blank() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))

# --- Building blocks --------------------------------------------------------

## A titled group: the Options header strip with the title, then a column for
## the group's rows. Returns the column.
func section(parent: Control, title: String, featured := false) -> VBoxContainer:
	if _theme == null: theme()
	var group := VBoxContainer.new()
	group.name = title.replace(" ", "")
	group.add_theme_constant_override("separation", 10)
	parent.add_child(group)
	var strip := PanelContainer.new()
	if _section_styles.has("strip"): strip.add_theme_stylebox_override("panel", _section_styles.strip)
	group.add_child(strip)
	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_color", HOVER_INK if featured else TITLE_INK)
	strip.add_child(caption)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var inset := MarginContainer.new()
	for side: String in ["left", "right"]: inset.add_theme_constant_override("margin_" + side, 8)
	inset.add_child(column)
	group.add_child(inset)
	return column

## Sizes the drop-down lists under `root` to their longest item in the kit's
## look. OptionButton's own fitting leaves a gap between the text and the
## bar's painted arrow, so the width is measured here and fixed instead.
static func refit(root: Node) -> void:
	for node: Node in root.find_children("*", "OptionButton", true, false):
		var list := node as OptionButton
		if not list.fit_to_longest_item or list.item_count == 0: continue
		var font := list.get_theme_font("font")
		var font_size := list.get_theme_font_size("font_size")
		var widest := 0.0
		for i in list.item_count:
			widest = maxf(widest, font.get_string_size(list.get_item_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var frame := list.get_theme_stylebox("normal").get_minimum_size().x
		var arrow := list.get_theme_icon("arrow").get_width() + list.get_theme_constant("h_separation")
		list.fit_to_longest_item = false
		list.custom_minimum_size.x = ceilf(widest + frame + arrow)

## The dialog frame (`kind` "frame") or a column box ("box") as a panel
## style with its own padding: left, top, right, bottom. Null without the art.
func panel_style(kind: String, padding: Vector4) -> StyleBox:
	var look := theme()
	if look == null: return null
	var source := look.get_stylebox("panel", "AcceptDialog" if kind == "frame" else "TabContainer")
	var style := source.duplicate() as StyleBox
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style

## A heading in the panel's title ink.
static func heading(text: String, size := 20) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TITLE_INK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

## Dresses `button` as an original square icon button (OK, Cancel, Back):
## no caption; its tooltip says what it does.
func icon_button(button: Button, control: String, tooltip := "") -> bool:
	var looks := plates(control)
	if looks.is_empty(): return false
	button.text = ""
	if not tooltip.is_empty(): button.tooltip_text = tooltip
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = _texture(looks[state])
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.custom_minimum_size = Vector2(looks.normal.get_size())
	ELUiSounds.bind(button, profile, control)
	return true

## Dresses a remake dialog in the kit: borderless, the kit's theme, and its
## OK button as the original Back (or `control`). Returns false, changing
## nothing, when this game lacks the pieces.
func dress_dialog(dialog: AcceptDialog, tooltip := "", control := "") -> bool:
	var look := theme()
	if look == null: return false
	dialog.exclusive = true
	dialog.borderless = true
	dialog.theme = look
	dialog.set_meta("menu_kit", self)
	var back: String = control if not control.is_empty() else str(art.get("back", art.get("close", "")))
	if not back.is_empty(): dialog_button(dialog, back, tooltip)
	return true

## The kit a dialog was dressed in (see dress_dialog), from any node in it;
## null for a dialog in the remake's own look.
static func of(node: Node) -> ELMenuKit:
	while node != null:
		if node.has_meta("menu_kit"): return node.get_meta("menu_kit")
		node = node.get_parent()
	return null

## The dialog's OK button as an original icon button. AcceptDialog sizes its
## buttons from its own theme constants (overriding custom_minimum_size), so
## those are set to the art's size.
func dialog_button(dialog: AcceptDialog, control: String, tooltip := "") -> bool:
	var button := dialog.get_ok_button()
	if not icon_button(button, control, tooltip): return false
	dialog.add_theme_constant_override("buttons_min_width", int(button.custom_minimum_size.x))
	dialog.add_theme_constant_override("buttons_min_height", int(button.custom_minimum_size.y))
	return true
