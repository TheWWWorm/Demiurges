class_name ELHudFrame
extends Control
## Original interface pieces are composed directly from the mounted CutParts registry.
var pieces: Array[Dictionary] = []
var panel_texture: Texture2D

func build(profile: ELProfile) -> void:
	pieces.clear()
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", ""))
	for definition: Dictionary in profile.table("CutParts").values():
		if definition.get("Ctrl", "") != "CombatScreen":
			continue
		var masks: String = str(definition.get("Msk", ""))
		if "Res2" in masks or "Res3" in masks or "Type2" in masks:
			continue
		var texture := profile.texture(paths.get(definition.Txt, ""))
		if texture == null:
			continue
		pieces.append({"texture": texture,
			"source": Rect2(definition.TxtL, definition.TxtT, definition.TxtW, definition.TxtH),
			"destination": Rect2(definition.ScrL, definition.ScrT - 600, definition.get("ScrW", definition.TxtW), definition.get("ScrH", definition.TxtH))})
	panel_texture = profile.texture("Interface/black/combat_panel_1")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	# Corners retain their proportions; the central card rail grows with the window.
	var extra := size.x - 800.0
	if panel_texture != null and extra > 0:
		var x := 374.0
		while x < 374 + extra:
			var width := minf(50, 374 + extra - x)
			draw_texture_rect_region(panel_texture, Rect2(x, size.y - 61, width, 61), Rect2(32, 0, width, 61))
			x += width
	for piece: Dictionary in pieces:
		var destination: Rect2 = piece.destination
		destination.position.y += size.y
		if destination.position.x >= 374:
			destination.position.x += extra
		draw_texture_rect_region(piece.texture, destination, piece.source)
