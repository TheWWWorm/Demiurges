extends SceneTree
## Headless check of the save pictures (GitHub #43):
## - a 256×192 scene capture is stored as a small JPEG and read back for
##   first- and second-game saves, named, quick and automatic;
## - the mission-start autosave gets its picture added without its world
##   changing;
## - second-game saves from before keep their raw RGB8 picture; saves without
##   a picture show none;
## - the first game's Load Mission screen shows the chosen save's picture in
##   the box above its details, and nothing for a save without one.
## - the second game's save lists show race marks for new and older saves;
##   the first game's mark every race playing on the saved map (#255).
## - in a rendered run, capturing a thumbnail keeps the on-screen UI visible.
##
##   godot --headless --path game --script ../tools/save_preview_check.gd
##
## Only scratch files under user://save_preview_check are written; the
## player's saves are never touched. The screen part needs the first game's
## files (user://profiles.json); without them it is skipped.

const FOLDER := "user://save_preview_check"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	_storage()
	await _screen()
	await _race_screen()
	if DisplayServer.get_name() != "headless": await _offscreen()
	for file in DirAccess.get_files_at(FOLDER): DirAccess.remove_absolute(FOLDER.path_join(file))
	DirAccess.remove_absolute(FOLDER)
	print("SAVE PREVIEW: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## A map-like test picture.
func _picture() -> Image:
	var image := Image.create(ELSaveSlots.PREVIEW_SIZE.x, ELSaveSlots.PREVIEW_SIZE.y, false, Image.FORMAT_RGB8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(x / 255.0, y / 191.0, 0.5 + 0.4 * sin(x * 0.05 + y * 0.03)))
	return image

func _difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
	return total / (a.get_width() / 4 * a.get_height() / 4 * 3)

func _document(edition: String, extra: Dictionary = {}) -> Dictionary:
	var document := {"format": ELAdventureSave.FORMAT, "version": 1, "edition": edition, "map": "check", "world": {"day": 3}, "objects": []}
	document.merge(extra, true)
	return document

func _save(name: String, document: Dictionary) -> String:
	var path := FOLDER.path_join(name + ".json")
	ELAdventureSave.new().write_document(path, document)
	return path

func _storage() -> void:
	var picture := _picture()
	var stored := ELSaveSlots.encode_preview(picture)
	check(not stored.is_empty() and stored.length() < 60000, "a scene capture is stored as a small JPEG (%d characters)" % stored.length())
	check(ELSaveSlots.encode_preview(Image.create(64, 48, false, Image.FORMAT_RGB8)).is_empty() and ELSaveSlots.encode_preview(null).is_empty(), "a picture of another size is not stored")
	for edition: String in ["el1", "el2"]:
		for type: String in [ELSaveSlots.SLOT, ELSaveSlots.AUTO]:
			var path := _save("%s-%s" % [edition, type], _document(edition, {"preview_jpg": stored}))
			var read := ELSaveSlots.preview_image({"edition": edition, "type": type, "path": path})
			check(read != null and read.get_size() == ELSaveSlots.PREVIEW_SIZE and _difference(read, picture) < 0.03, "%s %s save: its picture reads back" % [edition, type])
	var bare := _save("bare", _document("el1"))
	check(ELSaveSlots.preview_image({"edition": "el1", "type": ELSaveSlots.SLOT, "path": bare}) == null, "a save without a picture shows none")
	check(ELSaveSlots.preview_image({"edition": "el2", "type": ELSaveSlots.SLOT, "path": bare}) == null, "a save of the other game shows none")
	var broken := _save("broken", _document("el1", {"preview_jpg": "AAAA"}))
	check(ELSaveSlots.preview_image({"edition": "el1", "type": ELSaveSlots.SLOT, "path": broken}) == null, "a damaged picture shows none")
	var old := _save("old", _document("el2", {"preview_rgb": Marshalls.raw_to_base64(picture.get_data())}))
	var legacy := ELSaveSlots.preview_image({"edition": "el2", "type": ELSaveSlots.SLOT, "path": old})
	check(legacy != null and legacy.get_data() == picture.get_data(), "an earlier second-game save keeps its raw picture")
	# Mission start: the picture is added afterwards; the world stays.
	var start := _save("start", _document("el1"))
	var before: Variant = JSON.parse_string(FileAccess.get_file_as_string(start))
	check(ELSaveSlots.attach_preview(start, picture), "the mission-start autosave gets its picture")
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(start))
	after.erase("preview_jpg")
	check(after == before, "adding it leaves the saved game as it was")
	check(ELSaveSlots.preview_image({"edition": "el1", "type": ELSaveSlots.AUTO, "path": start}) != null, "the autosave row shows it")
	check(not ELSaveSlots.attach_preview(FOLDER.path_join("missing.json"), picture), "nothing is written for a missing save")

func _screen() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		return
	var menu := ELFrontMenu.new()
	menu.settings = ELSettings.new()
	menu.settings.use_edition("el1")
	root.add_child(menu)
	check(menu.build({"el1": profile}, "el1"), "the first game's menu builds")
	menu.mission_load_ui.prepare("load", ELSaveSlots.KIND_SINGLE)
	menu.show_screen("load_mission")
	await frames(1)
	var ui := menu.mission_load_ui
	check(ui.list.race_sheet != null and ui.list.race_sheet == menu.texture_named("SAVE_PANEL_6"), "el1 #255: Load Mission draws race marks from the original sheet")
	check(ELMissionLoadScreen.row_marks({"races": ["Black", "Red", "Blue"]}) == [0, 2, 3] and ELMissionLoadScreen.row_marks({"races": []}).is_empty(),
		"el1 #255: a row marks each race on its map in the original's order")
	await _first_races(profile)
	var with := FOLDER.path_join("el1-slot.json")
	var without := FOLDER.path_join("bare.json")
	ui.entries.assign([{"name": "with", "path": with, "type": ELSaveSlots.SLOT, "modified": 0, "edition": "el1", "kind": ELSaveSlots.KIND_SINGLE},
		{"name": "without", "path": without, "type": ELSaveSlots.SLOT, "modified": 0, "edition": "el1", "kind": ELSaveSlots.KIND_SINGLE}])
	ui.choose_row(0)
	var box: TextureRect = ui._preview
	check(box != null and box.texture != null and Vector2i(box.texture.get_size()) == ELSaveSlots.PREVIEW_SIZE, "Load Mission shows the chosen save's picture")
	var frame := menu.control_rect("SMInfoBounds") if menu.control_rect("SMInfoBounds").size.x > 0 else ui._rect("SMInfoBounds")
	check(box != null and absf(box.position.x - frame.position.x) < 8 and box.position.y + box.size.y < frame.position.y, "the picture sits in the box above the save's details")
	ui.choose_row(1)
	check(box != null and box.texture == null, "a save without a picture leaves the box empty")
	menu.queue_free()
	await frames(2)

## #255: the first game's rows list the races of the map's players, for new
## saves and for older ones whose header has no races.
func _first_races(profile: ELProfile) -> void:
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	var director := ELAdventureDirector.new()
	var ready := map.load_map(profile, "pmission05") and state.start(map, 1, 212, "", 1, false) and director.build(state)
	check(ready, "el1 #255: a two-race single mission loads")
	if not ready:
		state.close()
		return
	check(ELSaveSlots.current_row(state).get("races") == ["Green", "Blue"], "el1 #255: the running game's row lists the map's races (got %s)" % [ELSaveSlots.current_row(state).get("races")])
	var name := "Race Check"
	var file := ELSaveSlots.save_path("el1", name).get_file()
	var path := FOLDER.path_join(file)
	var index := path.get_basename() + ".meta.json"
	check(ELSaveSlots._write(path, index, name, ELSaveSlots.SLOT, director, {}).is_empty(), "el1 #255: a save is written with a list header")
	var identity := ELSaveSlots._slot_identity(profile, file)
	var row := ELSaveSlots._slot_row(profile, path, index, identity)
	check(row.get("races") == ["Green", "Blue"], "el1 #255: the save lists both races of the map, not only the player's (got %s)" % [row.get("races")])
	var codec := ELAdventureSave.new()
	var raw: Dictionary = codec.read_document(path)
	var old_index := row.duplicate()
	old_index.erase("races")
	raw._slot = Marshalls.utf8_to_base64(JSON.stringify(old_index))
	check(codec.write_document(path, raw) and codec.write_document(index, old_index), "el1 #255: an older header without races is written")
	var old := ELSaveSlots._slot_row(profile, path, index, identity)
	check(old.get("races") == ["Green", "Blue"], "el1 #255: the older save gets its marks from the checkpoint")
	var bad := old_index.duplicate()
	bad.races = ["Purple"]
	check(not ELSaveSlots._row_meta(JSON.stringify(bad), profile, file, identity).has("races"), "el1 #255: an unknown race in a header is ignored")
	state.close()

func _race_screen() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: the second game's files could not be mounted")
		return
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	var director := ELAdventureDirector.new()
	var ready := map.load_map(profile, "e2mission24_32") and state.start(map, 1, 212, "Maps/e2mission32") and director.build(state)
	check(ready, "the shared Chaot/Kinet map loads for the save-race check")
	if not ready:
		state.close()
		return
	var progress := ELSecondCampaign.new_game(1)
	progress.possible = ["Blue"]
	ELSecondCampaign.begin(progress, "Blue")
	state.scenario[ELSecondCampaign.KEY] = progress
	state.object(state.main_hero).shape = "BlueMainHero-1"
	var name := "Race Check"
	var file := ELSaveSlots.save_path("el2", name).get_file()
	var path := FOLDER.path_join(file)
	var index := path.get_basename() + ".meta.json"
	check(ELSaveSlots._write(path, index, name, ELSaveSlots.SLOT, director, {}).is_empty(), "a Kinet save is written with a list header")
	var identity := ELSaveSlots._slot_identity(profile, file)
	var row := ELSaveSlots._slot_row(profile, path, index, identity)
	check(row.get("race") == "Blue", "the saved hero's race is listed on a shared map")
	var codec := ELAdventureSave.new()
	var raw: Dictionary = codec.read_document(path)
	var old_index := row.duplicate()
	old_index.erase("race")
	raw._slot = Marshalls.utf8_to_base64(JSON.stringify(old_index))
	check(codec.write_document(path, raw) and codec.write_document(index, old_index), "an older header without the race field is written")
	var old := ELSaveSlots._slot_row(profile, path, index, identity)
	check(old.get("race") == "Blue", "the earlier save gets its badge from the checkpoint")
	var restored := codec.read(path, {"el2": profile})
	check(not restored.is_empty(), "the older save still restores normally")
	if not restored.is_empty(): restored.state.close()
	state.close()
	var menu := ELFrontMenu.new()
	menu.settings = ELSettings.new()
	menu.settings.use_edition("el2")
	root.add_child(menu)
	check(menu.build({"el2": profile}, "el2"), "the second game's menu builds")
	for mode: String in ["load", "save"]:
		var ui := menu.mission_load_ui
		ui.prepare(mode, ELSaveSlots.KIND_CAMPAIGN, mode == "save")
		menu.show_screen("load_campaign" if mode == "load" else "save_game")
		await frames(1)
		var headers := menu.canvas.get_children().filter(func(node: Node) -> bool: return node.name.begins_with("SaveRaceHeader_"))
		check(headers.size() == 4 and ui.list.race_sheet == menu.texture_named("SAVE_PANEL_6") and ui.list.race_sheet != null,
			"EL2 %s shows the original four-color header and uses the save marks from the original sheet" % mode)
		ui.entries.assign([old.merged({"modified": 0, "path": path}), {"name": "White", "modified": 0, "race": "White", "type": ELSaveSlots.PROGRESS}])
		ui.list.queue_redraw()
		await frames(1)
	check(ELMissionLoadScreen.race_marks("Blue") == [2] and ELMissionLoadScreen.race_marks("White") == [0, 1, 2, 3]
		and ELMissionLoadScreen.race_marks("").is_empty(), "the original marks distinguish a single race, White and an unknown race")
	menu.queue_free()
	await frames(2)

func _offscreen() -> void:
	var view := ELAdventureView.new()
	root.add_child(view)
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.position.z = 3
	view.camera.make_current()

	var figure := MeshInstance3D.new()
	figure.mesh = BoxMesh.new()
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0, 0, 1)
	figure.material_override = paint
	view.add_child(figure)

	var layers := CanvasLayer.new()
	view.add_child(layers)
	var hud := ColorRect.new()
	hud.color = Color(1, 0, 1)
	view.ui = hud
	layers.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.extras_layer = CanvasLayer.new()
	view.add_child(view.extras_layer)
	var hidden := [false]
	view.ui.visibility_changed.connect(func(): hidden[0] = hidden[0] or not view.ui.is_visible_in_tree())
	view.extras_layer.visibility_changed.connect(func(): hidden[0] = hidden[0] or not view.extras_layer.visible)

	await RenderingServer.frame_post_draw
	var preview := await view._capture_save_preview()
	var on_screen := root.get_texture().get_image()
	var shown := on_screen.get_pixelv(on_screen.get_size() / 2)
	check(not hidden[0] and shown.r > 0.8 and shown.b > 0.8, "capturing the thumbnail keeps the main HUD and overlays visible")
	check(preview != null and preview.get_size() == ELSaveSlots.PREVIEW_SIZE, "the offscreen thumbnail has the save preview dimensions")
	if preview != null:
		var pixel := preview.get_pixelv(preview.get_size() / 2)
		check(pixel.b > 0.8 and pixel.r < 0.2, "the thumbnail contains the world seen by the map camera")
	view.queue_free()
	await frames(2)
