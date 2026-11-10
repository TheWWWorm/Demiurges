class_name ELFirstClock
extends Label
## The original clock frame is shared by both editions, with different combat text.

const FRAME := Rect2(0, 0, 104, 41)
var _seconds := -1
var _second_combat := false

func build(profile: ELProfile, battle: bool) -> void:
	_second_combat = profile.id == "el2" and battle
	name = "CombatClock" if battle else "AdventureClock"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_override("font", ELArtDropList.row_font())
	add_theme_font_size_override("font_size", 20)
	add_theme_constant_override("outline_size", 4)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -184 if _second_combat else (-175 if battle else -370)
	offset_top = 20 if _second_combat else (12 if battle else 0)
	offset_right = offset_left + FRAME.size.x
	offset_bottom = offset_top + FRAME.size.y
	var sheet := _frame_texture(profile)
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = FRAME
		atlas.filter_clip = true
		var background := StyleBoxTexture.new()
		background.texture = atlas
		add_theme_stylebox_override("normal", background)
	hide()

func _frame_texture(profile: ELProfile) -> Texture2D:
	if _second_combat: return profile.texture("Interface/clock.mmp")
	var path := profile.file("Resources/gp1tex.res")
	if path.is_empty(): return null
	var archive := ELArchive.open(path)
	var frame := ELTexture.decode(archive.read("Interface/clock.mmp"))
	return ImageTexture.create_from_image(frame) if frame != null and not frame.is_empty() else null

func show_seconds(seconds: int) -> void:
	if seconds == _seconds: return
	_seconds = seconds
	visible = seconds >= 0
	if visible:
		var format := "%02d:%02d" if _second_combat else "%d:%d"
		text = format % [seconds / 60, seconds % 60]
		var normal := Color.WHITE if _second_combat else Color("d6bb88")
		add_theme_color_override("font_color", Color.RED if seconds <= 10 else normal)
