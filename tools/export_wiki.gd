extends SceneTree
## Exports the encyclopedia of the installed games for the hosted wiki
## (tools/build_wiki.py packages it). The pages are built by the engine's own
## ELWikiCatalog from both games at once, exactly as the in-game wiki builds
## them: one page per card, both editions merged.
##
##   godot --path game --script /abs/tools/export_wiki.gd -- --wiki-language=ru ##     --wiki-el1="/path/to/Etherlords" --wiki-el2="/path/to/Etherlords II" ##     --wiki-output=/path/to/repo/wiki/catalog [--wiki-images=/path/to/repo/wiki/catalog/images]
##
## Without --wiki-el1/--wiki-el2 the Steam copies are used.
## --wiki-el1-texts=<text.res> and --wiki-el1-regs=<regs.res> (and the same for
## el2) replace a game's text and table archives, for example with those of
## another language edition, without changing the installation.
## --wiki-pages-from=<export.json> builds only the pages of another export, so
## language editions match. --wiki-images renders the creatures (needs
## rendering, so omit --headless) and saves the card icons of each game into
## <images>/<game>/; pictures already there are kept unless --wiki-images-all.
## It also renders the story heroes that guide pages list (`heroes:` front
## matter, ELWikiData) as <images>/<game>/hero-<row>.webp. Without
## --wiki-output only the pictures are made and no export is written;
## --wiki-heroes-only skips the cards.

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback := "") -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return fallback

func _flag(name: String) -> bool:
	return ("--" + name) in OS.get_cmdline_user_args()

func _fail(message: String) -> void:
	printerr("export_wiki: ", message)
	quit(1)

## The game `edition` from its folder, with replaced archives; null on failure.
func _mount(edition: String, folder: String) -> ELProfile:
	var profile := ELProfile.new()
	if not profile.mount(edition, folder):
		_fail("%s: %s" % [edition, profile.error])
		return null
	var texts := _arg("wiki-%s-texts" % edition)
	if not texts.is_empty():
		var archive := ELArchive.open(texts)
		if not archive.error.is_empty():
			_fail(texts + ": " + archive.error)
			return null
		profile.texts.clear()
		for entry: String in archive.entries: profile.texts.merge(ELText.parse(archive.read(entry)), true)
	var regs := _arg("wiki-%s-regs" % edition)
	if not regs.is_empty():
		var tables := ELArchive.open(regs)
		if not tables.error.is_empty():
			_fail(regs + ": " + tables.error)
			return null
		profile.archives["regs"] = tables
		profile.tables.clear()
	return profile

func _run() -> void:
	var language := _arg("wiki-language", "en")
	var output := _arg("wiki-output")
	if output.is_empty() and _arg("wiki-images").is_empty():
		_fail("needs --wiki-output and/or --wiki-images (and --wiki-el1/--wiki-el2 without Steam copies)")
		return
	var folders := ELContentLibrary.steam_folders()
	var profiles := {}
	for edition: String in ELWikiCatalog.EDITIONS:
		var folder := _arg("wiki-" + edition, str(folders.get(edition, "")))
		if folder.is_empty(): continue
		var profile := _mount(edition, folder)
		if profile == null: return
		profiles[edition] = profile
	if profiles.is_empty():
		_fail("no game found; pass --wiki-el1 and --wiki-el2")
		return
	# --wiki-pages-from=<another export>: build exactly that export's pages.
	var only := {}
	var reference := _arg("wiki-pages-from")
	if not reference.is_empty():
		var other: Variant = JSON.parse_string(FileAccess.get_file_as_string(reference))
		if not other is Dictionary:
			_fail("cannot read " + reference)
			return
		for page: Dictionary in other.pages: only[page.key] = true
	var catalog := ELWikiCatalog.build(profiles, language, only)
	if not output.is_empty():
		var data := {"games": profiles.keys(), "language": language, "pages": catalog.pages}
		DirAccess.make_dir_recursive_absolute(output)
		var path := output.path_join("%s.json" % language)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data, "", true) + "
")
		file.close()
		print("export_wiki: %d pages from %s -> %s" % [catalog.pages.size(), ", ".join(profiles.keys()), path])
	var images := _arg("wiki-images")
	if not images.is_empty():
		for edition: String in profiles: await _images(profiles[edition], catalog, images.path_join(edition))
	quit(0)

func _images(profile: ELProfile, catalog: ELWikiCatalog, folder: String) -> void:
	if DisplayServer.get_name() == "headless":
		printerr("export_wiki: images need rendering; run without --headless")
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var redo := _flag("wiki-images-all")
	var icons := 0
	var models := 0
	# --wiki-heroes-only renders just the story heroes.
	for page: Dictionary in [] if _flag("wiki-heroes-only") else catalog.pages:
		var code := str(page.get("card", ""))
		if code.is_empty() or not profile.id in page.get("games", []): continue
		var icon_path := folder.path_join("icon-%s.png" % code)
		if redo or not FileAccess.file_exists(icon_path):
			var icon := profile.card_icon(code)
			var picture := icon.get_image() if icon != null else null
			if picture != null and not picture.is_empty():
				picture.save_png(icon_path)
				icons += 1
		var model_path := folder.path_join("%s.webp" % code)
		if page.get("kind") != "creature" or not profile.id in page.get("models", []): continue
		if not redo and FileAccess.file_exists(model_path): continue
		if await _render(ELWikiPreview.stage(profile, code, Vector2i(960, 960)), model_path): models += 1
		else: printerr("export_wiki: no model for ", code)
	# The story heroes of the guide pages.
	var heroes := 0
	var seen := {}
	for row: Dictionary in ELWikiData.PAGES.get("en", []):
		for hero: Array in row.get("heroes", []):
			if hero[0] != profile.id or seen.has(hero[1]): continue
			seen[hero[1]] = true
			var name := RegEx.create_from_string("[^a-z0-9]+").sub(str(hero[1]).to_lower(), "-", true).strip_edges().trim_prefix("-").trim_suffix("-")
			var hero_path := folder.path_join("hero-%s.webp" % name)
			if not redo and FileAccess.file_exists(hero_path): continue
			# Heroes carry faint glows; a firmer threshold frames the figure itself.
			if await _render(ELWikiPreview.stage_hero(profile, hero[1], Vector2i(960, 960)), hero_path, 0.12): heroes += 1
			else: printerr("export_wiki: no hero ", hero[1])
	print("export_wiki: %d icons, %d creature and %d hero pictures -> %s" % [icons, models, heroes, folder])

## Renders a staged figure into `path` (480 px WebP); false without a stage.
func _render(view: SubViewport, path: String, threshold := 0.025) -> bool:
	if view == null: return false
	root.add_child(view)
	# Let the idle clip and its particles run for a moment.
	for i in 12: await process_frame
	ELWikiPreview.frame(view, ELWikiPreview.YAW, ELWikiPreview.PITCH)
	for i in 3: await process_frame
	var shot := _cropped(view.get_texture().get_image(), 480, threshold)
	shot.save_webp(path, true, 0.86)
	view.queue_free()
	return true

## The square around the drawn creature (pixels unlike the background), with a
## margin, scaled to `size`.
func _cropped(image: Image, size: int, threshold := 0.025) -> Image:
	image.convert(Image.FORMAT_RGB8)
	var background := image.get_pixel(0, 0)
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if absf(c.r - background.r) + absf(c.g - background.g) + absf(c.b - background.b) < threshold: continue
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
