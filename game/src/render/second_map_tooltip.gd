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
var subject := -1
var _frame: Texture2D
var _picture: TextureRect
var _labels: Array[Label] = []
var _content := Vector2.ZERO

func setup(source: ELProfile, serif: Font) -> void:
	profile = source
	font = serif
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = profile.texture(ELSecondMapTooltips.PANEL_TEXTURE)
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
	_picture.visible = not picture.is_empty()
	var labels: Array = content.get("labels", [])
	for entry: Dictionary in labels:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = str(entry.text)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", INK)
		label.add_theme_constant_override("line_spacing", LINE_SPACING)
		add_child(label)
		label.size = label.get_minimum_size()
		if label.size.x > MAX_LABEL_WIDTH:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = MAX_LABEL_WIDTH
			label.size = Vector2(MAX_LABEL_WIDTH, 0)
			label.size = Vector2(MAX_LABEL_WIDTH, label.get_minimum_size().y)
		label.position = Vector2(entry.at) + Vector2.ONE * ELSecondMapTooltips.FRAME
		_labels.append(label)
		if label.text.is_empty(): continue
		var rect := Rect2(entry.at, label.size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if not picture.is_empty():
		var texture: Texture2D = building_icon(int(picture.index)) if picture.kind == "building" else profile.portrait(int(picture.index))
		_picture.texture = texture
		var at: Vector2 = picture.at
		if picture.get("centre", false): at.x = maxf(0.0, (bounds.size.x - picture.size.x) * 0.5) if not first else 0.0
		var rect := Rect2(at, picture.size)
		_picture.position = rect.position + Vector2.ONE * ELSecondMapTooltips.FRAME
		_picture.size = rect.size
		bounds = rect if first else bounds.merge(rect)
		first = false
	# Content starts at its own top-left; the frame is ten units outside it.
	var origin := bounds.position
	for label in _labels: label.position -= origin
	_picture.position -= origin
	_content = bounds.size
	size = _content + Vector2.ONE * ELSecondMapTooltips.FRAME * 2.0
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

## Nine-slice: 5-unit borders and corners, the 50-unit centre tiled.
func _draw() -> void:
	if _frame == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(33, 33, 33))
		return
	var source := ELSecondMapTooltips.PANEL_SOURCE
	var border := ELSecondMapTooltips.PANEL_BORDER
	var inner := Rect2(Vector2(border, border), size - Vector2(border, border) * 2.0)
	var middle := Rect2(source.position + Vector2(border, border), source.size - Vector2(border, border) * 2.0)
	if inner.size.x <= 0 or inner.size.y <= 0: return
	# Centre, tiled.
	var y := inner.position.y
	while y < inner.end.y:
		var h := minf(middle.size.y, inner.end.y - y)
		var x := inner.position.x
		while x < inner.end.x:
			var w := minf(middle.size.x, inner.end.x - x)
			draw_texture_rect_region(_frame, Rect2(x, y, w, h), Rect2(middle.position, Vector2(w, h)))
			x += w
		y += h
	# Edges, tiled along their length.
	var edges := [
		[Rect2(inner.position.x, 0, inner.size.x, border), Rect2(middle.position.x, source.position.y, middle.size.x, border), true],
		[Rect2(inner.position.x, inner.end.y, inner.size.x, border), Rect2(middle.position.x, middle.end.y, middle.size.x, border), true],
		[Rect2(0, inner.position.y, border, inner.size.y), Rect2(source.position.x, middle.position.y, border, middle.size.y), false],
		[Rect2(inner.end.x, inner.position.y, border, inner.size.y), Rect2(middle.end.x, middle.position.y, border, middle.size.y), false]]
	for edge: Array in edges:
		var target: Rect2 = edge[0]
		var piece: Rect2 = edge[1]
		var along: bool = edge[2]
		var at := 0.0
		var length := target.size.x if along else target.size.y
		var step := piece.size.x if along else piece.size.y
		while at < length:
			var part := minf(step, length - at)
			if along: draw_texture_rect_region(_frame, Rect2(target.position.x + at, target.position.y, part, target.size.y), Rect2(piece.position, Vector2(part, piece.size.y)))
			else: draw_texture_rect_region(_frame, Rect2(target.position.x, target.position.y + at, target.size.x, part), Rect2(piece.position, Vector2(piece.size.x, part)))
			at += part
	# Corners.
	var corner := Vector2(border, border)
	draw_texture_rect_region(_frame, Rect2(Vector2.ZERO, corner), Rect2(source.position, corner))
	draw_texture_rect_region(_frame, Rect2(Vector2(inner.end.x, 0), corner), Rect2(Vector2(middle.end.x, source.position.y), corner))
	draw_texture_rect_region(_frame, Rect2(Vector2(0, inner.end.y), corner), Rect2(Vector2(source.position.x, middle.end.y), corner))
	draw_texture_rect_region(_frame, Rect2(inner.end, corner), Rect2(middle.end, corner))
