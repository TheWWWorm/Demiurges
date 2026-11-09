extends SceneTree
## Exports the encyclopedia pages of one installed game for the hosted wiki
## (tools/build_wiki.py packages them). The pages are built by the engine's own
## ELWikiCatalog, exactly as the in-game wiki builds them.
##
##   godot --path game --script /abs/tools/export_wiki.gd -- \
##     --wiki-game=el1 --wiki-path="/path/to/Etherlords" --wiki-language=ru \
##     --wiki-output=/path/to/repo/wiki/catalog [--wiki-images=/path/to/repo/wiki/catalog/images]
##
## --wiki-texts=<text.res> and --wiki-regs=<regs.res> replace the installed
## game's text and table archives, for example with those of another language
## edition, without changing the installation. --wiki-pages-from=<export.json>
## builds only the pages of another export, so language editions match. --wiki-images renders every
## creature (needs rendering, so omit --headless) and saves every card icon.

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback := "") -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return fallback

func _fail(message: String) -> void:
	printerr("export_wiki: ", message)
	quit(1)

func _run() -> void:
	var game := _arg("wiki-game")
	var language := _arg("wiki-language", "en")
	var output := _arg("wiki-output")
	if not game in ["el1", "el2"] or output.is_empty() or _arg("wiki-path").is_empty():
		_fail("needs --wiki-game=el1|el2, --wiki-path and --wiki-output")
		return
	var profile := ELProfile.new()
	if not profile.mount(game, _arg("wiki-path")):
		_fail(profile.error)
		return
	var texts := _arg("wiki-texts")
	if not texts.is_empty():
		var archive := ELArchive.open(texts)
		if not archive.error.is_empty():
			_fail(texts + ": " + archive.error)
			return
		profile.texts.clear()
		for entry: String in archive.entries: profile.texts.merge(ELText.parse(archive.read(entry)), true)
	var regs := _arg("wiki-regs")
	if not regs.is_empty():
		var tables := ELArchive.open(regs)
		if not tables.error.is_empty():
			_fail(regs + ": " + tables.error)
			return
		profile.archives["regs"] = tables
		profile.tables.clear()
	# --wiki-pages-from=<another export>: build exactly that export's pages.
	var only := {}
	var reference := _arg("wiki-pages-from")
	if not reference.is_empty():
		var other: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference))
		if not other is Dictionary:
			_fail("cannot read " + reference)
			return
		for page: Dictionary in other.pages: only[page.key] = true
	var catalog := ELWikiCatalog.build(profile, language, only)
	var data := {"game": game, "language": language, "categories": ELWikiCatalog.categories(game, language), "pages": catalog.pages}
	DirAccess.make_dir_recursive_absolute(output)
	var path := output.path_join("%s-%s.json" % [game, language])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true) + "\n")
	file.close()
	print("export_wiki: %d pages -> %s" % [catalog.pages.size(), path])
	var images := _arg("wiki-images")
	if not images.is_empty(): await _images(profile, catalog, images.path_join(game))
	quit(0)

func _images(profile: ELProfile, catalog: ELWikiCatalog, folder: String) -> void:
	if DisplayServer.get_name() == "headless":
		printerr("export_wiki: images need rendering; run without --headless")
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var icons := 0
	var models := 0
	for page: Dictionary in catalog.pages:
		var code := str(page.get("card", ""))
		if code.is_empty(): continue
		var icon := profile.card_icon(code)
		var picture := icon.get_image() if icon != null else null
		if picture != null and not picture.is_empty():
			picture.save_png(folder.path_join("icon-%s.png" % code))
			icons += 1
		if page.get("kind") != "creature": continue
		var view := ELWikiPreview.stage(profile, code, Vector2i(960, 960))
		if view == null:
			printerr("export_wiki: no model for ", code)
			continue
		root.add_child(view)
		await process_frame
		ELWikiPreview.frame(view, ELWikiPreview.YAW, ELWikiPreview.PITCH)
		for i in 3: await process_frame
		var shot := _cropped(view.get_texture().get_image(), 480)
		shot.save_webp(folder.path_join("%s.webp" % code), true, 0.86)
		view.queue_free()
		models += 1
	print("export_wiki: %d icons, %d creature pictures -> %s" % [icons, models, folder])

## The square around the drawn creature (pixels unlike the background), with a
## margin, scaled to `size`.
func _cropped(image: Image, size: int) -> Image:
	image.convert(Image.FORMAT_RGB8)
	var background := image.get_pixel(0, 0)
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if absf(c.r - background.r) + absf(c.g - background.g) + absf(c.b - background.b) < 0.06: continue
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0: return image
	var side := int(maxf(high.x - low.x, high.y - low.y) * 1.16) + 4
	var centre := (low + high) / 2
	var square := Image.create(side, side, false, Image.FORMAT_RGB8)
	square.fill(background)
	square.blit_rect(image, Rect2i(centre - Vector2i(side, side) / 2, Vector2i(side, side)), Vector2i.ZERO)
	square.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return square
