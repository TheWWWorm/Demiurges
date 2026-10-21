class_name ELHudFrame
extends Control
## Original interface pieces are composed directly from the mounted CutParts registry.
## The original has two combat panel layouts: the 800x600 one (Res1), with
## the phase caption in a box above the three buttons, and the 1024x768 one
## (Res2), a single row with the caption in an oval beside the buttons and
## nothing over them. A panel at least 1024 wide uses the second when the
## content has its pieces.
const WIDE := 1024.0

var pieces: Array[Dictionary] = []
var panel_texture: Texture2D
var has_wide := false

func build(profile: ELProfile) -> void:
	pieces.clear()
	has_wide = false
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", ""))
	for definition: Dictionary in profile.table("CutParts").values():
		if definition.get("Ctrl", "") != "CombatScreen":
			continue
		var masks: String = str(definition.get("Msk", ""))
		if "Res3" in masks or "Type2" in masks:
			continue
		var texture := profile.texture(paths.get(definition.Txt, ""))
		if texture == null:
			continue
		var layout := 2 if "Res2" in masks else (1 if "Res1" in masks else 0)
		has_wide = has_wide or layout == 2
		pieces.append({"texture": texture, "layout": layout,
			"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
			"destination": Rect2(definition.ScrL, definition.ScrT - 600, definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH))})
	panel_texture = profile.texture("Interface/black/combat_panel_1")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

## True when the panel uses the original's 1024 layout at this width.
static func wide_layout(profile: ELProfile, width: float) -> bool:
	if profile == null or width < WIDE: return false
	if not profile.has_meta("combat_panel_wide"):
		var found := false
		for definition: Dictionary in profile.table("CutParts").values():
			if definition.get("Ctrl", "") == "CombatScreen" and "Res2" in str(definition.get("Msk", "")) and not "Type2" in str(definition.get("Msk", "")):
				found = true
				break
		profile.set_meta("combat_panel_wide", found)
	return bool(profile.get_meta("combat_panel_wide"))

## The width the current layout was drawn for: 1024 or 800.
static func base_width(profile: ELProfile, width: float) -> float:
	return WIDE if wide_layout(profile, width) else 800.0

## Moves a point of the original layout to this panel: the bottom rows follow
## the bottom edge; parts the original shifts right in 1024 mode (`shifted`,
## its ShiftX 224 controls) follow the right edge, the rest of the right-hand
## side moves by the extra width over the layout's own.
static func place(rect: Rect2, panel: Vector2, base: float, shifted: bool) -> Rect2:
	rect.position.y += panel.y - 600.0
	if rect.position.x >= 374: rect.position.x += panel.x - (800.0 if shifted else base)
	return rect

func _draw() -> void:
	# Corners retain their proportions; the central card rail grows with the window.
	var wide := has_wide and size.x >= WIDE
	var extra := size.x - (WIDE if wide else 800.0)
	if panel_texture != null and extra > 0:
		var x := 374.0
		while x < 374 + extra:
			var width := minf(50, 374 + extra - x)
			draw_texture_rect_region(panel_texture, Rect2(x, size.y - 61, width, 61), Rect2(32, 0, width, 61))
			x += width
	for piece: Dictionary in pieces:
		if piece.layout == (1 if wide else 2):
			continue
		var destination: Rect2 = piece.destination
		destination.position.y += size.y
		if destination.position.x >= 374:
			destination.position.x += extra
		draw_texture_rect_region(piece.texture, destination, piece.source)
