class_name ELListLook
extends RefCounted
## The original combat lists' item look, shared by the upper icon strip, the
## hand and the artifact rail (EL2 list draw ``, hand slot buttons
## ``; EL1 ``..``). Textures by the initializer tables:
## - an empty slot shows the HERO_PANEL_3 tile (206,60 50x50);
## - a disabled item carries SYMBOLS (40,60 19x19) stretched over it, tinted
##   #551111;
## - an enabled item under the pointer gets the ADV_SCREEN_2 border
##   (206,155 50x50);
## - a pressed enabled item is drawn 2 px smaller on every side.

const FRAME := Rect2(206, 60, 50, 50)
const VEIL := Rect2(40, 60, 19, 19)
const VEIL_TINT := Color8(0x55, 0x11, 0x11)
const HOVER := Rect2(206, 155, 50, 50)

var frame: AtlasTexture
var veil: AtlasTexture
var hover: AtlasTexture

static func load(profile: ELProfile) -> ELListLook:
	var look := ELListLook.new()
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	look.frame = _art(profile, paths, "HERO_PANEL_3", FRAME)
	look.veil = _art(profile, paths, "SYMBOLS", VEIL)
	look.hover = _art(profile, paths, "ADV_SCREEN_2", HOVER)
	return look

static func _art(profile: ELProfile, paths: Dictionary, name: String, region: Rect2) -> AtlasTexture:
	var texture := profile.texture(paths.get(name, "")) if paths.has(name) else null
	if texture == null: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	atlas.filter_clip = true
	return atlas

## Draws `button`'s icon in the original style. The button keeps its input,
## tooltip and children; its own texture draw is hidden.
func dress(button: TextureButton) -> void:
	button.self_modulate = Color(1, 1, 1, 0)
	var face := Face.new()
	face.look = self
	face.button = button
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(face)
	button.move_child(face, 0)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for signal_name: String in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
		button.connect(signal_name, face.queue_redraw)

## Empty slot tiles from `start` up to `count` slots of `pitch` px at `origin`.
func draw_frames(canvas: CanvasItem, origin: Vector2, start: int, count: int, pitch: float, size := 50.0) -> void:
	if frame == null: return
	for slot in range(maxi(0, start), count):
		canvas.draw_texture_rect(frame, Rect2(origin + Vector2(slot * pitch, 0), Vector2(size, size)), false)

class Face extends Control:
	var look: ELListLook
	var button: TextureButton

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var mode := button.get_draw_mode()
		if not button.disabled and (mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED) and button.is_hovered():
			rect = rect.grow(-2)
		if button.texture_normal != null: draw_texture_rect(button.texture_normal, rect, false)
		if button.disabled:
			if look.veil != null: draw_texture_rect(look.veil, rect, false, ELListLook.VEIL_TINT)
		elif mode == BaseButton.DRAW_HOVER and look.hover != null:
			draw_texture_rect(look.hover, rect, false)

## The rail's number glyphs: ADV_SCREEN_2 row y 246, 10x10 cells for
## "-./0123456789". Artifact charges sit at the icon's lower right, a black
## copy one pixel right and down under the white one: EL1 `` steps
## 10 px with the last digit at (40,40); EL2 `` steps 8 px with the
## last digit at (39,39) of a 50 px item.
class GlyphNumber extends Control:
	var text := ""
	var sheet: Texture2D
	var step := 8
	var last := Vector2(39, 39)

	func _draw() -> void:
		if sheet == null: return
		for k in text.length():
			var code := text.unicode_at(text.length() - 1 - k) - 0x2d
			if code < 0 or code > 12: continue
			var source := Rect2(code * 10, 246, 10, 10)
			var at := last - Vector2(k * step, 0)
			draw_texture_rect_region(sheet, Rect2(at + Vector2.ONE, Vector2(10, 10)), source, Color.BLACK)
			draw_texture_rect_region(sheet, Rect2(at, Vector2(10, 10)), source)

## A charge number in the original glyphs on a 50 px rail item.
func number(value: int, first_game: bool) -> GlyphNumber:
	var label := GlyphNumber.new()
	label.text = str(value)
	label.sheet = hover.atlas if hover != null else null
	label.step = 10 if first_game else 8
	label.last = Vector2(40, 40) if first_game else Vector2(39, 39)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(50, 50)
	return label
