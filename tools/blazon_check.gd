extends SceneTree
## Asset-free check of the picker geometry and generated banner sheets.

var failed := false

func _initialize() -> void:
	var profile := ELProfile.new()
	profile.id = "el1"
	var all_cells := true
	for logo in ELPlayerProfile.LOGOS:
		var rect := ELBlazonScreen.logo_rect(logo)
		all_cells = all_cells and ELBlazonScreen.hit(rect.get_center()) == Vector2i(0, logo) and rect.end.y < ELBlazonScreen.COLOUR_AT.y
	_check(ELPlayerProfile.LOGOS == 150 and all_cells, "all 150 cells are selectable above the colour grid")
	var starter := ELBlazonArt.STARTER_ATLAS.get_image()
	var extra := ELBlazonArt.EXTRA_ATLAS.get_image()
	var unique := {}
	var all_logos := true
	for logo in range(ELPlayerProfile.STARTER_LOGO_FIRST, ELPlayerProfile.LOGOS):
		var is_starter := logo < ELBlazonArt.EXTRA_LOGO_FIRST
		var pixels := starter if is_starter else extra
		var sheet := ELBlazonArt.STARTER_ATLAS if is_starter else ELBlazonArt.EXTRA_ATLAS
		var region := Rect2i(ELBlazonArt.logo_region(logo))
		var tile := pixels.get_region(region)
		all_logos = all_logos and ELBlazonArt.logo_texture(profile, logo) == sheet and Rect2i(Vector2i.ZERO, pixels.get_size()).encloses(region) \
			and Rect2i(1, 1, 39, 39).encloses(tile.get_used_rect()) and tile.get_used_rect().has_area()
		unique[hash(tile.get_data())] = true
	_check(all_logos and unique.size() == 78, "78 generated logos resolve to distinct, padded cells")
	_check(ELPlayerProfile.valid_saved({"blazon": [0, 0]}) and ELPlayerProfile.valid_saved({"blazon": [83, 15]}) \
		and ELPlayerProfile.valid_saved({"blazon": [149, 15]}) and not ELPlayerProfile.valid_saved({"blazon": [150, 0]}),
		"old and expanded saves use stable IDs with a strict upper bound")
	var picks := {}
	for i in 64:
		ELPlayerProfile.choose_starter_blazon()
		picks[ELPlayerProfile.blazon.x] = true
	_check(picks.size() > 1 and picks.keys().all(func(id: int) -> bool: return id >= 72 and id < 150),
		"starter selection varies within the generated set")
	quit(1 if failed else 0)

func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	failed = failed or not ok
