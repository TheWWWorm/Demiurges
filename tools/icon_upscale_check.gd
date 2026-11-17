extends SceneTree
## Check of the sharper icons and interface art (ELIconUpscale and
## ELNativeAssets.upscale):
##
## - the native network gives, on a fixed tiny picture, the bytes a plain
##   numpy reference of realesr-general-x4v3 gives with the shipped weights
##   (within 2 levels), keeps opaque pictures opaque and cut-out alpha cut
##   out without dark fringes, and refuses wrong weights and sizes;
## - a sheet is worked out once, kept as lossless WebP under the digest of
##   its bytes, found again without the network, and worked out again when
##   its bytes change; a kept picture is refused for other bytes or sizes;
## - a texture given a sharp picture keeps its original size (regions in
##   original pixels still fit), image_of() gives the original, and
##   switching the kind off gives the original back;
## - with the original games' files: a preparation counts its sheets, can
##   be cancelled keeping what is done and resumed without working those
##   out again, finds its pictures again after the game's files change, and
##   keeps only the current factor's files; textures loaded afterwards (as
##   during play) draw the finished pictures, with the time each took to
##   read, and no work is started while they load or frames go by;
## - without the native library (the browser) nothing is offered or made;
## - real sheets, upscaled and reduced back, stay close to the originals.
##
##   godot --headless --path game --script ../tools/icon_upscale_check.gd
##
## Pictures go to a scratch folder in the user folder, removed afterwards.

## What the reference gives for the tiny picture: 28 x 20 RGB bytes.
const EXPECTED := [
	"AAAfAAAeAAAeAAAeAAAfAAAiAAAoCgAyHABEOQBYTgBrVwBzWgB1WAB0XAB3ZAB7cwCKkQCZqgCqwgC71QDO4ADa6QDk6gDk5gDi4wDg4gDh5Q",
	"DiAAAdAAAdAAAdAAAdAAAeAAAkAgArCgAyIwBHOQBXSwBpVwBwWQB2WwB5XQB7YwB9dgCLkACaqACpvAC0zwDK4QDa6QDm6QDn5ADi4wDi4wDj",
	"4gDhAAAcAAAcAAAcAAAcAQAeAQAhAQAoCQAyIgBINwBbSQBoUwBwWAB3WwB3WgB2YAB7cwCKigCZqACqugC2zADI3gDY5ADi5gDn5ADk5QDl5Q",
	"Hl4gHjAAAeAAAdAQEeAQAeAQAgAAAjBAAqCQA1HwBHNwBbSwBpVwV3WQB7WgB6XQB6ZACBcQCMiQCbpQCsuQC+zgDL2wDY4gDh6ADo6ADm6APm",
	"5gPk5gTmAAAfAQIhAwMiAwIgBQMkCAMpCwApFgAtKwM/QQRWVAlsWwp4WQF/XQCBXwB/agCBfgCQlgCgrAGwxAa/2APO4gDY6ADj6gPl5wXh6A",
	"fn6Arp6g3qAAIhAgUjAgYlAgYnAwMoCQcnDAYlGAMmLwo4SRJWWRdrWRRzVg5/WAyEVgGCYgCHewCSnAOnsAi4wgi/1wjN5ATR6Afc6Qff5Qzi",
	"5w/o6RLs5xTqBQspBw0pBA0oAw8rBBAtCBEwDREuFQ0tKxU6RSRTUyVkWCVsViF4VRmDTxCDVguObwyfjBKyphXEthXLyxPQ2w/W4hDX5BHa5x",
	"nh6Bnl5hbm5BfkDx04DB04Ch82CSA2DSM1ECM2FiM1ICY3MydFRytMVS1RYjJYazJmYyt1XSR6ZCONcyCpjSW9pzHcujTmwSrczyjg1iXf2SXc",
	"3yLg5CDh5yHi5h/kGzhIGThIGTpJGT5IHEJIHEBBJD9CLTs9QT5BSzY4VTIxajkwdT9BfUJVhkRnklGGmFG3rlfewF/8yl//y1Xy0U/v1Eft1T",
	"zh2jff4jbf4TDd4zLaHE1KHU1JH1BLI1VOJFxQJ19RKltNK088N0gsSkIdVjkNaTsDfkUckE0vol1Kqmd6t3zGzpP/yo7/wXv/yXv/z3X/0m3/",
	"0WLxzVnm1lfg2Fff2FHVGWRIHGJMGmJHGmRIHWhKJXJQK3RLJWg0MF4gRFgNXFMAcVQAhVkAjVcGlF0mnXRmpozAwqb/yKn/vZ3/t5P/yp3/1Z",
	"z/2ZT60ovn2Ynb34zT5InQEnlJE3ZKDW5EC2pBB2M9Dmo6GnQ2I3IqN3UXUHcEaXYAg3UAiGoAfV8AiGsTknpWn5Gxuqj5y6//zrL/waX/zqn/",
	"1az74rro6LzX57TJ67G78Lm4H6RyHqBwIJ5wI55xHZhoJZdiM5lZRJ5MUZswYJIXeJQMhY4AjYIAhHUAgnkMiotFpqSZyLXb2cH/58n/4sf/3c",
	"f82svg4M/I49S55tKo7tqk89mfMM2kMtGoONOrOs6mPMqiSsucVcqUXMGFYrltbrtbdrhKiLE3laQdmJoTiJIdjpY5mqV0wr694Mrl6czn8Nrm",
	"6dnN7Niy69yb8OOX7+SP+eWL/eWFJdexI9iwKdmzL9WzMtWtOtKsQtCqTtKvU9GpWtSkY9maetmMktRpl8tZncVSl69Nlahdtr+F2Mqm6NGd++",
	"Wh/+OO/+WA/+x0/+ty/+Zu/+Nr/+hqF9KzF9GxGtCzGs2xHMmsKM2zMs66QdbJUd3UYODVbenVfPXIkfiuoPWZo+eKndd1nrdis7VZ1b9c689f",
	"/uhm/+1f//Bc/+1Z/+5Y/+1X/+dX/+ZbG9a3GdW4G9S5HNS7H9K9Jc++NtXNR9zdWt/obunve/Tvh/fmjPrbmf/Mnfm1ouKaor5jt7Y428g68+",
	"E99+k+/+5E//BB//ZF//JH//FO/+1O/+5RHNS0G9SzG9S1HNO5INK+Icy+MNPLRt7bW+Pobuvye+zzhPLyjPXslfvoofvYouapmbVVuLUb280U",
	"8N8g9eYt/u8y//Q4//M8//FA//NG//FJ/+9NHNSyHNOzG9S2GtK5H9K9Hs++LNPIQN3YWOTlZ+jxcOj0fO/8iPH7kfbwpf3lpeW1k65Nt7gL2t",
	"AA8uIX+ukp/+wv/+w0//A8//BC//BG/+9J/+5LGtGtGdOvF9CxF86zF8q4G8y+KNDFOdfQVeLlaev0cuj4euf/gOv/jvH5l/Xpo+S/mrNItL0H",
	"1tIH9OIY9+oq/eou/+k4/+w9/exD/O1G/OxL/e1N"]
## The tiny picture's size; its pixels are made by _tiny().
const TINY := Vector2i(7, 5)
const SCRATCH := "user://icon_upscale_check"
## Time allowed to read one kept picture while a texture is made (microseconds).
const LOAD_LIMIT_USEC := 60000

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

## The fixed tiny picture (RGBA8, opaque), as the reference made it.
static func _tiny() -> Image:
	var bytes := PackedByteArray()
	for y in TINY.y:
		for x in TINY.x:
			bytes.append_array([(x * 36 + y * 7) % 256, (y * 50 + x * 3) % 256, ((x ^ y) * 29 + 40) % 256, 255])
	return Image.create_from_data(TINY.x, TINY.y, false, Image.FORMAT_RGBA8, bytes)

static func _upscale(image: Image, threads := 4) -> PackedByteArray:
	return ClassDB.class_call_static(&"ELNativeAssets", &"upscale", ELIconUpscale.weights(), image.get_data(), image.get_width(), image.get_height(), threads)

func _clear_scratch() -> void:
	var path := ProjectSettings.globalize_path(SCRATCH)
	if not DirAccess.dir_exists_absolute(path): return
	for sub: String in DirAccess.get_directories_at(path):
		for file: String in DirAccess.get_files_at(path.path_join(sub)): DirAccess.remove_absolute(path.path_join(sub).path_join(file))
		DirAccess.remove_absolute(path.path_join(sub))
	for file: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

func _run() -> void:
	check(ELIconUpscale.native, "the native library has upscale()")
	check(ELIconUpscale.weights().size() == 2426624, "the weights are shipped (%d bytes)" % ELIconUpscale.weights().size())
	if not ELIconUpscale.native or ELIconUpscale.weights().is_empty():
		_done()
		return
	_check_forward()
	_check_alpha()
	_check_invalid()
	_clear_scratch()
	ELIconUpscale.forced_folder = SCRATCH
	_check_cache()
	_check_adopt()
	_check_fallback()
	_check_kinds()
	_check_backends()
	await _check_real()
	ELIconUpscale.forced_folder = ""
	ELIconUpscale.forced_factor = 0
	_clear_scratch()
	_done()

func _done() -> void:
	print("ICON UPSCALE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_forward() -> void:
	var expected := Marshalls.base64_to_raw("".join(EXPECTED))
	check(expected.size() == TINY.x * TINY.y * 16 * 3, "the reference has %d bytes" % expected.size())
	for threads: int in [1, 3, 8]:
		var out := _upscale(_tiny(), threads)
		check(out.size() == TINY.x * TINY.y * 64, "%d threads: a 4x picture (%d bytes)" % [threads, out.size()])
		if out.size() != TINY.x * TINY.y * 64: continue
		var worst := 0
		var opaque := true
		for i in TINY.x * TINY.y * 16:
			for c in 3: worst = maxi(worst, absi(out[i * 4 + c] - expected[i * 3 + c]))
			if out[i * 4 + 3] != 255: opaque = false
		check(worst <= 2, "%d threads: matches the numpy reference (largest difference %d levels)" % [threads, worst])
		check(opaque, "%d threads: an opaque picture stays opaque" % threads)

func _check_alpha() -> void:
	# A disc cut out of a red square: alpha only on or off, black where hidden.
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var inside := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(12, 12)) < 9.0
			image.set_pixel(x, y, Color(0.8, 0.1, 0.1, 1.0) if inside else Color(0, 0, 0, 0))
	var out := _upscale(image)
	check(out.size() == 24 * 24 * 64, "cut-out picture upscaled")
	if out.size() != 24 * 24 * 64: return
	var binary := true
	var dark_edge := 0
	for i in 96 * 96:
		var a := out[i * 4 + 3]
		if a != 0 and a != 255: binary = false
		# Visible pixels keep the disc's colour: no dark fringe from the
		# black of the hidden ones.
		if a == 255 and out[i * 4] < 150: dark_edge += 1
	check(binary, "cut-out alpha stays cut out")
	check(dark_edge == 0, "no dark fringe at the cut-out's edge (%d dark pixels)" % dark_edge)
	var centre := 48 * 96 + 48
	check(out[centre * 4 + 3] == 255 and out[3] == 0, "inside visible, corner hidden")

func _check_invalid() -> void:
	var tiny := _tiny()
	var broken := ELIconUpscale.weights().slice(0, 1000)
	check((ClassDB.class_call_static(&"ELNativeAssets", &"upscale", broken, tiny.get_data(), TINY.x, TINY.y, 2) as PackedByteArray).is_empty(), "truncated weights are refused")
	check((ClassDB.class_call_static(&"ELNativeAssets", &"upscale", ELIconUpscale.weights(), tiny.get_data(), TINY.x + 1, TINY.y, 2) as PackedByteArray).is_empty(), "a size that does not match the pixels is refused")
	check((ClassDB.class_call_static(&"ELNativeAssets", &"upscale", ELIconUpscale.weights(), PackedByteArray(), 0, 0, 2) as PackedByteArray).is_empty(), "an empty picture is refused")

## A sheet's job as a preparation hands it to a worker thread.
static func _job(entry: String, bytes: PackedByteArray, image: Image, factor: int, folder: String, flags := [false]) -> Dictionary:
	return {"entry": entry, "bytes": bytes, "image": image, "factor": factor, "folder": folder, "flags": flags,
		"weights": ELIconUpscale.weights(), "threads": 4, "stats": {}}

func _check_cache() -> void:
	var folder := SCRATCH.path_join("cache")
	var image := _tiny()
	var bytes := image.get_data()
	var first := _job("interface/spells/icon_01.mmp", bytes, image, 2, folder)
	ELIconUpscale.prepare_sheet(first)
	check(first.has("file") and first.stats.has("compute_usec") and not first.stats.has("cached"), "first time: worked out (%s)" % first.get("file", "nothing"))
	check(String(first.get("file", "")).ends_with(".x2.webp"), "kept as lossless WebP named by its factor")
	var path := folder.path_join(String(first.get("file", "")))
	var webp := FileAccess.get_file_as_bytes(path)
	check(webp.size() > 16 and webp.slice(0, 4).get_string_from_ascii() == "RIFF" and webp.slice(8, 12).get_string_from_ascii() == "WEBP" and webp.slice(12, 16).get_string_from_ascii() == "VP8L", "the file is lossless WebP (VP8L)")
	var second := _job("interface/spells/icon_01.mmp", bytes, image, 2, folder)
	ELIconUpscale.prepare_sheet(second)
	check(second.get("file", "") == first.get("file", "-") and second.stats.get("cached", false) and not second.stats.has("compute_usec"), "second time: found in the user folder without the network")
	var picture := ELIconUpscale.load_sharp(path, bytes, TINY)
	check(picture != null and picture.get_size() == TINY * 2 and picture.has_mipmaps(), "the kept picture reads back at twice the size, with mipmaps")
	var reference := Image.create_from_data(TINY.x * 4, TINY.y * 4, false, Image.FORMAT_RGBA8, _upscale(image))
	reference.resize(TINY.x * 2, TINY.y * 2, Image.INTERPOLATE_LANCZOS)
	if picture != null:
		var plain := picture.duplicate()
		plain.clear_mipmaps()
		check(plain.get_data() == reference.get_data(), "lossless: the kept picture is exactly the one worked out")
	var changed := image.duplicate()
	changed.set_pixel(3, 2, Color(1, 0, 1))
	var third := _job("interface/spells/icon_01.mmp", changed.get_data(), changed, 2, folder)
	ELIconUpscale.prepare_sheet(third)
	check(third.stats.has("compute_usec") and third.get("file", "") != first.get("file", ""), "a changed sheet is worked out again")
	check(ELIconUpscale.load_sharp(path, changed.get_data(), TINY) == null, "a kept picture is refused for other bytes")
	check(ELIconUpscale.load_sharp(path, bytes, TINY + Vector2i(1, 0)) == null, "a kept picture is refused for another size")
	var other_factor := _job("interface/spells/icon_01.mmp", bytes, image, 3, folder)
	ELIconUpscale.prepare_sheet(other_factor)
	check(other_factor.has("file") and other_factor.get("file") != first.get("file") and not other_factor.stats.has("cached"), "each factor is kept apart")
	var cancelled := _job("y.mmp", bytes.slice(0, 64), image.get_region(Rect2i(0, 0, 4, 4)), 2, folder, [true])
	ELIconUpscale.prepare_sheet(cancelled)
	check(not cancelled.has("file") and not cancelled.stats.has("compute_usec"), "a cancelled job works nothing out")

## A texture given its sharp picture as it is made.
func _check_adopt() -> void:
	ELIconUpscale.forced_factor = 2
	var values := {"sharper_icons": true, "sharper_interface": true}
	ELIconUpscale.use(values)
	var upscaler := ELIconUpscale.new("check")
	var image := Image.create(50, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.7))
	image.fill_rect(Rect2i(10, 10, 20, 15), Color(0.9, 0.8, 0.1))
	var job := _job("interface/spells/icon_99.mmp", image.get_data(), image, 2, upscaler.folder())
	ELIconUpscale.prepare_sheet(job)
	var sharp := ELIconUpscale.load_sharp(upscaler.folder().path_join(String(job.get("file", ""))), image.get_data(), image.get_size())
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(10, 10, 20, 15)
	upscaler.adopt("interface/spells/icon_99.mmp", texture, image, sharp)
	var shown := upscaler.shown("interface/spells/icon_99.mmp")
	check(shown != null and shown.get_size() == Vector2i(100, 80) and texture.has_meta(ELIconUpscale.ORIGINAL), "the icon draws a picture twice its size")
	check(texture.get_size() == Vector2(50, 40), "and keeps its original size")
	check(atlas.get_size() == Vector2(20, 15), "regions in original pixels still fit")
	check(ELIconUpscale.image_of(texture) == image, "image_of gives the original image")
	var inside := shown.get_pixel(40, 34) if shown != null else Color.BLACK
	check(inside.r > 0.8 and inside.g > 0.7 and inside.b < 0.25, "the picture keeps the sheet's colours (%s)" % inside)
	values.sharper_icons = false
	ELIconUpscale.use(values)
	check(not ELIconUpscale.enabled(ELIconUpscale.KIND_ICON), "switched off: icons are not sharpened")
	upscaler.apply_all()
	check(upscaler.shown("interface/spells/icon_99.mmp") == null and not texture.has_meta(ELIconUpscale.ORIGINAL), "switched off: the original image is back")
	var other := ImageTexture.create_from_image(image)
	upscaler.adopt("interface/spells/icon_98.mmp", other, image, null)
	check(upscaler.shown("interface/spells/icon_98.mmp") == null and not other.has_meta(ELIconUpscale.ORIGINAL), "without a finished picture a texture keeps its original")
	values.sharper_icons = true
	ELIconUpscale.use(values)
	ELIconUpscale.forced_factor = 0

func _check_fallback() -> void:
	var native := ELIconUpscale.native
	ELIconUpscale.native = false
	ELIconUpscale.forced_factor = 2
	check(not ELIconUpscale.available() and not ELIconUpscale.enabled(ELIconUpscale.KIND_ICON), "without the library nothing is sharpened or offered")
	var upscaler := ELIconUpscale.new("check")
	check(upscaler.sharp_path("interface/spells/icon_97.mmp").is_empty(), "without the library no picture is looked for")
	var image := _tiny()
	var job := _job("z.mmp", image.get_data().slice(0, 40), image.get_region(Rect2i(0, 0, 3, 3)), 2, SCRATCH.path_join("cache"))
	ELIconUpscale.prepare_sheet(job)
	check(not job.has("file"), "without the library no picture is made")
	ELIconUpscale.native = native
	ELIconUpscale.forced_factor = 0

func _check_kinds() -> void:
	check(ELIconUpscale.kind_of("interface/spells/icon_01.mmp") == ELIconUpscale.KIND_ICON, "spell icon sheets are icons")
	check(ELIconUpscale.kind_of("interface/heroes/photo_01.mmp") == ELIconUpscale.KIND_ICON, "portrait sheets are icons")
	check(ELIconUpscale.kind_of("interface/black/combat_panel_1.mmp") == ELIconUpscale.KIND_INTERFACE, "panels are interface art")
	check(ELIconUpscale.kind_of("interface/combat_text_1.mmp") == ELIconUpscale.KIND_NONE, "digit sheets are left alone")
	check(ELIconUpscale.kind_of("creatures/goblin.mmp") == ELIconUpscale.KIND_TEXTURE, "figure color textures are eligible")
	check(ELIconUpscale.kind_of("heroes/alpha/hero.mmp") == ELIconUpscale.KIND_NONE, "alpha skins are excluded")
	check(ELIconUpscale.kind_of("combatscenes/stone_normal.mmp") == ELIconUpscale.KIND_NONE, "normal maps are excluded")
	check(ELIconUpscale.factor_for(Vector2(1440, 900)) == 1 and ELIconUpscale.factor_for(Vector2(1920, 1080)) == 2 and ELIconUpscale.factor_for(Vector2(3840, 2160)) == 3 and ELIconUpscale.factor_for(Vector2(5120, 2880)) == 3, "factors follow the screen (1440x900: 1, 1080p: 2, 4K and 5K: 3)")

func _check_backends() -> void:
	if not ClassDB.class_has_method(&"ELNativeAssets", &"upscale_gpu"): return
	var image := _tiny()
	image.set_pixel(0, 0, Color.TRANSPARENT)
	image.set_pixel(1, 0, Color(1.0, 1.0, 0.0, 0.32))
	var cpu := _upscale(image)
	var gpu: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"upscale_gpu", ELIconUpscale.weights(), image.get_data(), TINY.x, TINY.y)
	var ready := not gpu.is_empty()
	if "--require-gpu" in OS.get_cmdline_user_args(): check(ready, "Vulkan backend returns pixels")
	if "--require-cpu" in OS.get_cmdline_user_args(): check(not ready, "Vulkan backend is unavailable")
	if ready:
		check(gpu.size() == cpu.size(), "GPU and CPU produce the same output dimensions")
		if gpu.size() == cpu.size():
			var worst := 0
			var alpha_matches := true
			for i in gpu.size():
				if i % 4 == 3: alpha_matches = alpha_matches and gpu[i] == cpu[i]
				else: worst = maxi(worst, absi(int(gpu[i]) - int(cpu[i])))
			check(alpha_matches and worst <= 3, "GPU preserves CPU alpha and stays within %d RGB levels" % worst)
	var job := _job("interface/spells/backend_test.mmp", image.get_data(), image, 2, SCRATCH.path_join("backend"))
	job.gpu = true
	ELIconUpscale.prepare_sheet(job)
	check(job.has("file") and not String(job.get("file", "")).is_empty() and job.stats.get("gpu", false) == ready,
		"preparation saves output using the " + ("GPU" if ready else "CPU fallback"))

## Runs a preparation to its end, cancelling it once `cancel_after` sheets
## were worked out (0: never).
func _prepare(upscaler: ELIconUpscale, limit: int, cancel_after := 0) -> ELIconUpscale.Preparation:
	var run := ELIconUpscale.Preparation.new([upscaler])
	run.limit = limit
	run.start()
	var frames := 0
	while not run.poll() and frames < 20000:
		if cancel_after > 0 and not run.cancelled and run.done - run.skipped >= cancel_after: run.cancel()
		await process_frame
		frames += 1
	return run

## With the original files: preparations of real sheets, and textures made
## afterwards the way play makes them.
func _check_real() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if not saved is Dictionary:
		print("SKIP: no original games' folders on this computer")
		return
	ELIconUpscale.use({"sharper_icons": true, "sharper_interface": true})
	ELIconUpscale.forced_factor = 2
	for edition: String in ["el1", "el2"]:
		if not saved.has(edition): continue
		var profile := ELProfile.new()
		if not profile.mount(edition, String(saved[edition])): continue
		var upscaler := profile.icon_upscale
		upscaler.clear()
		var sheets := upscaler.eligible()
		var icons := 0
		for entry: String in sheets:
			if ELIconUpscale.kind_of(entry) == ELIconUpscale.KIND_ICON: icons += 1
		check(icons > 20 and sheets.size() > icons, "%s: %d sheets to prepare (%d icons, %d interface)" % [edition, sheets.size(), icons, sheets.size() - icons])
		var before := upscaler.status()
		check(int(before.done) == 0 and int(before.total) == sheets.size() and not upscaler.complete(), "%s: nothing ready before a preparation" % edition)
		var estimate := ELIconUpscale.estimate([upscaler])
		check(int(estimate.sheets) == sheets.size() and float(estimate.seconds) > 0.0 and int(estimate.bytes) > 0, "%s: estimate %.0f s on %d threads, %.0f MB at twice the size" % [edition, float(estimate.seconds), ELIconUpscale.threads(), int(estimate.bytes) / 1048576.0])
		# Cancelled after two sheets: what was worked out is kept.
		var limit := 8
		var first: ELIconUpscale.Preparation = await _prepare(upscaler, limit, 2)
		check(first.cancelled and first.total == limit and first.done >= 2 and first.done < limit, "%s: cancelled at %d of %d sheets" % [edition, first.done, first.total])
		check(FileAccess.file_exists(upscaler.manifest_path(2)), "%s: the sheets done are written down" % edition)
		upscaler.mount(profile)
		check(int(upscaler.status().done) == first.done, "%s: read back after a restart: %d sheets ready" % [edition, int(upscaler.status().done)])
		# Resumed: the rest only.
		var second: ELIconUpscale.Preparation = await _prepare(upscaler, limit)
		check(not second.cancelled and second.done == limit and second.skipped == first.done and second.computed == limit - first.done and second.failed == 0, "%s: resumed: %d kept, %d worked out, %d of %d done" % [edition, second.skipped, second.computed, second.done, second.total])
		var speed := second._pixels_done / maxf(second._work_usec / 1000000.0, 0.001)
		print("  %s: %.2f megapixels a second, %.1f s for %d sheets" % [edition, speed / 1000000.0, second.elapsed(), second.computed])
		var third: ELIconUpscale.Preparation = await _prepare(upscaler, limit)
		check(third.computed == 0 and third.skipped == limit and third.done == limit, "%s: a further run works nothing out" % edition)
		var first_sheet: String = sheets[0]
		var path := upscaler.sharp_path(first_sheet)
		var header := FileAccess.get_file_as_bytes(path).slice(0, 16)
		var truncated := FileAccess.open(path, FileAccess.WRITE)
		truncated.store_buffer(header)
		truncated.close()
		check(upscaler.status().done == limit - 1, "%s: a truncated picture is no longer counted as ready" % edition)
		var repaired := await _prepare(upscaler, limit)
		check(repaired.complete() and repaired.computed == 1 and repaired.skipped == limit - 1, "%s: preparation replaces only the truncated picture" % edition)
		if edition == "el1":
			DirAccess.remove_absolute(path)
			DirAccess.make_dir_absolute(path)
			var tasks_before := ELIconUpscale.tasks_started
			var blocked := await _prepare(upscaler, limit)
			check(blocked.failed == 1 and not blocked.complete() and ELIconUpscale.tasks_started == tasks_before + 2, "an unwritable picture gets one automatic retry and remains pending")
			DirAccess.remove_absolute(path)
			var unblocked := await _prepare(upscaler, limit)
			check(unblocked.complete() and unblocked.computed == 1, "retrying after a write failure fills in only the missing picture")
		var manifest_path := upscaler.manifest_path(2)
		var saved_manifest := FileAccess.get_file_as_bytes(manifest_path)
		ELSafeFile.test_write_limit = 1
		var unsaved := await _prepare(upscaler, limit)
		ELSafeFile.test_write_limit = -1
		check(unsaved.done == limit and unsaved.save_failed and not unsaved.complete(), "%s: a failed manifest write cannot report completion" % edition)
		check(FileAccess.get_file_as_bytes(manifest_path) == saved_manifest, "%s: a failed manifest write preserves the previous checkpoint" % edition)
		var saved_again := await _prepare(upscaler, limit)
		check(saved_again.complete() and saved_again.computed == 0, "%s: retry saves the manifest without rerunning the network" % edition)
		# The game's files changed: sheets whose bytes did not are found again.
		upscaler._identity += "|changed"
		check(bool(upscaler.status().stale) and not upscaler.complete(), "%s: changed game files make the set stale" % edition)
		var fourth: ELIconUpscale.Preparation = await _prepare(upscaler, limit)
		check(fourth.computed == 0 and fourth.done == limit and fourth.skipped == 0, "%s: after a change, pictures are found again by their bytes (%d worked out)" % [edition, fourth.computed])
		upscaler.mount(profile)
		# Play: a fresh mount, textures made as screens make them.
		var tasks := ELIconUpscale.tasks_started
		var loads := ELIconUpscale.loads
		var usec := ELIconUpscale.load_usec
		var playing := ELProfile.new()
		playing.mount(edition, String(saved[edition]))
		var shown := 0
		var sized := true
		var slowest := 0
		for entry: String in sheets.slice(0, limit):
			var at := ELIconUpscale.load_usec
			var texture := playing.texture(entry)
			slowest = maxi(slowest, ELIconUpscale.load_usec - at)
			if texture == null: continue
			var picture := playing.icon_upscale.shown(entry)
			if picture != null: shown += 1
			var original := ELIconUpscale.image_of(texture)
			if picture == null or texture.get_size() != Vector2(original.get_size()) or picture.get_size() != original.get_size() * 2: sized = false
		var count := ELIconUpscale.loads - loads
		check(shown == limit and sized, "%s: textures made afterwards draw the finished pictures at twice the size, original size kept (%d of %d)" % [edition, shown, limit])
		check(count == limit and slowest < LOAD_LIMIT_USEC, "%s: each kept picture read in %.1f ms on average, %.1f ms at most" % [edition, (ELIconUpscale.load_usec - usec) / 1000.0 / maxi(count, 1), slowest / 1000.0])
		var unprepared := playing.texture(sheets[limit])
		check(unprepared != null and playing.icon_upscale.shown(sheets[limit]) == null, "%s: a sheet not prepared yet stays original" % edition)
		for i in 30: await process_frame
		check(ELIconUpscale.tasks_started == tasks, "%s: no work started while textures loaded and frames went by" % edition)
		# Only the current factor's files are kept once a set is complete.
		var stray := upscaler.folder().path_join("interface_old.0123456789abcdef.x3.webp")
		var file := FileAccess.open(stray, FileAccess.WRITE)
		file.store_string("x")
		file.close()
		var other_manifest := upscaler.manifest_path(3)
		file = FileAccess.open(other_manifest, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
		var kept_before := DirAccess.get_files_at(upscaler.folder()).size()
		upscaler.prune()
		var left := DirAccess.get_files_at(upscaler.folder())
		check(not FileAccess.file_exists(stray) and not FileAccess.file_exists(other_manifest) and left.size() == kept_before - 2 and left.size() == limit + 1, "%s: pruning keeps only the current factor's %d pictures and manifest" % [edition, left.size() - 1])
		upscaler.clear()
		check(ELIconUpscale.disk_bytes(upscaler.folder()) == 0 and int(upscaler.status().done) == 0, "%s: Clear removes every kept picture" % edition)
		_check_quality(edition, profile)
		if edition == "el2": _check_texture_option(profile)
	ELIconUpscale.forced_factor = 0

func _check_texture_option(profile: ELProfile) -> void:
	var values := {"sharper_icons": false, "sharper_interface": false, "sharper_textures": false}
	ELIconUpscale.use(values)
	check(not ELIconUpscale.enabled(ELIconUpscale.KIND_TEXTURE), "3D textures are opt-in")
	ELIconUpscale.forced_factor = 1
	values.sharper_textures = true
	var entry := "heroes/diamanda02.mmp"
	if not profile.archives.textures.has(entry):
		print("SKIP: Diamanda texture absent")
		return
	var upscaler := profile.icon_upscale
	var base := profile.texture(entry)
	var alias := profile.texture(entry.get_basename())
	var preview := ELWikiPreview.stage_hero(profile, "Diamanda2Blue", Vector2i(640, 640))
	var creature := ELWikiPreview.stage(profile, "STMC", Vector2i(640, 640))
	var arena := ELArena.new()
	root.add_child(arena)
	arena.build(profile, "Green.001")
	var creature_entry := "creatures/blackdestroyerbc01.mmp"
	var terrain_entry := "combatscenes/greengr00.mmp"
	var creature_skin := profile.texture(creature_entry.get_basename())
	var terrain := profile.texture(terrain_entry.get_basename())
	var source := ELTexture.readable(ELIconUpscale.image_of(base))
	check(upscaler.eligible().has(entry) and not upscaler.complete() and ELIconUpscale.cache_factor() == 2,
		"opaque 3D texture is eligible at layout resolution")
	for key: String in [entry, creature_entry, terrain_entry]:
		var image := ELTexture.readable(ELIconUpscale.image_of(profile.texture(key)))
		var job := _job(key, profile.read("textures", key), image, 2, upscaler.folder())
		job.gpu = ClassDB.class_has_method(&"ELNativeAssets", &"upscale_gpu")
		ELIconUpscale.prepare_sheet(job)
		if job.has("file"): upscaler.manifest.sheets[key] = [job.digest, job.file]
	upscaler.write_manifest()
	upscaler.mount(profile)
	var revision := ELIconUpscale.texture_revision
	upscaler.apply_all()
	var sharp := upscaler.shown(entry)
	check(sharp != null and sharp.get_size() == source.get_size() * 2 and sharp.has_mipmaps()
		and base.get_size() == Vector2(source.get_size()) and alias.has_meta(ELIconUpscale.ORIGINAL),
		"cached 2× texture keeps original dimensions and updates both aliases")
	check(preview != null and _material_uses_sharp(preview.get_node("Model"), alias), "the wiki hero material uses the prepared skin")
	check(creature != null and _material_uses_sharp(creature.get_node("Model"), creature_skin), "creature materials use the prepared skin")
	check(arena._ground != null and _material_uses_sharp(arena._ground, terrain), "the arena floor shader uses the prepared terrain texture")
	check(ELIconUpscale.texture_revision > revision, "applying prepared 3D textures invalidates the ray tracer's texture snapshot")
	if preview != null: preview.queue_free()
	if creature != null: creature.queue_free()
	arena.queue_free()
	values.sharper_textures = false
	upscaler.apply_all()
	check(not base.has_meta(ELIconUpscale.ORIGINAL) and not alias.has_meta(ELIconUpscale.ORIGINAL),
		"disabling 3D textures restores both aliases")
	var alpha := _tiny()
	alpha.set_pixel(0, 0, Color.TRANSPARENT)
	var cutout := _job("combatscenes/cutout.mmp", alpha.get_data(), alpha, 2, upscaler.folder())
	ELIconUpscale.prepare_sheet(cutout)
	check(cutout.has("file") and cutout.file.is_empty() and not cutout.stats.has("compute_usec"), "3D cutouts keep their original image")
	upscaler.clear()

func _material_uses_sharp(model: ELModel, texture: Texture2D) -> bool:
	if texture == null or not texture.has_meta(ELIconUpscale.ORIGINAL): return false
	if DisplayServer.get_name() != "headless" and texture.get_image().get_size() != Vector2i(texture.get_size()) * 2: return false
	for part: MeshInstance3D in model.parts.values():
		var material := part.material_override
		if material is StandardMaterial3D and material.albedo_texture == texture: return true
		if material is ShaderMaterial and material.get_shader_parameter("albedo_texture") == texture: return true
	return false

## A real sheet of each kind, upscaled and reduced back, stays close.
func _check_quality(edition: String, profile: ELProfile) -> void:
	for name: String in ["Interface/Spells/icon_01", "Interface/heroes/photo_01"]:
		var texture := profile.texture(name)
		if texture == null: continue
		var image := ELTexture.readable(ELIconUpscale.image_of(texture)).duplicate()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		var started := Time.get_ticks_usec()
		var out := _upscale(image, ELIconUpscale.threads())
		var usec := Time.get_ticks_usec() - started
		check(out.size() == image.get_width() * image.get_height() * 64, "%s %s upscaled in %.0f ms" % [edition, name, usec / 1000.0])
		if out.is_empty(): continue
		var big := Image.create_from_data(image.get_width() * 4, image.get_height() * 4, false, Image.FORMAT_RGBA8, out)
		big.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_BILINEAR)
		var total := 0.0
		var data: PackedByteArray = big.get_data()
		var source: PackedByteArray = image.get_data()
		for i in range(0, data.size(), 4):
			for c in 3: total += absf(data[i + c] - source[i + c])
		var mean := total / (data.size() / 4 * 3)
		check(mean < 12.0, "%s %s reduced back stays close to the original (mean difference %.1f levels)" % [edition, name, mean])
