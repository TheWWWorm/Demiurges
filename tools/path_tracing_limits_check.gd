extends SceneTree
## Checks of the path tracer's fixed budgets (ELPathTracing): the geometry
## ranges, which must be reused as objects come and go and must not rebuild
## the scene over and over when it does not fit, and the texture-array
## layers, which must not turn surfaces white or lose their cutouts when
## there are more textures than layers.
##
##   godot --headless --path game --script ../tools/path_tracing_limits_check.gd
##   godot --path game --rendering-method forward_plus --rendering-driver vulkan \
##       --resolution 1280x720 --script ../tools/path_tracing_limits_check.gd
##
## Headless: the range allocator under churn and the texture layers. On a
## GPU with ray tracing it also compiles every ray program, and in a demo
## battle (needs the second game's files) traces with a shrunken geometry
## budget: an over-budget scene leaves objects out once and settles, and
## objects shown and hidden over and over under a tight budget all end up
## traced, with few rebuilds.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_ranges_churn()
	_ranges_over_capacity()
	_texture_layers()
	if ELPathTracing.available():
		_compile_programs()
		await _battle_budget()
	else:
		print("No ray-tracing device: the GPU checks are skipped.")
	print("%d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# -- geometry ranges --------------------------------------------------------

## Allocates and frees ranges in a random order with the live total below the
## capacity. A failed allocation must always fit once packed (the rebuild the
## tracer asks for), and the rebuild must then hold everything.
func _ranges_churn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	const CAPACITY := 20000
	var ranges := ELPathTracing.Ranges.new(CAPACITY)
	var live := []   # [start, size]
	var failed := 0
	var rebuilds := 0
	var overlap := false
	var steps := 40000
	for step in steps:
		if not live.is_empty() and (rng.randf() < 0.3 or ranges.used > CAPACITY * 0.7):
			var item: Array = live.pop_at(rng.randi() % live.size())
			ranges.release(item[0], item[1])
			continue
		var size := rng.randi_range(3, 600)
		if ranges.used + size > CAPACITY * 0.75: continue
		var start := ranges.allocate(size)
		if start < 0:
			failed += 1
			if not ranges.fits_packed(size): overlap = true   # must not happen below the capacity
			# The rebuild: everything again, packed, then the new one.
			rebuilds += 1
			ranges.clear()
			for item: Array in live: item[0] = ranges.allocate(item[1])
			start = ranges.allocate(size)
			if start < 0 or live.any(func(item: Array) -> bool: return item[0] < 0): overlap = true
		live.append([start, size])
		if step % 1000 == 0 and _overlaps(live): overlap = true
	var total := 0
	for item: Array in live: total += item[1]
	check(not overlap and not _overlaps(live), "ranges: live ranges never overlap, and a failed allocation always fits once packed")
	check(ranges.used == total, "ranges: the live count matches the live ranges (%d)" % total)
	check(rebuilds * 100 < steps, "ranges: churn below 75%% of the capacity rebuilds rarely (%d rebuilds in %d steps, %d failed allocations)" % [rebuilds, steps, failed])
	for item: Array in live: ranges.release(item[0], item[1])
	check(ranges.used == 0 and ranges.high == 0 and ranges.report().holes == 0, "ranges: freeing everything merges all the free space back")
	# The old allocator only ever moved upwards: this much churn is many times
	# the capacity, so it would have overflowed long ago.
	var reused := ELPathTracing.Ranges.new(1000)
	var ok := true
	for i in 10000:
		var a := reused.allocate(300)
		var b := reused.allocate(500)
		ok = ok and a >= 0 and b >= 0
		reused.release(a, 300)
		reused.release(b, 500)
	check(ok and reused.high == 0, "ranges: freed ranges are reused (10000 cycles of 800 units in a capacity of 1000)")

func _overlaps(live: Array) -> bool:
	var sorted := live.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in range(1, sorted.size()):
		if sorted[i - 1][0] + sorted[i - 1][1] > sorted[i][0]: return true
	return false

func _ranges_over_capacity() -> void:
	var ranges := ELPathTracing.Ranges.new(100)
	var a := ranges.allocate(60)
	var b := ranges.allocate(50)
	check(a == 0 and b == -1 and not ranges.fits_packed(50), "ranges: a range past the capacity fails and would not fit packed either (no rebuild)")
	ranges.release(a, 60)
	var c := ranges.allocate(10)
	var d := ranges.allocate(20)
	ranges.release(c, 10)
	check(ranges.largest_free() == 70 and ranges.fits_packed(80) and ranges.allocate(80) == -1, "ranges: a fragmented capacity fails an allocation that fits once packed")
	ranges.release(d, 20)
	check(ranges.used == 0 and ranges.high == 0, "ranges: all free again")

# -- texture layers ---------------------------------------------------------

func _texture(colour: Color, cut: bool) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	if cut:
		for y in 8:
			for x in 4: image.set_pixel(x, y, Color(colour, 0.0))
	return ImageTexture.create_from_image(image)

## A slot as ELPathTracing._update_slot leaves it, its record returned.
func _use(tracer: ELPathTracing, id: int, look: Dictionary) -> PackedByteArray:
	var material := tracer._material(look)
	tracer._slots[id] = {"look": look, "flags": material[1], "layers": material[2]}
	return material[0]

func _texture_layers() -> void:
	var tracer := ELPathTracing.new()
	tracer._effect = ELPathTracing.Effect.new()
	var probe := _texture(Color.RED, false)
	if probe.get_image() == null:
		print("Textures keep no image here: the texture-layer checks are skipped.")
		tracer.free()
		return
	var id := 0
	# Every layer held by an opaque texture in view.
	for i in ELPathTracing.LAYERS:
		_use(tracer, id, {"texture": _texture(Color(float(i % 7) / 7.0, 0.5, 0.25), false), "flags": 0})
		id += 1
	check(tracer._next_layer == ELPathTracing.LAYERS, "layers: %d textures fill the array" % ELPathTracing.LAYERS)
	tracer._pinned.clear()
	# One more opaque texture: no layer, traced in its average colour, not white.
	var green := Color(0.1, 0.6, 0.2)
	var record := _use(tracer, id, {"texture": _texture(green, false), "flags": 0})
	id += 1
	var layer := record.decode_s32(4)
	var tint := Vector3(record.decode_float(16), record.decode_float(20), record.decode_float(24))
	var expected := green.srgb_to_linear()
	check(layer == -1 and tint.distance_to(Vector3(expected.r, expected.g, expected.b)) < 0.02,
		"layers: a texture past the array is traced in its average colour (%s), not white" % tint)
	# One more cutout: it takes an opaque texture's layer and keeps its cut.
	tracer._layer_ops.clear()
	var cut_look := {"texture": _texture(Color.YELLOW, true), "flags": 0, "cutoff": 0.5}
	record = _use(tracer, id, cut_look)
	id += 1
	check(record.decode_s32(4) >= 0 and (record.decode_u32(8) & ELPathTracing.SURFACE_ALPHA) != 0,
		"layers: a cutout past the array takes a layer and keeps its alpha cut")
	var resent: bool = tracer._layer_ops.size() == 1 and tracer._layer_ops[0][0] == "material" and (tracer._layer_ops[0][2] as PackedByteArray).decode_s32(4) == -1
	check(resent and tracer._layer_counts.given_up == 1, "layers: the opaque texture it displaced is re-sent in its average colour")
	tracer._pinned.clear()
	# Every layer held by a cutout: one more cutout has no layer but keeps
	# its classification.
	for i in ELPathTracing.LAYERS:
		_use(tracer, id, {"texture": _texture(Color(0.2, float(i % 5) / 5.0, 0.7), true), "flags": 0, "cutoff": 0.5})
		id += 1
		tracer._pinned.clear()
	record = _use(tracer, id, {"texture": _texture(Color.BLUE, true), "flags": 0, "cutoff": 0.5})
	id += 1
	check(record.decode_s32(4) == -1 and (record.decode_u32(8) & ELPathTracing.SURFACE_ALPHA) != 0,
		"layers: a cutout without a layer keeps its alpha classification")
	# Objects leave the scene: their layers are taken over by new textures.
	tracer._pinned.clear()
	tracer._slots.clear()
	var evicted_before: int = tracer._layer_counts.evicted
	record = _use(tracer, id, {"texture": _texture(Color.MAGENTA, false), "flags": 0})
	check(record.decode_s32(4) >= 0 and tracer._layer_counts.evicted > evicted_before, "layers: layers no slot holds any more are reused")
	var layers_free := tracer._free_layers.size()
	check(layers_free == ELPathTracing.LAYERS - 1, "layers: all unheld layers become free at once (%d)" % layers_free)
	tracer._effect = null
	tracer.free()

# -- GPU ----------------------------------------------------------------------

func _compile_programs() -> void:
	var rd := RenderingServer.get_rendering_device()
	var shaders := ELPathTraceShaders
	var rays := RDShaderSource.new()
	rays.set_stage_source(RenderingDevice.SHADER_STAGE_RAYGEN, shaders.RAYGEN)
	rays.set_stage_source(RenderingDevice.SHADER_STAGE_CLOSEST_HIT, shaders.CLOSEST_HIT)
	rays.set_stage_source(RenderingDevice.SHADER_STAGE_MISS, shaders.MISS)
	var spirv := rd.shader_compile_spirv_from_source(rays)
	var errors := ""
	for stage: int in [RenderingDevice.SHADER_STAGE_RAYGEN, RenderingDevice.SHADER_STAGE_CLOSEST_HIT, RenderingDevice.SHADER_STAGE_MISS]:
		errors += spirv.get_stage_compile_error(stage)
	check(errors.is_empty(), "the ray programs compile " + errors)
	for guides: bool in [false, true]:
		var source := RDShaderSource.new()
		source.source_compute = shaders.FILTER.replace("#version 460\n", "#version 460\n#define RAY_RECONSTRUCTION\n") if guides else shaders.FILTER
		var compiled := rd.shader_compile_spirv_from_source(source)
		check(compiled.compile_error_compute.is_empty(), "the %s compiles %s" % ["Ray Reconstruction guide program" if guides else "smoothing program", compiled.compile_error_compute])

func _settle(view: Node, seconds: float) -> void:
	var clock := 0.0
	while clock < seconds:
		view.ai_clock = -1000.0
		await process_frame
		clock += root.get_process_delta_time()

## Shrinks the render thread's geometry budget (on that thread) and starts
## the traced scene again.
func _budget(tracer: ELPathTracing, vertices: int, corners: int) -> void:
	var effect := tracer._effect
	var shrink := func() -> void:
		effect._vertex_ranges = ELPathTracing.Ranges.new(vertices)
		effect._corner_ranges = ELPathTracing.Ranges.new(corners)
		effect._skipped.clear()
		effect._skipped_total = 0
		effect._rebuilds = 0
	RenderingServer.call_on_render_thread(shrink)
	await process_frame
	await process_frame
	tracer._reset()

func _battle_budget() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el2"):
		print("No second-game files: the battle checks are skipped.")
		view.queue_free()
		return
	view.settings.values.auto_camera = false
	view._start("el2", {})
	await _settle(view, 1.0)
	var tracer: ELPathTracing = view.path_tracing
	tracer.set_enabled(true)
	await _settle(view, 2.0)
	var whole := tracer._effect.limits()
	if whole.is_empty():
		check(false, "the traced battle reports its budget")
		view.queue_free()
		return
	var vertices: int = whole.vertices.used
	var corners: int = whole.corners.used
	print("   battle: %d vertices, %d corners, %d objects" % [vertices, corners, whole.objects.used])
	check(whole.skipped == 0 and whole.rebuilds == 0, "battle: everything fits the real budget, no rebuilds")

	# Over budget: half of what the scene needs.
	await _budget(tracer, vertices / 2, corners / 2)
	await _settle(view, 2.0)
	var first := tracer._effect.limits()
	await _settle(view, 2.0)
	var later := tracer._effect.limits()
	print("   over budget: skipped %d (total %d -> %d), rebuilds %d, vertices %d/%d" % [later.skipped, first.skipped_total, later.skipped_total, later.rebuilds, later.vertices.used, later.vertices.capacity])
	check(later.skipped_over_budget > 0 and later.objects.used > 0, "over budget: some objects are left out, the rest is traced")
	check(later.rebuilds == 0 and later.skipped_total == first.skipped_total, "over budget: no rebuild and nothing defined again (settled, no loop)")

	# Tight budget with churn: figures hidden and shown in a shuffled order,
	# and stand-in objects of random sizes (as effects come and go) made and
	# freed around them, up to 40% of the scene's size on top of it.
	await _budget(tracer, int(vertices * 1.6), int(corners * 1.6))
	await _settle(view, 1.0)
	var models: Array[ELModel] = []
	for model: ELModel in tracer._models:
		if is_instance_valid(model) and model.visible: models.append(model)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cycles := 60
	var extras := {}   # fake id -> [vertices, corners]
	var extra_vertices := 0
	var extra_corners := 0
	var next_extra := 1 << 40
	for cycle in cycles:
		var ops := []
		for id: int in extras.keys():
			if rng.randf() < 0.5:
				extra_vertices -= extras[id][0]
				extra_corners -= extras[id][1]
				extras.erase(id)
				ops.append(["free", id])
		while true:
			var count := rng.randi_range(8, maxi(vertices / 10, 16))
			var triangles := rng.randi_range(4, maxi(corners / 30, 8))
			if extra_vertices + count > vertices * 0.4 or extra_corners + triangles * 3 > corners * 0.4: break
			var indices := PackedInt32Array()
			indices.resize(triangles * 3)
			var uvs := PackedVector2Array()
			uvs.resize(count)
			ops.append(["define", next_extra, count, indices.to_byte_array(), uvs.to_byte_array(), PackedByteArray()])
			extras[next_extra] = [count, triangles * 3]
			extra_vertices += count
			extra_corners += triangles * 3
			next_extra += 1
		var effect := tracer._effect
		effect._mutex.lock()
		effect._ops.append_array(ops)
		effect._mutex.unlock()
		var hidden: Array[ELModel] = []
		for model in models:
			if rng.randf() < 0.4:
				model.visible = false
				hidden.append(model)
		await _settle(view, 0.05)
		if cycle % 20 == 10:
			var now := tracer._effect.limits()
			print("   churn cycle %d: objects %d, vertices %d/%d/%d, corners %d/%d/%d, holes %d, rebuilds %d, waiting %d" % [cycle, now.objects.used,
				now.vertices.used, now.vertices.allocated, now.vertices.capacity, now.corners.used, now.corners.allocated, now.corners.capacity, now.corners.holes, now.rebuilds, now.skipped])
		for model in hidden: model.visible = true
		await _settle(view, 0.05)
	var leftover := []
	for id: int in extras: leftover.append(["free", id])
	tracer._effect._mutex.lock()
	tracer._effect._ops.append_array(leftover)
	tracer._effect._mutex.unlock()
	# A pending rebuild waits at most REBUILD_INTERVAL callbacks.
	await _settle(view, 4.0)
	var churned := tracer._effect.limits()
	print("   churn: %d models, %d cycles, rebuilds %d, waits for a rebuild %d, skipped now %d (over budget %d), vertex holes %d" % [models.size(), cycles, churned.rebuilds, churned.skipped_total, churned.skipped, churned.skipped_over_budget, churned.vertices.holes])
	check(churned.skipped == 0, "churn: every object is traced once settled")
	check(churned.rebuilds <= cycles / 4, "churn: rebuilds stay few (%d in %d cycles)" % [churned.rebuilds, cycles])

	# A define that fits only once packed: one rebuild, then the whole scene
	# is traced again (the stand-ins are not sent again, as gone objects).
	await _budget(tracer, vertices + 100, corners + 1000)
	await _settle(view, 1.0)
	var packed_before := tracer._effect.limits()
	var first_id := 1 << 41
	_extra_ops(tracer, [_fake_define(first_id, 50), _fake_define(first_id + 1, 30)])
	await _settle(view, 0.2)
	_extra_ops(tracer, [["free", first_id], _fake_define(first_id + 2, 60)])
	await _settle(view, 0.2)
	var waiting := tracer._effect.limits()
	await _settle(view, 4.0)
	var packed := tracer._effect.limits()
	print("   fragmented: waiting %d before, rebuilds %d, objects %d -> %d, vertex holes %d" % [waiting.skipped, packed.rebuilds, packed_before.objects.used, packed.objects.used, packed.vertices.holes])
	check((waiting.skipped == 1 or waiting.rebuilds == 1) and waiting.skipped_over_budget == 0, "fragmented: the define that fits only packed waits for a rebuild, not left out for good")
	check(packed.rebuilds == 1 and packed.skipped == 0 and packed.objects.used == packed_before.objects.used and packed.vertices.used == vertices,
		"fragmented: one rebuild packs the scene and traces all of it again")
	view.queue_free()
	await process_frame

func _fake_define(id: int, count: int) -> Array:
	var indices := PackedInt32Array([0, 0, 0])
	var uvs := PackedVector2Array()
	uvs.resize(count)
	return ["define", id, count, indices.to_byte_array(), uvs.to_byte_array(), PackedByteArray()]

func _extra_ops(tracer: ELPathTracing, ops: Array) -> void:
	tracer._effect._mutex.lock()
	tracer._effect._ops.append_array(ops)
	tracer._effect._mutex.unlock()
