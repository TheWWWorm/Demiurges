class_name ELExpeditionOfferTile
extends Button
## A whole offer as one button: its title and lines inside a bronze-lined
## slot (the look of ELExpeditionCardCell), so a click anywhere on it takes
## the choice. The tile grows to fit its lines at the width it is given.

const PAD := Vector2(10, 7)

var content: VBoxContainer

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 3)
	add_child(content)
	add_theme_stylebox_override("normal", _style(Color("5c4c36"), Color("0b0a08e0")))
	add_theme_stylebox_override("hover", _style(Color("d6bb88"), Color("1c1710ea")))
	add_theme_stylebox_override("pressed", _style(Color("fff4d6"), Color("241c12ee")))
	add_theme_stylebox_override("hover_pressed", get_theme_stylebox("pressed"))
	add_theme_stylebox_override("disabled", _style(Color("3a3226"), Color("0a0a0a90")))
	add_theme_stylebox_override("focus", _style(Color("fff4d6"), Color.TRANSPARENT))
	content.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	resized.connect(_fit)

static func _style(line: Color, fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	return style

## Adds a line of text (wrapping) and returns it.
func line(value: String, points: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", ink if not disabled else ink.darkened(0.35))
	content.add_child(label)
	return label

func _fit() -> void:
	content.position = PAD
	content.size = Vector2(maxf(0.0, size.x - PAD.x * 2.0), 0.0)
	var height := content.get_combined_minimum_size().y + PAD.y * 2.0
	if absf(custom_minimum_size.y - height) > 0.5: custom_minimum_size.y = height
	content.size.y = height - PAD.y * 2.0
