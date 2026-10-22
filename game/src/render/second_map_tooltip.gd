class_name ELSecondMapTooltip
extends Control
## The second game's map tooltip panel: the original nine-slice frame from
## Interface/black/ToolTip around a picture and text labels laid out by
## ELSecondMapTooltips.describe(). Lives on the HUD canvas, so its units are
## the HUD's 768-pixel-high design units; it never takes the mouse.

const INK := Color("e6dcc0")
const FONT_SIZE := 14
const LINE_SPACING := 0
## Longer lines (some specialization descriptions) wrap at this width so the
## panel stays readable in the window.
const MAX_LABEL_WIDTH := 480.0

var profile: ELProfile
var font: Font
## Space between the frame's outer edge and the content (units, across and down).
var margin := Vector2.ONE * ELSecondMapTooltips.FRAME
var ink := INK
var font_size := FONT_SIZE
var subject := -1
var _frame: Texture2D
var _picture: TextureRect
## The picture's black backdrop, one unit larger on every side.
var _backdrop: ColorRect
var _labels: Array[Label] = []
var _content := Vector2.ZERO

func setup(source: ELProfile, serif: Font) -> void:
	profile = source
	font = serif
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = profile.texture(ELSecondMapTooltips.PANEL_TEXTURE)
	_backdrop = ColorRect.new()
	_backdrop.color = Color.BLACK
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_picture)
	hide()

## Builds the panel for one object's description.
func set_content(id: int, content: Dictionary) -> void:
	subject = id
	for label in _labels: label.queue_free()
	_labels.clear()
	var bounds := Rect2()
	var first := true
	var picture: Dictionary = content.get("picture", {})
	var inset: Vector2 = content.get("margin", margin)
	_picture.visible = not picture.is_empty()
	_backdrop.visible = picture.get("framed", false)
	var labels: Array = content.get("labels", [])
	for entry: Dictionary in labels:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = str(entry.text)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", ink)
		label.add_theme_constant_override("line_spacing", LINE_SPACING)
		add_child(label)
		label.size = label.get_minimum_size()
		if label.size.x > MAX_LABEL_WIDTH:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = MAX_LABEL_WIDTH
			label.size = Vector2(MAX_LABEL_WIDTH, 0)
			label.size = Vector2(MAX_LABEL_WIDTH, label.get_minimum_size().y)
		label.position = Vector2(entry.at) + inset
		_labels.append(label)
		if label.text.is_empty(): continue
		var rect := Rect2(entry.at, label.size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if not picture.is_empty():
		var texture: Texture2D = picture.get("texture") if picture.has("texture") else (building_icon(int(picture.index)) if picture.kind == "building" else profile.portrait(int(picture.index)))
		_picture.texture = texture
		var at: Vector2 = picture.at
		if picture.get("centre", false): at.x = maxf(0.0, (bounds.size.x - picture.size.x) * 0.5) if not first else 0.0
		var rect := Rect2(at, picture.size)
		_picture.position = rect.position + inset
		_picture.size = rect.size
		bounds = rect if first else bounds.merge(rect)
		first = false
	# Content starts at its own top-left; the frame is ten units outside it.
	var origin := bounds.position
	for label in _labels: label.position -= origin
	_picture.position -= origin
	_backdrop.position = _picture.position - Vector2.ONE
	_backdrop.size = _picture.size + Vector2.ONE * 2.0
	_content = bounds.size
	size = _content + inset * 2.0
	queue_redraw()

## Places the frame for a cursor given in the same units; `screen` is the
## visible canvas size.
func place(cursor: Vector2, screen: Vector2) -> void:
	position = ELSecondMapTooltips.place(_content, cursor, screen)

func content_size() -> Vector2:
	return _content

func building_icon(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = profile.texture("Interface/Buildings/Icon_%d" % (index / 15 + 1))
	atlas.region = Rect2((index % 15 % 3) * 70, (index % 15 / 3) * 50, 70, 50)
	atlas.filter_clip = true
	return atlas

## The frame's pieces in the panel texture: corners, edges tiled along their
## length and the centre tiled from the inner corner. By default the nine
## slices of one square; the first game assembles its frame from strips.
var pieces := square_pieces(ELSecondMapTooltips.PANEL_SOURCE, ELSecondMapTooltips.PANEL_BORDER)

static func square_pieces(source: Rect2, border: float) -> Dictionary:
	var middle := Rect2(source.position + Vector2(border, border), source.size - Vector2(border, border) * 2.0)
	var corner := Vector2(border, border)
	return {"border": border, "fill": middle,
		"top": Rect2(middle.position.x, source.position.y, middle.size.x, border),
		"bottom": Rect2(middle.position.x, middle.end.y, middle.size.x, border),
		"left": Rect2(source.position.x, middle.position.y, border, middle.size.y),
		"right": Rect2(middle.end.x, middle.position.y, border, middle.size.y),
		"top_left": Rect2(source.position, corner), "top_right": Rect2(Vector2(middle.end.x, source.position.y), corner),
		"bottom_left": Rect2(Vector2(source.position.x, middle.end.y), corner), "bottom_right": Rect2(middle.end, corner)}

## Nine-slice: corners, edges tiled along their length, the centre tiled.
func _draw() -> void:
	if _frame == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(33, 33, 33))
		return
	var border: float = pieces.border
	var inner := Rect2(Vector2(border, border), size - Vector2(border, border) * 2.0)
	if inner.size.x <= 0 or inner.size.y <= 0: return
	_tile(inner, pieces.fill)
	_tile(Rect2(inner.position.x, 0, inner.size.x, border), pieces.top)
	_tile(Rect2(inner.position.x, inner.end.y, inner.size.x, border), pieces.bottom)
	_tile(Rect2(0, inner.position.y, border, inner.size.y), pieces.left)
	_tile(Rect2(inner.end.x, inner.position.y, border, inner.size.y), pieces.right)
	var corner := Vector2(border, border)
	draw_texture_rect_region(_frame, Rect2(Vector2.ZERO, corner), pieces.top_left)
	draw_texture_rect_region(_frame, Rect2(Vector2(inner.end.x, 0), corner), pieces.top_right)
	draw_texture_rect_region(_frame, Rect2(Vector2(0, inner.end.y), corner), pieces.bottom_left)
	draw_texture_rect_region(_frame, Rect2(inner.end, corner), pieces.bottom_right)

## Repeats a piece of the texture over `target` from its top-left corner.
func _tile(target: Rect2, piece: Rect2) -> void:
	var y := target.position.y
	while y < target.end.y:
		var h := minf(piece.size.y, target.end.y - y)
		var x := target.position.x
		while x < target.end.x:
			var w := minf(piece.size.x, target.end.x - x)
			draw_texture_rect_region(_frame, Rect2(x, y, w, h), Rect2(piece.position, Vector2(w, h)))
			x += w
		y += h
