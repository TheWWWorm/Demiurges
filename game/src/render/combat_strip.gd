class_name ELCombatStrip
extends Control
## The combat panel's upper icon strip (the original "Abilities" panel): the
## shown character's enchantments or a hero's graveyard as 50x50 spell icons
## on a 53 px pitch, oldest first. AbilitieScrollLeft/Right move it one icon
## per press with a short slide and repeat while held; a refill with other
## contents starts again at the first icon. An enabled icon plays the card
## turn sound when clicked, a disabled one the error sound.
## Drawn in the original list look (ELListLook), with the frame tile in
## every empty visible slot.
## Placed in the original 800x600 layout, bottom-anchored like ELHudFrame;
## a wider window shows more icons, as the card rail does.
signal item_pressed(index: int)

const CLIP := Rect2(130, 480, 360, 60)
const FIRST := Vector2(151, 489)
const VISIBLE := 6
const PITCH := 53
const ICON := 50
## 11 px per frame of the original's 60 Hz update.
const SLIDE := 660.0
const REPEAT := 0.3
const SOUND := "Buttons/cardturn.wav"

var profile: ELProfile
var items: Array[Dictionary] = []
var first := 0
var offset := 0.0
var left: ELCutPartButton
var right: ELCutPartButton
var buttons: Array[TextureButton] = []
var _view: Control
var _row: Control
var _key := ""
var _held := 0
var _repeat := 0.0
var _frames: Control
var look: ELListLook

func build(data: ELProfile) -> void:
	profile = data
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	items.clear()
	first = 0
	offset = 0.0
	_key = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_row)
	_frames = Control.new()
	_frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frames.draw.connect(_draw_frames)
	_view.add_child(_frames)
	_view.move_child(_frames, 0)
	look = ELListLook.load(profile)
	left = _arrow("AbilitieScrollLeft", -1)
	right = _arrow("AbilitieScrollRight", 1)
	layout()

## The frame tile in every visible slot past the last icon.
func _draw_frames() -> void:
	if look != null: look.draw_frames(_frames, FIRST - CLIP.position, items.size() - first, visible_count(), PITCH, ICON)

func _arrow(control: String, direction: int) -> ELCutPartButton:
	var bounds := Rect2()
	for row: Dictionary in profile.table("CutParts").values():
		if str(row.get("Ctrl", "")) != control: continue
		var rect := Rect2(row.ScrL, row.ScrT, row.get("ScrW", row.TxtW), row.get("ScrH", row.TxtH))
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	var button := ELCutPartButton.new()
	button.build(profile, control, bounds)
	button.push_at_rest = true
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.dim_disabled = false
	button.set_meta("strip_arrow", direction)
	button.set_meta("origin", bounds.position)
	button.pressed.connect(_press_arrow.bind(direction))
	button.button_up.connect(func(): _held = 0)
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	add_child(button)
	return button

## Icons that fit: six in the original window, more when it is wider.
func visible_count() -> int:
	return VISIBLE + maxi(0, int((size.x - CLIP.size.x) / PITCH))

func layout() -> void:
	if _view == null: return
	_view.position = Vector2.ZERO
	_view.size = size
	if _frames != null:
		_frames.size = size
		_frames.queue_redraw()
	var extra := size.x - CLIP.size.x
	if left != null: left.position = left.get_meta("origin") - CLIP.position
	if right != null: right.position = right.get_meta("origin") - CLIP.position + Vector2(extra, 0)
	_place_row()
	_update_arrows()

## Replaces the icons. `key` names the shown list (character, mode and
## contents); a different list starts again at the first icon.
func set_items(list: Array[Dictionary], key: String) -> void:
	if key != _key:
		first = 0
		offset = 0.0
		_key = key
	items = list
	first = clampi(first, 0, maxi(0, items.size() - visible_count()))
	for button in buttons:
		_row.remove_child(button)
		button.queue_free()
	buttons.clear()
	for i in items.size():
		var item: Dictionary = items[i]
		var button := TextureButton.new()
		button.texture_normal = item.get("icon")
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.size = Vector2(ICON, ICON)
		button.position = Vector2(FIRST.x - CLIP.position.x + i * PITCH, FIRST.y - CLIP.position.y)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = str(item.get("tooltip", ""))
		button.disabled = not item.get("enabled", false)
		look.dress(button)
		for key_name: String in item.get("meta", {}): button.set_meta(key_name, item.meta[key_name])
		ELUiSounds.bind_path(button, profile, SOUND)
		button.pressed.connect(func(): item_pressed.emit(i))
		_row.add_child(button)
		buttons.append(button)
	_place_row()
	_update_arrows()
	if _frames != null: _frames.queue_redraw()

func scroll(direction: int) -> void:
	var limit := maxi(0, items.size() - visible_count())
	var next := clampi(first + direction, 0, limit)
	if next == first: return
	first = next
	_update_arrows()
	if _frames != null: _frames.queue_redraw()
	set_process(true)

func _press_arrow(direction: int) -> void:
	scroll(direction)
	_held = direction
	_repeat = REPEAT
	set_process(true)

func _process(delta: float) -> void:
	var target := float(first * PITCH)
	offset = move_toward(offset, target, SLIDE * delta)
	_place_row()
	if _held != 0:
		var button := left if _held < 0 else right
		if not button.button_pressed or button.disabled: _held = 0
		else:
			_repeat -= delta
			if _repeat <= 0.0:
				_repeat = REPEAT
				ELUiSounds.play(profile, str(button.get_meta("ui_sound", "")))
				scroll(_held)
	if _held == 0 and is_equal_approx(offset, target): set_process(false)

func _place_row() -> void:
	if _row != null: _row.position = Vector2(-offset, 0)

func _update_arrows() -> void:
	if left == null or right == null: return
	left.disabled = first <= 0
	right.disabled = first + visible_count() >= items.size()
	left.queue_redraw()
	right.queue_redraw()
