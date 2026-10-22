class_name ELCutPartButton
extends BaseButton
## A push button drawn from an original control's CutParts states: "Free"
## pieces at rest, "Free"+"Light" pieces added on hover and "Push" pieces while
## pressed. Pieces are placed relative to the control's rectangle in the
## original 800x600 layout; `type` keeps only pieces with that mask (Type1/2).
## Phase-animated pieces (Phase2..6) are the battle buttons' shutter: with
## `shutter` on, the plate slides over the control frame by frame while it is
## unavailable (disabled) and back when it becomes available again.
var pieces := {"normal": [], "hover": [], "pressed": [], "push": []}
## Shutter frames Phase2 (open) .. Phase6 (closed).
var phases: Array = [[], [], [], [], []]
var shutter := false
## The battle buttons light their "Push" frame under the pointer as well as
## while pressed.
var push_on_hover := false
## Draws for another button (its state, hover and press) without taking input.
var mirror: BaseButton
## 0 open .. 5 fully closed.
var closing := 0.0
## Seconds per shutter frame.
const SHUTTER_STEP := 0.033
var origin := Vector2.ZERO
## A control with no "Free" art of its own (the combat strip's scroll arrows)
## shows its plain "Push" piece at rest, as the front-end menus do.
var push_at_rest := false
## Controls without "Disabled" art (scroll arrows) look the same when disabled.
var dim_disabled := true

func build(profile: ELProfile, control: String, rect: Rect2, type := "") -> void:
	for state: String in pieces: pieces[state].clear()
	for frames: Array in phases: frames.clear()
	origin = rect.position
	custom_minimum_size = rect.size
	size = rect.size
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for definition: Dictionary in profile.table("CutParts").values():
		if definition.get("Ctrl", "") != control: continue
		var raw: Variant = definition.get("Msk", [])
		var masks: Array = raw if raw is Array else [raw]
		if "Res2" in masks or "Res3" in masks: continue
		if not type.is_empty() and (("Type1" in masks or "Type2" in masks) and not type in masks): continue
		var phase := -1
		for m: Variant in masks:
			if str(m).begins_with("Phase") and str(m) != "Phase1": phase = int(str(m).substr(5)) - 2
		if phase >= 0:
			var frame_texture := profile.texture(paths.get(definition.get("Txt", ""), ""))
			if phase < phases.size() and frame_texture != null: phases[phase].append({"texture": frame_texture,
				"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
				"destination": Rect2(Vector2(definition.ScrL, definition.ScrT) - origin, Vector2(definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH)))})
			continue
		var state := ""
		if "Push" in masks:
			state = "pressed"
			if not "Light" in masks: pieces.push.append({"texture": profile.texture(paths.get(definition.get("Txt", ""), "")),
				"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
				"destination": Rect2(Vector2(definition.ScrL, definition.ScrT) - origin, Vector2(definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH)))})
		elif "Free" in masks: state = "hover" if "Light" in masks else "normal"
		# A "Light" piece alone is the hover glow over either state.
		elif "Light" in masks: state = "hover"
		if state.is_empty(): continue
		var texture := profile.texture(paths.get(definition.get("Txt", ""), ""))
		if texture == null: continue
		pieces[state].append({"texture": texture,
			"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
			"destination": Rect2(Vector2(definition.ScrL, definition.ScrT) - origin, Vector2(definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH)))})
	var tip := ""
	var row: Variant = null
	for candidate: Dictionary in profile.table("Controls").values():
		if str(candidate.get("Name", "")) == control: row = candidate
	if row != null and not str(row.get("ToolTip", "")).is_empty(): tip = profile.text(str(row.ToolTip))
	tooltip_text = tip
	ELUiSounds.bind(self, profile, control)
	queue_redraw()

func has_art() -> bool:
	return not (pieces.normal.is_empty() and pieces.hover.is_empty() and pieces.pressed.is_empty())

func has_shutter() -> bool:
	return shutter and phases.all(func(frames: Array) -> bool: return not frames.is_empty())

## Shows the shutter fully open or closed at once (a new battle screen).
func settle() -> void:
	closing = 5.0 if _unavailable() else 0.0
	queue_redraw()

func _unavailable() -> bool:
	return mirror.disabled if mirror != null else disabled

var _mirror_mode := -1

func _process(delta: float) -> void:
	if mirror != null and mirror.get_draw_mode() != _mirror_mode:
		_mirror_mode = mirror.get_draw_mode()
		queue_redraw()
	if not has_shutter(): return
	var goal := 5.0 if _unavailable() else 0.0
	if not is_equal_approx(closing, goal):
		closing = move_toward(closing, goal, delta / SHUTTER_STEP)
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_READY: set_process(shutter or mirror != null)

func _draw() -> void:
	if has_shutter() and closing > 0.0:
		for piece: Dictionary in phases[clampi(ceili(closing) - 1, 0, 4)]:
			if piece.texture != null: draw_texture_rect_region(piece.texture, piece.destination, piece.source)
		return
	var mode := mirror.get_draw_mode() if mirror != null else get_draw_mode()
	var states: Array[String] = ["normal"]
	match mode:
		DRAW_HOVER: states.assign(["push", "hover"] if push_on_hover else ["normal", "hover"])
		DRAW_PRESSED, DRAW_HOVER_PRESSED: states = ["pressed"]
	if push_at_rest and pieces.normal.is_empty() and states[0] == "normal": states[0] = "push"
	for state in states:
		for piece: Dictionary in pieces[state]:
			if piece.texture != null: draw_texture_rect_region(piece.texture, piece.destination, piece.source)
	if dim_disabled and mode == DRAW_DISABLED: draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
