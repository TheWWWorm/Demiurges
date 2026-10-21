class_name ELCombatManaPanel
extends Control
## The X choice of a variable spell or a pay-X ability, inside the combat
## panel's information box as in both games: IncreaseMana, DecreaseMana,
## ManaOk and ManaCancel drawn from their CutParts, and the chosen value over
## its limit ("X/limit") in the box's upper line, where the phase caption
## stands otherwise. Increase stops at the limit, Decrease at the minimum (0
## unless the ability names one); OK takes the value to the next step (target
## or cast), Cancel drops the spell or ability. Coordinates are the original
## 800x600 layout, bottom-anchored like ELCombatRail.
signal confirmed
signal cancelled
signal changed(value: int)

const CONTROLS := ["IncreaseMana", "DecreaseMana", "ManaOk", "ManaCancel"]
## Upper line of the information box (800x600 layout).
const READOUT := Rect2(516, 492, 165, 22)
const INK := Color("d6bb88")

var buttons: Dictionary = {}
## The chosen value and its bounds.
var amount := Range.new()
var readout: Label
var _rects: Dictionary = {}
var _profile: ELProfile

func build(profile: ELProfile) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	_rects.clear()
	_profile = profile
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.step = 1
	amount.rounded = true
	for row: Dictionary in profile.table("CutParts").values():
		var control := str(row.get("Ctrl", ""))
		if control not in CONTROLS: continue
		var rect := Rect2(row.ScrL, row.ScrT, row.get("ScrW", row.TxtW), row.get("ScrH", row.TxtH))
		_rects[control] = _rects[control].merge(rect) if _rects.has(control) else rect
	for control: String in CONTROLS:
		if not _rects.has(control): continue
		var button := ELCutPartButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		button.build(profile, control, _rects[control])
		add_child(button)
		buttons[control] = button
	if buttons.has("IncreaseMana"): buttons.IncreaseMana.pressed.connect(step.bind(1))
	if buttons.has("DecreaseMana"): buttons.DecreaseMana.pressed.connect(step.bind(-1))
	if buttons.has("ManaOk"): buttons.ManaOk.pressed.connect(func(): confirmed.emit())
	if buttons.has("ManaCancel"): buttons.ManaCancel.pressed.connect(func(): cancelled.emit())
	readout = Label.new()
	readout.name = "ManaReadout"
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	readout.add_theme_font_size_override("font_size", 15)
	readout.add_theme_color_override("font_color", INK)
	readout.add_theme_color_override("font_outline_color", Color.BLACK)
	readout.add_theme_constant_override("outline_size", 3)
	add_child(readout)
	hide()
	layout()

func has_art() -> bool:
	return buttons.size() == CONTROLS.size()

## Shows the choice with `initial` clamped to [minimum, limit].
func open(minimum: int, limit: int, initial: int) -> void:
	amount.min_value = minimum
	amount.max_value = maxi(minimum, limit)
	amount.value = clampi(initial, minimum, maxi(minimum, limit))
	_show_value()
	show()

func close() -> void:
	hide()

func value() -> int:
	return int(amount.value)

func step(delta: int) -> void:
	amount.value = clampi(int(amount.value) + delta, int(amount.min_value), int(amount.max_value))
	_show_value()
	changed.emit(int(amount.value))

func set_value(number: int) -> void:
	amount.value = clampi(number, int(amount.min_value), int(amount.max_value))
	_show_value()
	changed.emit(int(amount.value))

func get_ok_button() -> BaseButton:
	return buttons.get("ManaOk")

func get_cancel_button() -> BaseButton:
	return buttons.get("ManaCancel")

func _show_value() -> void:
	if readout != null: readout.text = "%d/%d" % [int(amount.value), int(amount.max_value)]

func layout() -> void:
	for control: String in buttons:
		var rect := _place(_rects[control])
		buttons[control].position = rect.position
		buttons[control].size = rect.size
	if readout != null:
		var rect := _place(READOUT)
		readout.position = rect.position
		readout.size = rect.size

## In the original's 1024 layout the controls sit in the phase oval beside
## the buttons (their ShiftX 22 / ShiftY 224 against the panel's 168).
func _place(rect: Rect2) -> Rect2:
	if ELHudFrame.wide_layout(_profile, size.x):
		rect.position += Vector2(22, 56)
		return ELHudFrame.place(rect, size, ELHudFrame.WIDE, false)
	return ELHudFrame.place(rect, size, 800.0, false)
