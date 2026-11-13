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
