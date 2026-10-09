class_name ELCutPartButton
extends BaseButton
## A push button drawn from an original control's CutParts states: "Free"
## pieces at rest, "Free"+"Light" pieces added on hover and "Push" pieces while
## pressed. Pieces are placed relative to the control's rectangle in the
## original 800x600 layout; `type` keeps only pieces with that mask (Type1/2),
## and phase-animated pieces (Phase2..6) are left out.
var pieces := {"normal": [], "hover": [], "pressed": [], "push": []}
var origin := Vector2.ZERO
## A control with no "Free" art of its own (the combat strip's scroll arrows)
## shows its plain "Push" piece at rest, as the front-end menus do.
var push_at_rest := false
## Controls without "Disabled" art (scroll arrows) look the same when disabled.
var dim_disabled := true

func build(profile: ELProfile, control: String, rect: Rect2, type := "") -> void:
	for state: String in pieces: pieces[state].clear()
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
		if masks.any(func(m: Variant) -> bool: return str(m).begins_with("Phase") and str(m) != "Phase1"): continue
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

func _draw() -> void:
	var states: Array[String] = ["normal"]
	match get_draw_mode():
		DRAW_HOVER: states = ["normal", "hover"]
		DRAW_PRESSED, DRAW_HOVER_PRESSED: states = ["pressed"]
	if push_at_rest and pieces.normal.is_empty() and states[0] == "normal": states[0] = "push"
	for state in states:
		for piece: Dictionary in pieces[state]:
			if piece.texture != null: draw_texture_rect_region(piece.texture, piece.destination, piece.source)
	if dim_disabled and get_draw_mode() == DRAW_DISABLED: draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
