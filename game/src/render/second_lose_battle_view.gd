class_name ELSecondLoseBattleView
extends Control
## Second-game LoseBattle screen (CLoseBattle). After a played adventure battle
## that no player-one hero won, the full-screen GOOD_DEFEAT picture (the
## 1024x768 Res2 tiles) fades in with "Нажмите любую клавишу" (LoseBattle_Text1);
## once it is up, any key or click fades it out over one second and the map
## resumes. Wider windows centre the picture on black.

signal closed

const PANEL := "LoseBattle"
const FADE_IN := 1.0
const FADE_OUT := 1.0

var hud: ELSecondAdventureHud
var canvas: Control
var art: Control
var hint: Label
## 0 fading in, 1 waiting for a key, 2 fading out.
var stage := 0
var _pieces: Array[Dictionary] = []
var _clock := 0.0

func build(owner: ELSecondAdventureHud) -> void:
	hud = owner
	name = "LoseBattle"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_art)
	canvas.add_child(art)
	var row: Dictionary = hud._controls.get("LoseBattle_Text1", {})
	hint = Label.new()
	hint.name = "LoseBattle_Text1"
	hint.text = hud.text(str(row.get("Text", "")))
	hint.add_theme_font_override("font", hud.face_bold)
	hint.add_theme_font_size_override("font_size", int(row.get("FontSize", 18)))
	hint.add_theme_color_override("font_color", Color("d6bb88"))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hint)
	for piece_row: Dictionary in hud.rows(PANEL, ["Res2"]):
		var piece := hud.cut(piece_row)
		if not piece.is_empty(): _pieces.append(piece)
	resized.connect(_layout)
	modulate.a = 0.0
	_layout()

func _layout() -> void:
	if size.y <= 0: return
	var factor := minf(size.y / 768.0, size.x / 1024.0)
	canvas.scale = Vector2(factor, factor)
	canvas.position = (size - Vector2(1024, 768) * factor) * 0.5
	canvas.size = Vector2(1024, 768)
	art.size = canvas.size
	var row: Dictionary = hud._controls.get("LoseBattle_Text1", {})
	hint.position = Vector2(float(row.get("Left", 43)) + float(row.get("ShiftX", 0)), float(row.get("Top", 540)) + float(row.get("ShiftY", 168)))
	hint.size = Vector2(maxf(float(row.get("Width", 238)), hint.get_minimum_size().x), float(row.get("Height", 20)))
	art.queue_redraw()

func _draw_art() -> void:
	for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)

func _process(delta: float) -> void:
	_clock += delta
	match stage:
		0:
			modulate.a = clampf(_clock / FADE_IN, 0.0, 1.0)
			if _clock >= FADE_IN:
				stage = 1
				_clock = 0.0
		2:
			modulate.a = clampf(1.0 - _clock / FADE_OUT, 0.0, 1.0)
			if _clock >= FADE_OUT:
				closed.emit()
				queue_free()

## Any key or click once the picture is up starts the fade out.
func dismiss() -> bool:
	if stage != 1: return false
	stage = 2
	_clock = 0.0
	return true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()
		accept_event()
