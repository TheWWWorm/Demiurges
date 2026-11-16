class_name ELSharperArtScreen
extends CanvasLayer
## "Preparing sharper art": the step that enlarges the games' icons and
## interface art (ELIconUpscale.Preparation), in front of everything, with
## a progress bar, the sheets done, the time taken and the time left, and a
## Cancel button (what is done is kept; the next run resumes). It can open
## first as a prompt (Start / Later) with an estimate of the time and the
## disk space, so the work never starts without the player's consent.
##
## Emits `closed` with whether every sheet is ready.

signal closed(complete: bool)

const INK := Color(0.93, 0.89, 0.8)
const DIM := Color(0.72, 0.68, 0.6)

var upscalers: Array = []
var profile: ELProfile
## Called with "later" when the prompt is dismissed (ELSettings remembers it).
var on_later: Callable
var preparation: ELIconUpscale.Preparation
var _panel: PanelContainer
var _title: Label
var _body: Label
var _bar: ProgressBar
var _counts: Label
var _start: Button
var _later: Button
var _cancel: Button
var _close: Button
## Frame times while the screen works (the worst, in microseconds), so a
## check can tell it stayed responsive.
var worst_frame_usec := 0
var _last_frame := 0

## Opens the screen over `parent` for these editions' upscalers: a prompt
## first when `ask`, otherwise the preparation at once.
static func open(parent: Node, of: Array, shown: ELProfile, ask: bool) -> ELSharperArtScreen:
	var screen := ELSharperArtScreen.new()
	screen.upscalers = of
	screen.profile = shown
	parent.add_child(screen)
	if ask: screen.show_prompt()
	else: screen.begin()
	return screen

func _t(text: String) -> String:
	return ELRemakeText.t(text, profile)

func _ready() -> void:
	layer = 90
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "SharperArt"
	_panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.08, 0.97)
	style.border_color = Color(0.55, 0.45, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	_title = _label("", 22, INK)
	column.add_child(_title)
	_body = _label("", 16, DIM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 576
	column.add_child(_body)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(576, 26)
	_bar.show_percentage = true
	_bar.visible = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.045, 0.04)
	track.border_color = Color(0.4, 0.33, 0.22)
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.58, 0.34)
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_color_override("font_color", INK)
	_bar.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_bar.add_theme_constant_override("outline_size", 4)
	column.add_child(_bar)
	_counts = _label("", 15, INK)
	_counts.visible = false
	column.add_child(_counts)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_later = _button(buttons, "Later", "Later")
	_start = _button(buttons, "Start", "Start")
	_cancel = _button(buttons, "Cancel", "Cancel")
	_close = _button(buttons, "Close", "Close")
	_later.pressed.connect(func():
		if on_later.is_valid(): on_later.call("later")
		_end())
	_start.pressed.connect(begin)
	_cancel.pressed.connect(func():
		if preparation != null and not preparation.finished:
			preparation.cancel()
			_cancel.disabled = true
			_cancel.text = _t("Stopping…"))
	_close.pressed.connect(_end)
	for button: Button in [_later, _start, _cancel, _close]: button.visible = false

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(box: HBoxContainer, node_name: String, caption: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = _t(caption)
	button.custom_minimum_size = Vector2(120, 36)
	box.add_child(button)
	return button

## The prompt: what the step does, how long it takes and the disk it needs.
func show_prompt() -> void:
	if _title == null: await ready
	var estimate := ELIconUpscale.estimate(upscalers)
	_title.text = _t("Prepare sharper art?")
	_body.text = _t("The games' icons and interface art can be enlarged once on this computer by a small AI model, so they look sharp on this screen. It takes about %s and %s of disk space. You can play with the original art meanwhile and prepare it later from Options.") % [
		duration(float(estimate.seconds)), size_text(int(estimate.bytes))]
	_later.visible = true
	_start.visible = true
	_start.grab_focus.call_deferred()

## Starts the preparation and shows its progress.
func begin() -> void:
	if _title == null: await ready
	preparation = ELIconUpscale.Preparation.new(upscalers)
	preparation.start()
	_title.text = _t("Preparing sharper art")
	_body.text = _t("Enlarging the games' icons and interface art on this computer. Cancel keeps what is done; the rest can be prepared later from Options.")
	_later.visible = false
	_start.visible = false
	_cancel.visible = true
	_bar.visible = true
	_counts.visible = true
	_last_frame = Time.get_ticks_usec()
	_update()

func _process(_delta: float) -> void:
	if preparation == null or (preparation.finished and not _cancel.visible): return
	var now := Time.get_ticks_usec()
	if _last_frame > 0: worst_frame_usec = maxi(worst_frame_usec, now - _last_frame)
	_last_frame = now
	if preparation.poll():
		_done()
		return
	_update()

func _update() -> void:
	_bar.max_value = maxi(preparation.total, 1)
	_bar.value = preparation.done
	_counts.text = _t("%d of %d sheets · %s elapsed · about %s left") % [preparation.done, preparation.total, clock(preparation.elapsed()), clock(preparation.remaining())]

func _done() -> void:
	_cancel.visible = false
	_close.visible = true
	_close.grab_focus.call_deferred()
	_update()
	# Textures made before now draw their finished pictures.
	for upscaler: ELIconUpscale in upscalers: upscaler.apply_all()
	var complete := preparation.done >= preparation.total
	_title.text = _t("Sharper art is ready") if complete else _t("Sharper art: stopped")
	_counts.text = _t("%d of %d sheets · %s elapsed") % [preparation.done, preparation.total, clock(preparation.elapsed())]
	if preparation.failed > 0: _body.text = _t("Some sheets could not be enlarged and stay as they were.")
	elif not complete: _body.text = _t("What is done is kept. Prepare the rest later from Options.")
	else: _body.text = _t("Screens opened from now on use the sharper art.")

func _end() -> void:
	var complete := preparation != null and preparation.finished and preparation.done >= preparation.total
	closed.emit(complete)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# The screen is in front: keys do not reach the game under it.
	if event is InputEventKey: get_viewport().set_input_as_handled()

## "1:05" or "12:40" (minutes and seconds) or "1:02:03".
static func clock(seconds: float) -> String:
	var whole := maxi(0, roundi(seconds))
	if whole >= 3600: return "%d:%02d:%02d" % [whole / 3600, (whole / 60) % 60, whole % 60]
	return "%d:%02d" % [whole / 60, whole % 60]

## "about a minute", "12 minutes"... in the screen's language.
func duration(seconds: float) -> String:
	var minutes := maxi(1, ceili(seconds / 60.0))
	return _t("1 minute") if minutes == 1 else _t("%d minutes") % minutes

func size_text(bytes: int) -> String:
	if bytes >= 1024 * 1024 * 1024: return _t("%.1f GB") % (bytes / 1073741824.0)
	return _t("%d MB") % maxi(1, roundi(bytes / 1048576.0))
