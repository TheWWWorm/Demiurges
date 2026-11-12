class_name ELMetalMasks
extends RefCounted
## Where figures' skins are painted as metal (ELFigure.metal_material), one
## mask per figure and skin. Masks are worked out on worker threads, never on
## the main thread during play: every armoured figure of the edition right
## after its content is mounted, and any other figure as soon as it is first
## built (it is drawn without metal until then). Finished masks are kept in
## the user folder, keyed by the figure's and skins' bytes, so later starts
## only read them back.
##
## Each edition's content (ELProfile.metal_masks) has its own.

## Emitted on the main thread when a figure's masks are ready (`key`).
signal finished(key: String)

## Bump when the classifier changes: masks kept on disk are then rebuilt.
const VERSION := 4
const SIDE := 128
const FOLDER := "user://metal_masks"
const MAGIC := 0x4d4d4c45
## Marks of a skin's texels: under a figure part, under a named metal one,
## under a part that is metal all over (machine wings).
const MARK_PART := 1
const MARK_METAL := 2
const MARK_SOLID := 3
## Masks worked out at once (the rest of the pool stays free for loading).
const WORKERS := 2
## Requests located per frame while the precompute list is read.
const LOCATES_PER_FRAME := 8
## Table rows listed per frame.
const ROWS_PER_FRAME := 64
## Chroma bins across the colour wheel (both axes) and value bins of the
## colour statistics a figure's metal is learnt from.
const CHROMA_BINS := 13
const VALUE_BINS := 5

static var native := ClassDB.class_exists(&"ELNativeAssets")
## Main thread time spent on masks (looking them up, starting and finishing
## jobs, swapping materials), its worst single frame, and how many masks were
## classified on the main thread (none, where threads exist).
static var main_thread_usec := 0
static var main_thread_worst_usec := 0
static var main_thread_classified := 0

var edition := ""
## Where masks are kept (one folder per edition under it).
var folder := FOLDER
var _jobs := {}
var _queue: Array[String] = []
var _requests: Array = []
## Tables being listed for precompute, and the skins listed.
var _tables: Array = []
var _listed := {}
var _running := {}
var _ready := {}
## Shared with the jobs: [cancelled].
var _flags := [false]
var _pumping := false
var _batch := {}
static var _frame := -1
static var _frame_usec := 0
## Metal materials kept so their shaders stay compiled (warm_shaders).
static var _warm: Array[Material] = []

func _init(edition_id: String) -> void:
	edition = edition_id

func _notification(what: int) -> void:
	# No jobs outlive their queue (they hold its shared flags, not the queue).
	if what == NOTIFICATION_PREDELETE:
		_flags[0] = true
		for task: int in _running.values(): WorkerThreadPool.wait_for_task_completion(task)
		for table: Dictionary in _tables:
			if table.task >= 0: WorkerThreadPool.wait_for_task_completion(table.task)

## The key of a figure in its skins (as ELModel.build names them).
static func key(template: String, skin: String, second_skin: String) -> String:
	var main := ELArchive.key(skin)
	var second := ELArchive.key(second_skin)
	return "%s|%s|%s" % [ELArchive.key(template), main, "" if second == main else second]

## The masks of a figure in these skins, {"main": Texture2D, "second":
## Texture2D} (a skin without metal has none), or null while they are being
## worked out: `finished` is emitted with the key once they are ready.
func lookup(profile: ELProfile, template: String, skin: String, second_skin: String) -> Variant:
	var started := Time.get_ticks_usec()
	var at := key(template, skin, second_skin)
	var found: Variant = _ready.get(at)
	if found == null:
		_request(profile, template, skin, second_skin, true)
		if _ready.has(at): found = _ready[at]
	spent(Time.get_ticks_usec() - started)
	return found

## Queues every hero, shape and creature skin of the edition (call after
## mounting its content).
func precompute(profile: ELProfile) -> void:
	# Without threads the work would land on the main thread: such builds work
	# masks out when a figure is first built, and keep them.
	if OS.has_feature("web") and not OS.has_feature("threads"): return
	warm_shaders()
	var started := Time.get_ticks_usec()
	_batch = {"started": started, "skins": 0, "cached": 0, "computed": 0, "compute_usec": 0, "prepare_usec": 0, "done": false,
		"listing_usec": 0, "pump_usec": 0, "pump_worst_usec": 0, "frames": 0}
	# Tables not read yet are parsed on worker threads too.
	for spec: Array in [["HeroTemplates", "Heroes/", "Texture2"], ["Shapes", "Heroes/", "Texture2"], ["CombatCreatures", "Creatures/", "SecTexture"]]:
		var table := {"spec": spec, "profile": profile, "task": -1}
		if profile.tables.has(spec[0]): table.rows = profile.tables[spec[0]]
		else:
			table.bytes = profile.read("regs", spec[0] + ".reg")
			table.task = WorkerThreadPool.add_task(ELMetalMasks._parse_table.bind(table), false, "Metal mask list")
		_tables.append(table)
	_batch.listing_usec = Time.get_ticks_usec() - started
	spent(_batch.listing_usec)
	_start_pump()

static func _parse_table(table: Dictionary) -> void:
	table.rows = ELRegistry.parse(table.bytes)

## Queues a parsed table's skins, a few rows each frame.
func _list(table: Dictionary) -> bool:
	var spec: Array = table.spec
	var profile: ELProfile = table.profile
	if not table.has("left"):
		if not profile.tables.has(spec[0]): profile.tables[spec[0]] = table.rows
		table.left = Dictionary(table.rows).values()
	var left: Array = table.left
	for i in mini(ROWS_PER_FRAME, left.size()):
		var row: Variant = left.pop_back()
		if not row is Dictionary or String(row.get("Model", "")).is_empty() or String(row.get("Texture", "")).is_empty(): continue
		var skin: String = spec[1] + String(row.Texture).replace("\\", "/")
		var second := String(spec[1]) + String(row[spec[2]]).replace("\\", "/") if row.has(spec[2]) else ""
		var at := key(row.Model, skin, second)
		if _listed.has(at): continue
		_listed[at] = true
		_requests.append([String(row.Model), skin, second, profile])
	return left.is_empty()

## Compiles the metal materials' shaders now, while content loads: the first
## figure to turn to metal would otherwise compile them as it is drawn.
static func warm_shaders() -> void:
	if not _warm.is_empty(): return
	var started := Time.get_ticks_usec()
	var blank := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_L8))
	# ELModel.build's two skins: cut-out and soft (Alpha32) alpha.
	for transparency: BaseMaterial3D.Transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
		var base := ELFigure.material(blank)
		base.transparency = transparency
		var metal := ELFigure.metal_material(base, blank)
		metal.get_rid()
		_warm.append(metal)
	spent(Time.get_ticks_usec() - started)
	print_verbose("Metal masks: shaders compiled in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))

## Stops the jobs (waiting for the ones running) and forgets the queue.
func stop() -> void:
	_flags[0] = true
	for at: String in _running: WorkerThreadPool.wait_for_task_completion(_running[at])
	for table: Dictionary in _tables:
		if table.task >= 0: WorkerThreadPool.wait_for_task_completion(table.task)
	_tables.clear()
	_running.clear()
	_queue.clear()
	_requests.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if _pumping and tree != null and tree.process_frame.is_connected(_pump): tree.process_frame.disconnect(_pump)
	_pumping = false

func _request(profile: ELProfile, template: String, skin: String, second_skin: String, urgent: bool) -> void:
	var at := key(template, skin, second_skin)
	if _ready.has(at): return
	if _jobs.has(at):
		if urgent and at in _queue:
			_queue.erase(at)
			_queue.push_front(at)
		return
	var job := job_for(profile, template, skin, second_skin)
	_jobs[at] = job
	if job.mod.is_empty() or job.main.is_empty():
		_ready[at] = {}
		return
	if urgent: _queue.push_front(at)
	else: _queue.append(at)
	_start_pump()

## A figure's job: where its package and skins are stored, where its masks
## are kept. Its worker fills "result" and "stats".
func job_for(profile: ELProfile, template: String, skin: String, second_skin: String) -> Dictionary:
	var at := key(template, skin, second_skin)
	var job := {"key": at, "template": ELArchive.key(template), "flags": _flags, "result": {}, "stats": {}}
	job.mod = profile.locate_figure(job.template + ".mod")
	job.main = profile.texture_location(skin)
	var second := ELArchive.key(second_skin)
	job.has_second = not second.is_empty() and second != ELArchive.key(skin)
	job.second = profile.texture_location(second_skin) if job.has_second else {}
	job.path = "%s/%s/%s.%s.mask" % [folder, edition, job.template.validate_filename(), at.md5_text().substr(0, 12)]
	return job

func _start_pump() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _pumping or tree == null: return
	_pumping = true
	_flags[0] = false
	tree.process_frame.connect(_pump)
	if tree.root != null and not tree.root.tree_exiting.is_connected(stop): tree.root.tree_exiting.connect(stop)

func _pump() -> void:
	var started := Time.get_ticks_usec()
	for table: Dictionary in _tables:
		if table.task >= 0:
			if not WorkerThreadPool.is_task_completed(table.task): continue
			WorkerThreadPool.wait_for_task_completion(table.task)
			table.task = -1
		if _list(table): _tables.erase(table)
		break
	var located := 0
	while not _requests.is_empty() and located < LOCATES_PER_FRAME:
		var request: Array = _requests.pop_front()
		_request(request[3], request[0], request[1], request[2], false)
		located += 1
	for at: String in _running.keys():
		if not WorkerThreadPool.is_task_completed(_running[at]): continue
		WorkerThreadPool.wait_for_task_completion(_running[at])
		_running.erase(at)
		_finish(_jobs[at])
	while _running.size() < WORKERS and not _queue.is_empty():
		var at: String = _queue.pop_front()
		_running[at] = WorkerThreadPool.add_task(ELMetalMasks._work.bind(_jobs[at]), false, "Metal mask")
	var used := Time.get_ticks_usec() - started
	spent(used)
	if not _batch.is_empty() and not _batch.done:
		_batch.pump_usec += used
		_batch.pump_worst_usec = maxi(_batch.pump_worst_usec, used)
		_batch.frames += 1
	if _running.is_empty() and _queue.is_empty() and _requests.is_empty() and _tables.is_empty():
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_pump)
		_pumping = false
		if not _batch.is_empty() and not _batch.done:
			_batch.done = true
			print_verbose("Metal masks (%s): %d skins in %.0f ms, %d from the cache, %d worked out (%.2f ms classifying, %.2f ms reading and decoding, per skin); main thread: %.1f ms listing them, then %.1f ms over %d frames (at most %.3f ms), %d classified there" % [
				edition, _batch.skins, (Time.get_ticks_usec() - int(_batch.started)) / 1000.0, _batch.cached, _batch.computed,
				_batch.compute_usec / 1000.0 / maxi(_batch.computed, 1), _batch.prepare_usec / 1000.0 / maxi(_batch.computed, 1),
				_batch.listing_usec / 1000.0, _batch.pump_usec / 1000.0, _batch.frames, _batch.pump_worst_usec / 1000.0, main_thread_classified])

func _finish(job: Dictionary) -> void:
	_ready[job.key] = job.result
	var stats: Dictionary = job.stats
	if not _batch.is_empty() and not _batch.done:
		_batch.skins += 1
		if stats.get("cached", false): _batch.cached += 1
		elif stats.has("compute_usec"):
			_batch.computed += 1
			_batch.compute_usec += int(stats.compute_usec)
			_batch.prepare_usec += int(stats.prepare_usec)
	# Only the result stays: the job's bytes and inputs go.
	_jobs[job.key] = {"key": job.key}
	finished.emit(job.key)

## Counts main thread time spent on masks (main_thread_usec).
static func spent(usec: int) -> void:
	main_thread_usec += usec
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_frame_usec = 0
	_frame_usec += usec
	main_thread_worst_usec = maxi(main_thread_worst_usec, _frame_usec)

## A figure's masks if they are ready (see lookup), else null.
func ready_masks(at: String) -> Variant:
	return _ready.get(at)

## A worker thread's part: reads the figure and skins, reuses the kept masks
## when their bytes match, or works them out and keeps them.
static func _work(job: Dictionary) -> void:
	var flags: Array = job.flags
	if flags[0]: return
	var stats: Dictionary = job.stats
	var started := Time.get_ticks_usec()
	var mod := read_location(job.mod)
	var main := read_location(job.main.location)
	var second := read_location(job.second.location) if not job.second.is_empty() else PackedByteArray()
	if mod.is_empty() or main.is_empty(): return
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(var_to_bytes([VERSION, SIDE, ELFigure.METAL_PARTS, ELFigure.METAL_NAMES, ELFigure.SOFT_PARTS, ELFigure.MACHINE_WINGS, ELFigure.CLOTH_PARTS, job.has_second, job.second.is_empty()]))
	for bytes: PackedByteArray in [mod, main, second]:
		hashing.update(var_to_bytes(bytes.size()))
		if not bytes.is_empty(): hashing.update(bytes)
	var digest := hashing.finish()
	var levels: Variant = _load(job.path, digest)
	if levels == null:
		var figure_inputs := inputs(job, mod, main, second)
		stats.prepare_usec = Time.get_ticks_usec() - started
		if flags[0]: return
		var classified := Time.get_ticks_usec()
		levels = {}
		for role: String in figure_inputs:
			levels[role] = classify(figure_inputs[role].pixels, figure_inputs[role].parts, SIDE)
		stats.compute_usec = Time.get_ticks_usec() - classified
		_store(job.path, digest, levels)
	else:
		stats.cached = true
	var textures := {}
	for role: String in levels:
		var bytes: PackedByteArray = levels[role]
		if bytes.size() != SIDE * SIDE: continue
		var image := Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, bytes)
		image.generate_mipmaps()
		textures[role] = ImageTexture.create_from_image(image)
	job.result = textures

## Where `location` ([path, offset, size]) points, read with its own file.
static func read_location(location: Array) -> PackedByteArray:
	if location.size() < 3: return PackedByteArray()
	var file := FileAccess.open(location[0], FileAccess.READ)
	if file == null: return PackedByteArray()
	file.seek(location[1])
	return file.get_buffer(location[2])

static func _load(path: String, digest: PackedByteArray) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 25 or file.get_32() != MAGIC or file.get_32() != VERSION: return null
	if file.get_buffer(16) != digest: return null
	var roles := file.get_8()
	var levels := {}
	for role: String in ["main", "second"]:
		if roles & (1 if role == "main" else 2) == 0: continue
		var bytes := file.get_buffer(SIDE * SIDE)
		if bytes.size() != SIDE * SIDE: return null
		levels[role] = bytes
	return levels

static func _store(path: String, digest: PackedByteArray, levels: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_32(MAGIC)
	file.store_32(VERSION)
	file.store_buffer(digest)
	file.store_8((1 if levels.has("main") else 0) | (2 if levels.has("second") else 0))
	for role: String in ["main", "second"]:
		if levels.has(role): file.store_buffer(levels[role])

## Each skin's classifier inputs, {role: {pixels, parts}}, for the skins with
## metal parts on them: the figure's parts as ELModel.build dresses them.
static func inputs(job: Dictionary, mod: PackedByteArray, main: PackedByteArray, second: PackedByteArray) -> Dictionary:
	var package := ELArchive.from_bytes(mod)
	if not package.error.is_empty(): return {}
	var parts := {"main": [], "second": []}
	var metal := {"main": [], "second": []}
	for link: Array in ELFigure.hierarchy(package.read(job.template)):
		var name: String = link[0]
		if name in ELModel.EFFECT_ANCHORS: continue
		var figure := ELFigure.parse(package.read(name))
		if figure.is_empty(): continue
		var slot := int(figure.texture_slot)
		if slot == 14 or int(figure.material_id) == ELFigure.MATERIAL_MAGIC or ELFigure.is_cloth(job.template, name): continue
		var role := "main"
		if slot == 2 and job.has_second and not job.second.is_empty(): role = "second"
		elif slot == 2 and job.has_second: continue
		var arrays: Array = figure.arrays
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		parts[role].append(part_bytes(MARK_PART, uvs, indices))
		if ELFigure.is_machine_wing(job.template, name): metal[role].append(part_bytes(MARK_SOLID, uvs, indices))
		elif ELFigure.is_metal_part(name): metal[role].append(part_bytes(MARK_METAL, uvs, indices))
	var inputs := {}
	for role: String in metal:
		if metal[role].is_empty(): continue
		var image := ELTexture.decode(main if role == "main" else second)
		if image == null: continue
		var blob := PackedByteArray()
		for bytes: PackedByteArray in parts[role] + metal[role]: blob.append_array(bytes)
		inputs[role] = {"pixels": skin_pixels(image), "parts": blob}
	return inputs

## A skin as the classifier reads it: SIDE x SIDE RGBA8.
static func skin_pixels(image: Image) -> PackedByteArray:
	image = image.duplicate()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SIDE, SIDE, Image.INTERPOLATE_BILINEAR)
	return image.get_data()

## One part for the classifier: its mark, UV and index counts, UVs, indices.
static func part_bytes(mark: int, uvs: PackedVector2Array, indices: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedInt32Array([mark, uvs.size(), indices.size()]).to_byte_array()
	bytes.append_array(uvs.to_byte_array())
	bytes.append_array(indices.to_byte_array())
	return bytes

## Where a skin (`pixels`, side x side RGBA8) is painted as metal, one byte
## per texel. `parts` lists the figure's parts on it (part_bytes): its named
## armour and weapons show what its metal looks like, their grey (steel,
## iron) and gold texels as _painted_metal finds them. Elsewhere on the
## figure (every part but feathers, hair and cloth) a texel is metal when it
## is painted in those colours too, so a chest plate or greave on the body
## shines like the pauldrons it matches, while skin, hair and leather of a
## similar hue stay matte (common on the body, rare on the armour). Parts
## marked MARK_SOLID (machine wings) are metal all over.
## Compiled (native/el_assets.c) where the platform has the library.
static func classify(pixels: PackedByteArray, parts: PackedByteArray, side: int) -> PackedByteArray:
	if OS.get_thread_caller_id() == OS.get_main_thread_id(): main_thread_classified += 1
	if native: return ClassDB.class_call_static(&"ELNativeAssets", &"metal_mask", pixels, parts, side)
	return classify_script(pixels, parts, side)

static func classify_script(pixels: PackedByteArray, parts: PackedByteArray, side: int) -> PackedByteArray:
	var count := side * side
	if side <= 0 or pixels.size() != count * 4: return PackedByteArray()
	var cover := PackedByteArray()
	cover.resize(count)
	# The figure's parts first, then its metal ones over them.
	for metal_pass in [false, true]:
		var at := 0
		while at + 12 <= parts.size():
			var mark := parts.decode_s32(at)
			var uv_count := parts.decode_s32(at + 4)
			var index_count := parts.decode_s32(at + 8)
			var next := at + 12 + uv_count * 8 + index_count * 4
			if uv_count < 0 or index_count < 0 or next > parts.size(): return PackedByteArray()
			if (mark != MARK_PART) == metal_pass:
				_cover(cover, parts.slice(at + 12, at + 12 + uv_count * 8).to_float32_array(), parts.slice(at + 12 + uv_count * 8, next).to_int32_array(), side, mark)
			at = next
	var painted := PackedFloat32Array()
	var greyer := PackedFloat32Array()
	var skin := PackedFloat32Array()
	var bins := PackedInt32Array()
	painted.resize(count)
	greyer.resize(count)
	skin.resize(count)
	bins.resize(count)
	var chroma := CHROMA_BINS
	var seed_hist := PackedFloat32Array()
	var body_hist := PackedFloat32Array()
	var seed_weight := 0.0
	var seed_warmth := 0.0
	seed_hist.resize(chroma * chroma * VALUE_BINS)
	body_hist.resize(seed_hist.size())
	for i in count:
		if pixels[i * 4 + 3] < 128: continue
		var c := Color(pixels[i * 4] / 255.0, pixels[i * 4 + 1] / 255.0, pixels[i * 4 + 2] / 255.0)
		var hue := c.h
		var saturation := c.s
		var value := c.v
		var p := _painted_metal(value, saturation, hue)
		painted[i] = p
		greyer[i] = _painted_metal(value, saturation, hue, 0.32, 0.18)
		var tone := _skin_tone(saturation, hue)
		skin[i] = tone
		var angle := hue * TAU
		var a := clampi(int((saturation * cos(angle) + 1.0) * 0.5 * chroma), 0, chroma - 1)
		var b := clampi(int((saturation * sin(angle) + 1.0) * 0.5 * chroma), 0, chroma - 1)
		var v := clampi(int(value * VALUE_BINS), 0, VALUE_BINS - 1)
		var bin := (a * chroma + b) * VALUE_BINS + v
		bins[i] = bin
		if cover[i] == MARK_METAL:
			seed_hist[bin] += p
			seed_weight += p
			seed_warmth += p * tone
		elif cover[i] == MARK_PART: body_hist[bin] += p
	seed_hist = _blur_bins(seed_hist)
	body_hist = _blur_bins(body_hist)
	var peak := 0.0
	for value in seed_hist: peak = maxf(peak, value)
	# Skin-toned texels are learnt only when the named metal itself is painted
	# that warm (bronze, brass), never beside plain steel.
	var skin_kept := 1.0 - smoothstep(0.1, 0.3, seed_warmth / maxf(seed_weight, 0.000001))
	var learnt := PackedFloat32Array()
	learnt.resize(count)
	if peak > 0.0:
		for i in count:
			if cover[i] == 0 or painted[i] <= 0.0: continue
			var in_seeds := seed_hist[bins[i]]
			var share := in_seeds / maxf(in_seeds + body_hist[bins[i]], 0.000001)
			learnt[i] = smoothstep(0.1, 0.35, in_seeds / peak) * smoothstep(0.12, 0.3, share) * smoothstep(0.15, 0.45, greyer[i]) * (1.0 - skin[i] * skin_kept)
	# A lone matching texel amid skin or cloth is paint, not a plate.
	var around := _box(learnt, side, 2)
	var levels := PackedByteArray()
	levels.resize(count)
	for i in count:
		var named := painted[i] if cover[i] == MARK_METAL else (1.0 if cover[i] == MARK_SOLID else 0.0)
		var value := maxf(named, learnt[i] * smoothstep(0.1, 0.3, around[i]))
		levels[i] = int(value * 255.0 + 0.5)
	return levels

## How much a texel (value, saturation, hue) looks painted as metal: low
## saturation (fading in from `tinted` to `grey_below`) at a mid to high
## value, or a bright gold.
## Away from the named parts the stricter grey keeps pale skin matte.
static func _painted_metal(v: float, s: float, h: float, tinted := 0.38, grey_below := 0.18) -> float:
	var grey := smoothstep(tinted, grey_below, s) * smoothstep(0.15, 0.35, v)
	var gold := smoothstep(0.45, 0.65, v) * (1.0 - smoothstep(0.02, 0.06, absf(h - 0.12))) * smoothstep(0.25, 0.4, s)
	return maxf(grey, gold)

## How much a texel looks like skin (faces, arms): a faint warm tint, which
## shaded skin keeps where it greys towards steel (gold sits further round
## the colour wheel).
static func _skin_tone(s: float, h: float) -> float:
	var away := absf(h - 0.03)
	away = minf(away, 1.0 - away)
	return smoothstep(0.08, 0.14, s) * (1.0 - smoothstep(0.05, 0.08, away))

## Texels (of a `side` square) under the triangles (`uvs` as u, v pairs and
## `indices`) get `mark`, row span by row span (texel centres inside).
static func _cover(cover: PackedByteArray, uvs: PackedFloat32Array, indices: PackedInt32Array, side: int, mark: int) -> void:
	var uv_count := uvs.size() / 2
	for t in range(0, indices.size() - 2, 3):
		var i0 := indices[t]
		var i1 := indices[t + 1]
		var i2 := indices[t + 2]
		if mini(i0, mini(i1, i2)) < 0 or maxi(i0, maxi(i1, i2)) >= uv_count: continue
		var a := Vector2(uvs[i0 * 2], uvs[i0 * 2 + 1]) * side
		var b := Vector2(uvs[i1 * 2], uvs[i1 * 2 + 1]) * side
		var c := Vector2(uvs[i2 * 2], uvs[i2 * 2 + 1]) * side
		var top := minf(a.y, minf(b.y, c.y))
		var bottom := maxf(a.y, maxf(b.y, c.y))
		if bottom - top > side * 2 or maxf(a.x, maxf(b.x, c.x)) - minf(a.x, minf(b.x, c.x)) > side * 2: continue
		# A sliver too thin to hold a texel centre still marks its own.
		var centre := (a + b + c) / 3.0
		cover[posmod(int(floorf(centre.y)), side) * side + posmod(int(floorf(centre.x)), side)] = mark
		for y in range(int(ceilf(top - 0.5)), int(floorf(bottom - 0.5)) + 1):
			var row := y + 0.5
			var low := INF
			var high := -INF
			if (a.y <= row) != (b.y <= row):
				var x := a.x + (row - a.y) * (b.x - a.x) / (b.y - a.y)
				low = minf(low, x)
				high = maxf(high, x)
			if (b.y <= row) != (c.y <= row):
				var x := b.x + (row - b.y) * (c.x - b.x) / (c.y - b.y)
				low = minf(low, x)
				high = maxf(high, x)
			if (c.y <= row) != (a.y <= row):
				var x := c.x + (row - c.y) * (a.x - c.x) / (a.y - c.y)
				low = minf(low, x)
				high = maxf(high, x)
			if low > high: continue
			var wrapped := posmod(y, side) * side
			for x in range(int(ceilf(low - 0.5)), int(floorf(high - 0.5)) + 1):
				cover[wrapped + posmod(x, side)] = mark

## Spreads a colour histogram to its neighbouring bins, normalised to sum 1.
static func _blur_bins(hist: PackedFloat32Array) -> PackedFloat32Array:
	var chroma := CHROMA_BINS
	var levels := VALUE_BINS
	var out := PackedFloat32Array()
	out.resize(hist.size())
	var total := 0.0
	for a in chroma:
		for b in chroma:
			for v in levels:
				var sum := 0.0
				for da in range(-1, 2):
					for db in range(-1, 2):
						for dv in range(-1, 2):
							var na := a + da
							var nb := b + db
							var nv := v + dv
							if na < 0 or nb < 0 or nv < 0 or na >= chroma or nb >= chroma or nv >= levels: continue
							var weight := (0.5 if da != 0 else 1.0) * (0.5 if db != 0 else 1.0) * (0.5 if dv != 0 else 1.0)
							sum += hist[(na * chroma + nb) * levels + nv] * weight
				out[(a * chroma + b) * levels + v] = sum
				total += sum
	if total > 0.0:
		for i in out.size(): out[i] /= total
	return out

## The mean of each texel's square neighbourhood (`radius` texels out).
static func _box(values: PackedFloat32Array, side: int, radius: int) -> PackedFloat32Array:
	var span := float(radius * 2 + 1)
	var rows := PackedFloat32Array()
	rows.resize(values.size())
	for y in side:
		var at := y * side
		var sum := 0.0
		for d in range(-radius, radius + 1): sum += values[at + clampi(d, 0, side - 1)]
		for x in side:
			rows[at + x] = sum / span
			sum += values[at + mini(x + radius + 1, side - 1)] - values[at + maxi(x - radius, 0)]
	var out := PackedFloat32Array()
	out.resize(values.size())
	for x in side:
		var sum := 0.0
		for d in range(-radius, radius + 1): sum += rows[clampi(d, 0, side - 1) * side + x]
		for y in side:
			out[y * side + x] = sum / span
			sum += rows[mini(y + radius + 1, side - 1) * side + x] - rows[maxi(y - radius, 0) * side + x]
	return out
