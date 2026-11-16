class_name ELIconUpscale
extends RefCounted
## Sharper icons and interface art, prepared on the player's own machine.
##
## The original games' icons (spells, heroes' portraits, skills, global
## spells, artefacts, states, buildings) and interface art (screens, panels,
## frames, buttons, the battle and map panels) are drawn at a few hundred
## pixels a sheet. Each sheet can be enlarged four times by a small
## super-resolution network (Real-ESRGAN realesr-general-x4v3, its weights
## in native/models/, run by ELNativeAssets.upscale), reduced (Lanczos) to
## the factor the screen needs (its size against the 1440 x 900 layout,
## rounded up, at most 3) and kept in the user folder as lossless WebP
## (user://upscaled/<edition>/), with a manifest of the sheets done. Nothing
## upscaled is ever shipped.
##
## The work is an explicit step, never done during play: the "Preparing
## sharper art" screen (ELSharperArtScreen) runs Preparation, which the
## player starts from a prompt (first start, a switch turned on, the cache
## missing or stale for the screen) or from Options; it shows its progress,
## can be cancelled (what is done is kept) and resumed.
##
## During play only finished pictures are used, when a sheet's texture is
## first made (ELProfile, on the loading screens' worker threads where they
## prefetch): the texture gets the sharp picture with a size override of
## the original size, so every region, margin, slice and layout in original
## pixels keeps working and the art is drawn at the same size on screen,
## only with more pixels. A sheet without a finished picture stays original
## until the next preparation. Code that reads a sheet's pixels uses
## image_of(), which gives the original image. At 1440 x 900 or smaller
## nothing changes on screen.
##
## Settings "sharper_icons" and "sharper_interface" (ELSettings) switch each
## kind. Without the native library (the browser) nothing is offered.
##
## Each edition's content (ELProfile.icon_upscale) has its own.

## Bump when the network, its weights or the way pictures are made change:
## kept pictures are then prepared again.
const VERSION := 2
const MODEL := "res://native/models/realesr-general-x4v3.bin"
const FOLDER := "user://upscaled"
## The meta of an upscaled texture that holds its original image.
const ORIGINAL := &"el_original_image"
const KIND_NONE := 0
const KIND_ICON := 1
const KIND_INTERFACE := 2
## Sheets of icons (archive entries under these folders, or these files).
const ICON_FOLDERS := ["interface/spells/", "interface/heroes/", "interface/skills/", "interface/globalspells/",
	"interface/artifacts/", "interface/affects/", "interface/buildings/"]
const ICON_FILES := ["interface/combatsymbols.mmp", "interface/hero_states.mmp", "interface/symbols.mmp", "interface/world_symbols_map.mmp"]
## Never upscaled: digits and tiny glyphs, plain fills, light maps and the
## selection rings drawn in the 3D scenes.
const SKIPPED := ["interface/combat_text", "interface/big_states", "interface/lightmap", "interface/solid_", "interface/test",
	"interface/selection"]
## The layout every factor is measured against (project viewport size).
const LAYOUT := Vector2(1440, 900)
## The largest factor kept: three times is as sharp as a 4K screen shows the
## layout (2.4 times), and a fourth costs nearly twice the memory for what
## only a 5K screen would show.
const MAX_FACTOR := 3
## Seconds a megapixel of sheets takes on one thread, for the estimate
## before anything was measured (a desktop processor with AVX2; ARM
## handhelds about twice as long), and the time to write a sheet.
const SECONDS_PER_MEGAPIXEL := 110.0
const SECONDS_PER_MEGAPIXEL_ARM := 240.0
const SECONDS_PER_SHEET := 0.15
## Bytes a kept picture takes per pixel (lossless WebP of the games' art).
const BYTES_PER_PIXEL := 1.0

static var native := ClassDB.class_exists(&"ELNativeAssets") and ClassDB.class_has_method(&"ELNativeAssets", &"upscale")
## The settings (ELSettings.values) the switches are read from.
static var preferences: Dictionary = {}
static var _all: Array[WeakRef] = []
static var _weights := PackedByteArray()
static var _weights_read := false
## Set by checks: the factor used instead of the screen's and the window's.
static var forced_factor := 0
## Set by checks: where pictures are kept instead of FOLDER.
static var forced_folder := ""
## Worker tasks started by preparations, ever (checks: none during play),
## and sharp pictures loaded for textures with their total time.
static var tasks_started := 0
static var loads := 0
static var load_usec := 0

var edition := ""
## The kept pictures: the manifest of the screen's factor.
var manifest := {}
## Textures made from sheets (by archive entry): {texture (WeakRef), image
## (the original), kind, sharp (the picture shown, if any)}.
var _known := {}
## Where the edition's textures come from: [archive, entries] and their
## files' sizes and dates (a manifest made from other files is stale).
var _archive: ELArchive
var _identity := ""

func _init(edition_id: String) -> void:
	edition = edition_id
	_all.append(weakref(self))

## Whether this build can sharpen anything: the native library, the weights,
## and not the browser.
static func available() -> bool:
	return native and not OS.has_feature("web") and OS.get_processor_count() >= 2

## Whether the device has the cores to prepare it in a few minutes (the
## switches' default; fewer cores leave them for the player to turn on).
static func recommended() -> bool:
	return available() and OS.get_processor_count() >= 4

## Uses `values` (ELSettings.values) for the switches.
static func use(values: Dictionary) -> void:
	preferences = values

static func enabled(kind: int) -> bool:
	if not available() or kind == KIND_NONE: return false
	if kind == KIND_ICON: return bool(preferences.get("sharper_icons", recommended()))
	return bool(preferences.get("sharper_interface", recommended()))

## Which kind an archive entry (lower case, as ELArchive.key gives it) is.
static func kind_of(entry: String) -> int:
	if not entry.begins_with("interface/") or not entry.ends_with(".mmp"): return KIND_NONE
	for prefix: String in SKIPPED:
		if entry.begins_with(prefix): return KIND_NONE
	if entry in ICON_FILES: return KIND_ICON
	for folder: String in ICON_FOLDERS:
		if entry.begins_with(folder): return KIND_ICON
	return KIND_INTERFACE

## How many times its original size a picture needs at `size` (window or
## screen pixels): 1 at the layout's own size or smaller, at most MAX_FACTOR.
static func factor_for(size: Vector2) -> int:
	if forced_factor > 0: return forced_factor
	if size.x <= 0.0 or size.y <= 0.0: return 1
	var scale := minf(size.x / LAYOUT.x, size.y / LAYOUT.y)
	return clampi(ceili(scale - 0.05), 1, MAX_FACTOR)

## The factor of the window now: at 1 the originals are drawn.
static func window_factor() -> int:
	if DisplayServer.get_name() == "headless": return factor_for(Vector2.ZERO)
	return factor_for(Vector2(DisplayServer.window_get_size()))

## The factor pictures are prepared at: the screen's, the largest the
## window can get.
static func target_factor() -> int:
	if DisplayServer.get_name() == "headless": return factor_for(Vector2.ZERO)
	return factor_for(Vector2(DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())))

## The image a texture was made from: the original even when the texture
## draws a sharp picture. For code that reads a sheet's pixels.
static func image_of(texture: Texture2D) -> Image:
	if texture == null: return null
	if texture.has_meta(ORIGINAL): return texture.get_meta(ORIGINAL)
	return texture.get_image()

## The network's weights (read once).
static func weights() -> PackedByteArray:
	if not _weights_read:
		_weights_read = true
		if FileAccess.file_exists(MODEL): _weights = FileAccess.get_file_as_bytes(MODEL)
	return _weights

## Threads a preparation runs the network on: all cores but one (it is the
## task in front of the player), at least one.
static func threads() -> int:
	return clampi(OS.get_processor_count() - 1, 1, 64)

static func root_folder() -> String:
	return forced_folder if not forced_folder.is_empty() else FOLDER

func folder() -> String:
	return root_folder().path_join(edition)

func manifest_path(factor: int) -> String:
	return folder().path_join("manifest.x%d.json" % factor)

## Reads the manifest of the target factor (after the content is mounted).
func mount(profile: ELProfile) -> void:
	_archive = profile.archives.get("textures")
	var parts := PackedStringArray()
	for path: String in profile.mounted_layers.get("textures", []):
		var file := profile.file(path)
		parts.append("%s:%d:%d" % [path, FileAccess.get_size(file) if not file.is_empty() else 0, FileAccess.get_modified_time(file) if not file.is_empty() else 0])
	_identity = "|".join(parts)
	manifest = read_manifest(target_factor())

func read_manifest(factor: int) -> Dictionary:
	var empty := {"version": VERSION, "factor": factor, "identity": _identity, "sheets": {}}
	if factor < 2 or not FileAccess.file_exists(manifest_path(factor)): return empty
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path(factor)))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION or int(parsed.get("factor", 0)) != factor or not parsed.get("sheets") is Dictionary:
		return empty
	return parsed

func write_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(folder())
	var part := "%s.%08x.part" % [manifest_path(int(manifest.factor)), randi()]
	var file := FileAccess.open(part, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(manifest))
	file.close()
	DirAccess.rename_absolute(part, manifest_path(int(manifest.factor)))

## The sheets of the edition the switches ask for: archive entries, sorted
## (icons first).
func eligible() -> Array[String]:
	var result: Array[String] = []
	if _archive == null: return result
	var names: Array = _archive.entries.keys()
	names.sort()
	for kind: int in [KIND_ICON, KIND_INTERFACE]:
		if not enabled(kind): continue
		for entry: String in names:
			if kind_of(entry) == kind: result.append(entry)
	return result

## How far the kept pictures are: {done, total, stale (the game's files
## changed since), factor, bytes (on disk, every factor)}.
func status() -> Dictionary:
	var sheets: Dictionary = manifest.get("sheets", {})
	var done := 0
	var wanted := eligible()
	for entry: String in wanted:
		if sheets.has(entry): done += 1
	return {"done": done, "total": wanted.size(), "stale": String(manifest.get("identity", "")) != _identity and not sheets.is_empty(),
		"factor": target_factor(), "bytes": disk_bytes(folder())}

## Whether the kept pictures cover every sheet the switches ask for.
func complete() -> bool:
	var state := status()
	return int(state.factor) < 2 or (int(state.done) >= int(state.total) and not state.stale)

static func disk_bytes(path: String) -> int:
	var total := 0
	if not DirAccess.dir_exists_absolute(path): return 0
	for file: String in DirAccess.get_files_at(path): total += FileAccess.get_size(path.path_join(file))
	return total

## Removes every kept picture and manifest of the edition.
func clear() -> void:
	var path := folder()
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
	manifest = read_manifest(target_factor())
	restore_all()

## Removes kept files the current manifest does not name (other factors,
## replaced sheets): after a finished preparation.
func prune() -> void:
	var keep := {manifest_path(int(manifest.factor)).get_file(): true}
	for entry: String in manifest.sheets: keep[String(manifest.sheets[entry][1])] = true
	var path := folder()
	if not DirAccess.dir_exists_absolute(path): return
	for file: String in DirAccess.get_files_at(path):
		if not keep.has(file): DirAccess.remove_absolute(path.path_join(file))

## Where a sheet's sharp picture is, for a texture about to be made, or ""
## (the kind switched off, a small window, no finished picture). Main thread.
func sharp_path(entry: String) -> String:
	var kind := kind_of(entry)
	if not enabled(kind) or window_factor() < 2: return ""
	var found: Variant = manifest.get("sheets", {}).get(entry)
	if not found is Array or found.size() < 2 or String(found[1]).is_empty(): return ""
	return folder().path_join(String(found[1]))

## The digest a sheet's picture is kept under (its stored bytes).
static func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(var_to_bytes([VERSION, bytes.size()]))
	hashing.update(bytes)
	return hashing.finish().hex_encode().substr(0, 16)

## Reads a kept picture for a sheet: its stored bytes must match the
## digest it was kept under and its size the original's times `factor`.
## Null otherwise. Touches nothing shared: worker threads may call it.
static func load_sharp(path: String, bytes: PackedByteArray, original: Vector2i) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path): return null
	var name := path.get_file()
	var parts := name.split(".")
	if parts.size() < 4 or parts[parts.size() - 3] != digest(bytes): return null
	var started := Time.get_ticks_usec()
	var picture := Image.load_from_file(path)
	if picture == null or picture.get_width() % original.x != 0 or picture.get_width() / original.x < 2 or picture.get_size() != original * (picture.get_width() / original.x): return null
	picture.convert(Image.FORMAT_RGBA8)
	picture.generate_mipmaps()
	loads += 1
	load_usec += Time.get_ticks_usec() - started
	return picture

## A texture just made from an archive entry (ELProfile._texture_store),
## with its sharp picture when one was loaded (`sharp`, else null).
func adopt(entry: String, texture: ImageTexture, image: Image, sharp: Image) -> void:
	var kind := kind_of(entry)
	if kind == KIND_NONE or texture == null or image == null: return
	_known[entry] = {"texture": weakref(texture), "image": image, "kind": kind}
	if sharp != null: _show(entry, sharp)

func _show(entry: String, sharp: Image) -> void:
	var known: Dictionary = _known[entry]
	var texture: ImageTexture = known.texture.get_ref()
	if texture == null: return
	var image: Image = known.image
	texture.set_image(sharp)
	texture.set_size_override(image.get_size())
	texture.set_meta(ORIGINAL, image)
	known.sharp = sharp

## The sharp picture a texture shows, or null (checks).
func shown(entry: String) -> Image:
	return _known.get(entry, {}).get(&"sharp")

## Gives every texture made so far its original image back.
func restore_all() -> void:
	for entry: String in _known: _restore(entry)

func _restore(entry: String) -> void:
	var known: Dictionary = _known[entry]
	var texture: ImageTexture = known.texture.get_ref()
	if texture == null or not known.has(&"sharp"): return
	texture.set_image(known.image)
	texture.remove_meta(ORIGINAL)
	known.erase(&"sharp")

## Brings textures made so far in line with the switches and the kept
## pictures: after a preparation or a switch was changed, while a screen
## of the player's choosing is in front (reads pictures on this thread).
func apply_all() -> void:
	for entry: String in _known:
		var known: Dictionary = _known[entry]
		var texture: ImageTexture = known.texture.get_ref()
		if texture == null: continue
		var path := sharp_path(entry)
		if path.is_empty():
			_restore(entry)
			continue
		if known.has(&"sharp"): continue
		var bytes := _archive.read(entry) if _archive != null else PackedByteArray()
		var sharp := load_sharp(path, bytes, Vector2i(known.image.get_size()))
		if sharp != null: _show(entry, sharp)

## Every live edition's upscaler.
static func all() -> Array[ELIconUpscale]:
	var result: Array[ELIconUpscale] = []
	for ref: WeakRef in _all.duplicate():
		var upscaler: ELIconUpscale = ref.get_ref()
		if upscaler == null: _all.erase(ref)
		else: result.append(upscaler)
	return result

## The work a preparation of `upscalers` would do: {sheets (left to
## work out), pixels, seconds (estimate), bytes (estimated disk use of the
## finished set)}.
static func estimate(upscalers: Array) -> Dictionary:
	var sheets := 0
	var pixels := 0
	var total_pixels := 0
	for upscaler: ELIconUpscale in upscalers:
		var kept: Dictionary = upscaler.manifest.get("sheets", {})
		for entry: String in upscaler.eligible():
			var location := upscaler._archive.locate(entry)
			# From the stored size (16- or 32-bit pixels, mipmaps), or a 256 x
			# 256 sheet when it is not known.
			var size := 65536
			if location.size() == 3 and int(location[2]) > 76: size = maxi(1, (int(location[2]) - 76) / 3)
			total_pixels += size
			if kept.has(entry): continue
			sheets += 1
			pixels += size
	var per_megapixel := SECONDS_PER_MEGAPIXEL_ARM if OS.has_feature("arm64") or OS.has_feature("arm32") else SECONDS_PER_MEGAPIXEL
	var factor := target_factor()
	return {"sheets": sheets, "pixels": pixels, "seconds": pixels / 1000000.0 * per_megapixel / threads() + sheets * SECONDS_PER_SHEET,
		"bytes": int(total_pixels * factor * factor * BYTES_PER_PIXEL)}

## A worker thread's part of a preparation: a sheet's picture at `factor`,
## kept as lossless WebP under the digest of its stored bytes, or read back
## when a picture with that digest is already kept. Fills job.file (the
## kept file's name) and job.stats.
static func prepare_sheet(job: Dictionary) -> void:
	var flags: Array = job.flags
	if flags[0]: return
	var stats: Dictionary = job.stats
	var bytes: PackedByteArray = job.bytes if job.has("bytes") else ELMetalMasks.read_location(job.location)
	if bytes.is_empty(): return
	var key := digest(bytes)
	var factor := clampi(int(job.factor), 2, 4)
	var name := "%s.%s.x%d.webp" % [String(job.entry).get_basename().validate_filename(), key, factor]
	var path := String(job.folder).path_join(name)
	job.digest = key
	if FileAccess.file_exists(path):
		job.file = name
		stats.cached = true
		return
	var image: Image = job.image if job.has("image") else ELTexture.decode(bytes)
	# Not a picture the game draws (a sheet of another format), or larger
	# than the network takes: kept as it is, and counted as done.
	if image == null or image.get_width() > 4096 or image.get_height() > 4096 or image.get_width() * image.get_height() > 4194304:
		job.file = ""
		return
	image = image.duplicate()
	if image.is_compressed() and image.decompress() != OK: return
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	if flags[0] or not native: return
	var model: PackedByteArray = job.weights
	if model.is_empty(): return
	var started := Time.get_ticks_usec()
	var out: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"upscale", model, image.get_data(), image.get_width(), image.get_height(), int(job.threads))
	stats.compute_usec = Time.get_ticks_usec() - started
	stats.pixels = image.get_width() * image.get_height()
	if out.size() != image.get_width() * image.get_height() * 64: return
	var picture := Image.create_from_data(image.get_width() * 4, image.get_height() * 4, false, Image.FORMAT_RGBA8, out)
	if factor < 4: picture.resize(image.get_width() * factor, image.get_height() * factor, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(job.folder)
	# Written aside first: a run that ends half way keeps no broken picture,
	# and two games running at once never write the same file.
	var part := "%s.%08x.part" % [path, randi()]
	if picture.save_webp(part, false) != OK: return
	if DirAccess.rename_absolute(part, path) != OK:
		DirAccess.remove_absolute(part)
		if not FileAccess.file_exists(path): return
	job.file = name


## One preparation run over some editions' upscalers: start(), then poll()
## once a frame until it returns true. cancel() stops it after the sheets
## being worked out (what is done is kept; a later run resumes).
class Preparation:
	extends RefCounted
	## Sheets worked out at once, each on its share of all cores but one: a
	## small sheet keeps few threads busy, and one job's picture is written
	## while the other's is worked out.
	const JOBS := 2
	## Manifests are written after this many finished sheets (and at the end).
	const SAVE_EVERY := 16

	var upscalers: Array = []
	## Every sheet the switches ask for: [upscaler, entry]; the next to start.
	var _plan: Array = []
	var _next := 0
	var _running := {}
	var _flags := [false]
	var _unsaved := 0
	var total := 0
	var done := 0
	## Sheets kept already when the run began (not counted in its speed).
	var skipped := 0
	var computed := 0
	var failed := 0
	var started_usec := 0
	var finished := false
	var cancelled := false
	## Set by checks: at most this many sheets of each edition (0: all).
	var limit := 0
	## Pixels worked out and the time since the first was started, for the
	## remaining time.
	var _pixels_done := 0
	var _pixels_left := 0
	var _work_usec := 0

	func _init(of: Array) -> void:
		upscalers = of

	func start() -> void:
		started_usec = Time.get_ticks_usec()
		for upscaler: ELIconUpscale in upscalers:
			var factor := ELIconUpscale.target_factor()
			if factor < 2: continue
			# A new factor, or the game's files changed: a fresh manifest, and
			# sheets whose stored bytes did not change keep their pictures.
			if int(upscaler.manifest.get("factor", 0)) != factor or String(upscaler.manifest.get("identity", "")) != upscaler._identity:
				var stored := upscaler.read_manifest(factor)
				# Kept pictures are named by their sheets' bytes: those still on
				# disk are found again by prepare_sheet without the network.
				var kept: Dictionary = stored.sheets if String(stored.get("identity", "")) == upscaler._identity else {}
				upscaler.manifest = {"version": VERSION, "factor": factor, "identity": upscaler._identity, "sheets": kept}
			var sheets: Dictionary = upscaler.manifest.sheets
			var wanted := upscaler.eligible()
			if limit > 0: wanted = wanted.slice(0, limit)
			for entry: String in wanted:
				total += 1
				if sheets.has(entry):
					done += 1
					skipped += 1
					continue
				var location := upscaler._archive.locate(entry)
				if location.size() < 3 or int(location[2]) <= 0:
					# An in-memory archive (an imported data pack): read here.
					_plan.append([upscaler, entry, upscaler._archive.read(entry)])
				else: _plan.append([upscaler, entry, location])
				_pixels_left += maxi(1, (int(location[2]) - 76) / 3) if location.size() == 3 else 65536

	func cancel() -> void:
		cancelled = true
		_flags[0] = true

	## Starts and finishes sheets; true once the run is over (finished or
	## cancelled and its running sheets done).
	func poll() -> bool:
		if finished: return true
		for task: int in _running.keys():
			if not WorkerThreadPool.is_task_completed(task): continue
			WorkerThreadPool.wait_for_task_completion(task)
			_finish(_running[task])
			_running.erase(task)
		while not cancelled and _running.size() < JOBS and _next < _plan.size():
			var item: Array = _plan[_next]
			_next += 1
			var upscaler: ELIconUpscale = item[0]
			var job := {"entry": item[1], "flags": _flags, "factor": int(upscaler.manifest.factor), "folder": upscaler.folder(),
				"weights": ELIconUpscale.weights(), "threads": ceili(ELIconUpscale.threads() / float(JOBS)), "stats": {}, "upscaler": upscaler, "started": Time.get_ticks_usec()}
			if item[2] is PackedByteArray: job.bytes = item[2]
			else: job.location = item[2]
			ELIconUpscale.tasks_started += 1
			_running[WorkerThreadPool.add_task(ELIconUpscale.prepare_sheet.bind(job), false, "Preparing sharper art")] = job
		if _running.is_empty() and (cancelled or _next >= _plan.size()):
			for upscaler: ELIconUpscale in upscalers:
				if int(upscaler.manifest.get("factor", 0)) < 2: continue
				upscaler.write_manifest()
				# A finished set replaces every other factor's pictures.
				if not cancelled and upscaler.complete(): upscaler.prune()
			finished = true
		return finished

	func _finish(job: Dictionary) -> void:
		var upscaler: ELIconUpscale = job.upscaler
		var stats: Dictionary = job.stats
		if job.has("file"):
			upscaler.manifest.sheets[job.entry] = [job.digest, job.file]
			done += 1
			if stats.has("compute_usec"): computed += 1
		elif not _flags[0]: failed += 1
		if stats.has("pixels"):
			_pixels_done += int(stats.pixels)
			_work_usec = Time.get_ticks_usec() - started_usec
		_unsaved += 1
		if _unsaved >= SAVE_EVERY:
			_unsaved = 0
			upscaler.write_manifest()

	## Seconds the run has taken.
	func elapsed() -> float:
		return (Time.get_ticks_usec() - started_usec) / 1000000.0

	## Seconds still to go: measured speed once sheets were worked out, the
	## estimate before.
	func remaining() -> float:
		var left := maxi(_pixels_left - _pixels_done, 0)
		if _pixels_done > 0 and _work_usec > 0: return left * (_work_usec / 1000000.0) / _pixels_done
		var per_megapixel := ELIconUpscale.SECONDS_PER_MEGAPIXEL_ARM if OS.has_feature("arm64") else ELIconUpscale.SECONDS_PER_MEGAPIXEL
		return left / 1000000.0 * per_megapixel / ELIconUpscale.threads()
