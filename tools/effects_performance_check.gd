extends SceneTree
## Asset-free V4 workload and rendering regressions. No original game files.
## -- --render exercises both actual blood shaders and GPU buffer readback.
## BENCH lines are script CPU microbenchmarks, not hardware frame-rate claims.

var failures: Array[String] = []
var checks := 0

class ParticleProfile extends ELProfile:
	var payload := PackedByteArray()
	func read(_archive: String, _entry: String) -> PackedByteArray:
		return payload

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_frame_cache()
	_cache_limits()
	_generations()
	_hidden_map()
	_hidden_combat()
	_blood_lifecycle()
	if "--benchmark" in OS.get_cmdline_user_args():
		_frame_benchmark()
		_cache_workloads()
	if "--render" in OS.get_cmdline_user_args(): await _render()
	print("EFFECTS PERFORMANCE: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _file(counts: Array, looping := 0) -> ELParticleFile:
	var file := ELParticleFile.new()
	file.frames = counts.size()
	file.columns = 4
	file.rows = 4
	file.loop_end = looping
	file.closing_frame = looping > 0 and file.frames - looping == 1
	file.texture = "v4_test.bmp"
	var total := 0
	for count: int in counts:
		file.starts.append(total)
		file.max_count = maxi(file.max_count, count)
		total += count
	file.starts.append(total)
	file.positions.resize(total * 3)
	file.sizes.resize(total)
	file.cells.resize(total * 2)
	file.rgb.resize(total * 3)
	file.alpha.resize(total)
	for i in total:
		file.positions[i * 3] = float(i % 17) * 0.13
		file.positions[i * 3 + 1] = float(i % 19) * -0.11
		file.positions[i * 3 + 2] = float(i % 13) * 0.09
		file.sizes[i] = (-1.0 if i % 3 == 0 else 1.0) * (0.12 + (i % 5) * 0.07)
		file.cells.encode_u16(i * 2, i % 16)
		file.rgb[i * 3] = (i * 17) % 256
		file.rgb[i * 3 + 1] = (i * 31) % 256
		file.rgb[i * 3 + 2] = (i * 43) % 256
		file.alpha[i] = 255 - (i % 7) * 25
	return file

func _joined(file: ELParticleFile, frames: PackedInt32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for frame: int in frames: result.append_array(file.instances(frame))
	return result

func _frame_cache() -> void:
	var map := ELAdventureEffects.new()
	var file := _file([3, 100, 7, 2, 0, 5, 1], 3)
	var exact := true
	var padded := true
	for loops in [-1, 0, 1, 3]:
		for frame in 30:
			var frames := file.visible_frames(frame, loops)
			var data := map._frame_data(file, frames)
			var expected := _joined(file, frames)
			var actual: PackedFloat32Array = data.buffer
			exact = exact and int(data.count) * 16 == expected.size() and actual.slice(0, expected.size()) == expected
			padded = padded and actual.size() == file.visible_capacity() * 16
			for i in range(expected.size(), actual.size()): padded = padded and actual[i] == 0.0
	check(exact, "cached map frames preserve every position, signed size, atlas cell, colour, alpha and finite-loop tail")
	check(padded, "all phases use one stable GPU capacity and their invisible padding is zero")
	check(file._instances.size() == file.frames, "source-frame preparation remains shared across combined loop phases")
	var frames := file.visible_frames(7)
	check(is_same(map._frame_data(file, frames), map._frame_data(file, frames.duplicate())), "equal phases from different emitters reuse the same combined data")
	var other := _file([3, 100, 7, 2, 0, 5, 1], 3)
	other.positions[0] = 200.0
	check(not is_same(map._frame_data(file, PackedInt32Array([0])), map._frame_data(other, PackedInt32Array([0]))), "different source files never share a frame cache entry")
	var first := map._frame_data(file, PackedInt32Array([0]))
	var old_capacity := file.max_count * ceili(float(file.frames) / file.loop_end)
	print("METRIC sparse_map_upload_bytes: V3=%d V4=%d" % [old_capacity * 64, (first.buffer as PackedFloat32Array).size() * 4])
	check((first.buffer as PackedFloat32Array).size() / 16 < old_capacity and first.count == 3, "a map phase uses the actual maximum overlap rather than max-frame times cycle-count")
	var tiny := _file([1, 0, 1])
	check((map._frame_data(tiny, PackedInt32Array([0])).buffer as PackedFloat32Array).size() == 16, "one-particle sheets retain their original small upload capacity")
	var closing := _file([3, 4, 5, 1000], 3)
	check(closing.visible_capacity() == 5, "a duplicate closing frame does not inflate the stable overlap capacity")
	var temporary := _file([2, 3])
	var reference: WeakRef = weakref(temporary)
	map._frame_data(temporary, PackedInt32Array([0]))
	temporary = null
	check(reference.get_ref() == null, "combined frame keys do not pin decoded source files beyond their own cache lifetime")
	map.free()

func _bytes(x: float) -> PackedByteArray:
	# One real unpacked .pfx frame with one particle, using the decoder's
	# exact binary record. Distinct positions make stale content observable.
	var name := "v4_test.bmp".to_ascii_buffer()
	var bytes := PackedByteArray()
	bytes.resize(40 + name.size() + 18)
	bytes.encode_u32(0, ELParticleFile.MAGIC)
	bytes.encode_u32(4, 1)
	bytes.encode_u32(8, 1)
	bytes.encode_float(16, x)
	bytes.encode_float(28, 1.0)
	for i in range(34, 38): bytes[i] = 255
	bytes.encode_u16(38, name.size())
	for i in name.size(): bytes[40 + i] = name[i]
	bytes.encode_u32(40 + name.size(), 4)
	bytes.encode_u32(44 + name.size(), 4)
	return bytes

func _generations() -> void:
	var first := ParticleProfile.new()
	first.id = "v4_particle_generation"
	first.payload = _bytes(1.25)
	ELAdventureEffects.keep_file(first, "fixture.pfx")
	var first_key := ELAdventureEffects.cache_space(first) + ":fixture.pfx"
	var old := ELAdventureEffects.particle_file(first, "fixture.pfx")
	check(old.error.is_empty() and old.positions[0] == 1.25 and ELAdventureEffects._kept.has(first_key), "a prepared map particle file stays pinned in its own content generation")
	var second := ParticleProfile.new()
	second.id = first.id
	second.payload = _bytes(9.5)
	var current := ELAdventureEffects.particle_file(second, "fixture.pfx")
	var second_key := ELAdventureEffects.cache_space(second) + ":fixture.pfx"
	check(current.positions[0] == 9.5 and not is_same(current, old) and not ELAdventureEffects._kept.has(first_key) and not ELAdventureEffects._files.has(first_key),
		"reimporting the same edition removes pinned old bytes and decodes its replacement payload")
	ELAdventureEffects.keep_file(first, "fixture.pfx")
	var stale := ELAdventureEffects.particle_file(first, "fixture.pfx")
	check(stale.positions[0] == 1.25 and not ELAdventureEffects._kept.has(first_key) and not ELAdventureEffects._files.has(first_key) and is_same(ELAdventureEffects._files[second_key], current),
		"late work from an old profile cannot repopulate or overwrite the current cache")
	first._textures["effects/v4_test"] = _atlas()
	second._textures["effects/v4_test"] = _atlas()
	var map := ELAdventureEffects.new()
	var a := map._material(old, first)
	var b := map._material(current, second)
	check(a != b and a.get_shader_parameter("atlas") != b.get_shader_parameter("atlas"), "particle materials also keep content generations isolated")
	map.free()
	ELAdventureEffects._files.erase(second_key)
	ELAdventureEffects._order.erase(second_key)
	ELAdventureEffects._generations.erase(first.id)

func _cache_limits() -> void:
	var map := ELAdventureEffects.new()
	var counts: Array = []
	counts.resize(map.FRAME_CACHE_ENTRIES)
	counts.fill(1)
	var file := _file(counts)
	for frame in file.frames: map._frame_data(file, PackedInt32Array([frame]))
	var extra := _file([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	for frame in extra.frames: map._frame_data(extra, PackedInt32Array([frame]))
	check(map._frame_cache.size() == map.FRAME_CACHE_ENTRIES and map._frame_order.size() == map.FRAME_CACHE_ENTRIES,
		"combined-frame entry count stays capped after more than 4,096 distinct phases")
	check(not map._frame_cache.has([file.get_instance_id(), PackedInt32Array([0])]), "the oldest combined phase is evicted without changing the decoded file")
	map.free()
	map = ELAdventureEffects.new()
	counts.resize(20)
	counts.fill(8192)
	file = _file(counts)
	for frame in file.frames: map._frame_data(file, PackedInt32Array([frame]))
	var sum := 0
	for data: Dictionary in map._frame_cache.values(): sum += (data.buffer as PackedFloat32Array).size() * 4
	check(map._frame_bytes == sum and sum <= map.FRAME_CACHE_BYTES and map._frame_cache.size() < 20,
		"combined buffers obey the 8 MiB budget with exact byte accounting")
	var before := map._frame_bytes
	var frames := PackedInt32Array()
	for frame in file.frames: frames.append(frame)
	var oversized := map._frame_data(file, frames)
	check((oversized.buffer as PackedFloat32Array).size() * 4 > map.FRAME_CACHE_BYTES and map._frame_bytes == before and not map._frame_cache.has([file.get_instance_id(), frames]),
		"an oversized overlap draws completely without escaping the cache budget")
	map.free()

func _map_effect(map: ELAdventureEffects, file: ELParticleFile) -> Dictionary:
	var node := MultiMeshInstance3D.new()
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = QuadMesh.new()
	mesh.instance_count = 64
	mesh.visible_instance_count = 0
	node.multimesh = mesh
	map.add_child(node)
	return {"file": file, "node": node, "entry": {}, "elapsed": 0.0, "frame": -1, "optional": false, "rain": false}

func _hidden_map() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var map := ELAdventureEffects.new()
	parent.add_child(map)
	map.set_process(false)
	var effect := _map_effect(map, _file([3, 4, 5, 6, 7, 8, 9, 10]))
	map.effects.probe = effect
	map._advance("probe", 0.0)
	parent.visible = false
	map._advance("probe", 0.1)
	check(effect.elapsed == 0.1 and effect.frame == 0 and effect.node.multimesh.visible_instance_count == 3,
		"a hidden map effect advances its clock without rebuilding or uploading a new frame")
	parent.visible = true
	map._advance("probe", 0.0)
	check(effect.frame == 3 and effect.node.multimesh.visible_instance_count == 6, "revealing a map draws the current frame immediately")
	parent.visible = false
	map._advance("probe", 1.0)
	check(map.effects.is_empty(), "a hidden finite map effect still retires at its original lifetime")
	parent.free()

func _hidden_combat() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var effects := ELCombatEffects.new()
	stage.add_child(effects)
	effects.set_process(false)
	var file := _file([2, 3, 4, 5, 6, 7, 8, 9])
	var frames := {}
	for frame in file.frames: frames[frame] = ELCombatEffects._frame_buffer(file, frame)
	var emitter := effects._free_emitter(false)
	emitter.entry = {"file": file, "frames": frames, "bytes": 0}
	emitter.centre_basis = Basis.IDENTITY
	emitter.opacity = 1.0
	emitter.loop = false
	emitter.life = file.frames
	emitter.active = true
	var model := ELModel.new()
	stage.add_child(model)
	model.set_process(false)
	emitter.follow = model
	emitter.following = true
	effects._draw(emitter, 0)
	model.visible = false
	model.frame = 3.0
	effects._step_emitter(emitter, 0.1)
	check(emitter.frame == 0 and emitter.mesh.visible_instance_count == 2 and not emitter.node.visible,
		"a hidden figure attachment skips uploads while its model's animation clock advances")
	model.visible = true
	model.frame = 5.0
	model.position = Vector3(2, 3, 4)
	effects._step_emitter(emitter, 0.0)
	check(emitter.frame == 5 and emitter.mesh.visible_instance_count == 7 and emitter.node.position == model.position,
		"revealed figure particles catch up to the latest authored frame and placement")
	var prop := Node3D.new()
	stage.add_child(prop)
	prop.visible = false
	emitter.following = false
	emitter.visibility_link = prop
	emitter.elapsed = 0.2
	emitter.track = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1])
	effects._step_emitter(emitter, 0.0)
	check(not emitter.node.visible and emitter.frame == 5, "an opaque animation key cannot reveal the particles of a hidden scenery prop")
	prop.visible = true
	effects._step_emitter(emitter, 0.0)
	check(emitter.node.visible and emitter.frame == 6, "a revealed scenery link uploads its current phase")
	stage.visible = false
	effects._step_emitter(emitter, 1.0)
	check(not emitter.active and emitter.mesh.visible_instance_count == 0, "hidden combat transients still expire and release their pool slot")
	stage.free()

func _blood() -> ELCombatBlood:
	var blood := ELCombatBlood.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	blood._drop_node = blood._layer(QuadMesh.new(), material, blood.DROP_LIMIT)
	blood._print_node = blood._layer(PlaneMesh.new(), material, blood.PRINT_LIMIT)
	blood.rng.seed = 1729
	return blood

func _old_drops(drops: Array[Dictionary]) -> Array[Dictionary]:
	var alive: Array[Dictionary] = []
	for drop: Dictionary in drops:
		var p: Vector3 = drop.p
		if p.z < drop.floor: continue
		var v: Vector3 = drop.v
		drop.previous = p
		drop.p = p + v
		v.z = maxf(v.z + float(drop.gravity), float(drop.terminal))
		drop.v = v
		alive.append(drop)
	return alive

func _old_prints(prints: Array[Dictionary], delta: float) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for mark: Dictionary in prints:
		var before: float = mark.age
		var age := before + delta
		mark.age = age
		if age >= ELCombatBlood.PRINT_GONE: continue
		var grow := maxf(0.0, minf(age, ELCombatBlood.PRINT_GROWN) - maxf(before, ELCombatBlood.PRINT_SHOW))
		mark.half = float(mark.half) + grow * float(mark.rate)
		var fade := maxf(0.0, minf(age, ELCombatBlood.PRINT_GONE) - maxf(before, ELCombatBlood.PRINT_HOLD))
		mark.alpha = maxf(0.0, float(mark.alpha) - fade * 0.2)
		kept.append(mark)
	return kept

func _blood_lifecycle() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var blood := _blood()
	parent.add_child(blood)
	check(not blood.is_processing(), "an empty blood layer sleeps instead of receiving idle frame callbacks")
	blood.burst(Vector3(0, 3, 0))
	check(blood.is_processing(), "a new death wakes the blood layer")
	var drops: Array[Dictionary] = blood.drops.duplicate(true)
	var prints: Array[Dictionary] = blood.prints.duplicate(true)
	var drops_identity := blood.drops
	var prints_identity := blood.prints
	var state := blood.rng.state
	var clock := 0.0
	var exact := true
	for delta: float in [0.01, 0.01, 0.05, 0.3, 0.8, 19.5, 5.7]:
		if not drops.is_empty():
			clock += delta
			while clock >= blood.TICK:
				clock -= blood.TICK
				drops = _old_drops(drops)
		else: clock = 0.0
		prints = _old_prints(prints, delta)
		blood._process(delta)
		exact = exact and blood.drops == drops and blood.prints == prints and blood._clock == clock
	check(exact and blood.rng.state == state, "blood simulation, print growth/fade, ordering and RNG state match the V3 reference across mixed frame times")
	check(is_same(drops_identity, blood.drops) and is_same(prints_identity, blood.prints), "blood compacts its original arrays instead of allocating a replacement each tick")
	check(not blood.is_processing() and blood.prints.is_empty() and blood.drops.is_empty(), "the layer sleeps again after all original lifetimes finish")
	blood.burst(Vector3(0, 3, 0))
	parent.visible = false
	blood._process(1.0)
	check(blood._prints_dirty and blood._drops_dirty and blood._print_node.multimesh.visible_instance_count == 0,
		"hidden blood advances while postponing instance updates")
	parent.visible = true
	check(not blood._prints_dirty and not blood._drops_dirty and blood.visible_prints() == blood.PRINTS_PER_BURST,
		"revealing held stains refreshes their latest size and opacity immediately")
	blood.clear()
	check(not blood.is_processing() and blood.visible_prints() == 0, "clearing blood removes visible instances and processing")
	parent.free()

func _legacy_map_buffer(file: ELParticleFile, frames: PackedInt32Array) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	for frame: int in frames: buffer.append_array(file.instances(frame))
	var copies := 1 if file.loop_end <= 0 else ceili(float(file.frames) / file.loop_end)
	buffer.resize(file.max_count * copies * 16)
	return buffer

func _frame_benchmark() -> void:
	var counts: Array = []
	for i in 37: counts.append(64 + (i % 9) * 128)
	var file := _file(counts, 12)
	var map := ELAdventureEffects.new()
	var phases: Array[PackedInt32Array] = []
	for frame in 12: phases.append(file.visible_frames(60 + frame))
	for frame in file.frames: file.instances(frame)
	for frames: PackedInt32Array in phases: map._frame_data(file, frames)
	var before: Array[int] = []
	var after: Array[int] = []
	for repeat in 6:
		var at := Time.get_ticks_usec()
		for i in 1200: _legacy_map_buffer(file, phases[i % phases.size()])
		before.append(Time.get_ticks_usec() - at)
		at = Time.get_ticks_usec()
		for i in 1200: map._frame_data(file, phases[i % phases.size()])
		after.append(Time.get_ticks_usec() - at)
	before.sort()
	after.sort()
	var old_median := (before[2] + before[3]) * 0.5
	var new_median := (after[2] + after[3]) * 0.5
	print("BENCHMARK_JSON: " + JSON.stringify({"name": "map_combined_frame_preparation", "v3_ms": old_median / 1000.0,
		"v4_ms": new_median / 1000.0, "runs": 6, "calls_per_run": 1200, "loop_phases": 12,
		"scope": "same-process warmed script CPU buffer preparation; excludes uploads, rendering and game frame rate"}))
	# Timings are evidence, not a pass/fail gate sensitive to host scheduling.
	check(map._frame_cache.size() == phases.size(), "1,200 repeated map draws reuse twelve prepared phase buffers")
	map.free()

func _cache_workloads() -> void:
	for scenario: Dictionary in [
		{"name": "map_cold_unique_frames", "phases": 64, "particles": 64, "cold": true, "passes": 1},
		{"name": "map_long_loop_in_budget", "phases": 256, "particles": 256, "cold": false, "passes": 2},
		{"name": "map_long_loop_over_budget", "phases": 256, "particles": 1024, "cold": false, "passes": 2}]:
		var counts: Array = []
		counts.resize(int(scenario.phases) + 1)
		counts.fill(int(scenario.particles))
		# Separate decodes: each version warms its own original source-frame
		# cache. The new bounded combined cache must not make misses slower by
		# throwing that established preparation work away.
		var old_file := _file(counts, int(scenario.phases))
		var new_file := _file(counts, int(scenario.phases))
		var phases: Array[PackedInt32Array] = []
		for phase in int(scenario.phases): phases.append(PackedInt32Array([phase]))
		var map := ELAdventureEffects.new()
		if not scenario.cold:
			for frames: PackedInt32Array in phases:
				_legacy_map_buffer(old_file, frames)
				map._frame_data(new_file, frames)
		var before: Array[int] = []
		var after: Array[int] = []
		for sample in 6:
			if scenario.cold:
				old_file._instances.clear()
				new_file._instances.clear()
				map.free()
				map = ELAdventureEffects.new()
			var start := Time.get_ticks_usec()
			for repeat in int(scenario.passes):
				for frames: PackedInt32Array in phases: _legacy_map_buffer(old_file, frames)
			before.append(Time.get_ticks_usec() - start)
			start = Time.get_ticks_usec()
			for repeat in int(scenario.passes):
				for frames: PackedInt32Array in phases: map._frame_data(new_file, frames)
			after.append(Time.get_ticks_usec() - start)
		before.sort()
		after.sort()
		print("BENCHMARK_JSON: " + JSON.stringify({"name": scenario.name, "v3_ms": (before[2] + before[3]) / 2000.0,
			"v4_ms": (after[2] + after[3]) / 2000.0, "runs": 6, "phases": scenario.phases,
			"particles_per_frame": scenario.particles, "calls_per_run": int(scenario.phases) * int(scenario.passes),
			"v3_cached_instance_bytes": int(scenario.phases) * int(scenario.particles) * 64,
			"v4_source_instance_bytes": new_file._instances.size() * int(scenario.particles) * 64,
			"v4_cached_buffer_bytes": map._frame_bytes, "v4_cache_limit_bytes": map.FRAME_CACHE_BYTES,
			"scope": "same-process script CPU preparation; separate source instances; cold decode or long-loop cache working set; excludes upload/rendering"}))
		check(map._frame_bytes <= map.FRAME_CACHE_BYTES and new_file._instances.size() == int(scenario.phases), scenario.name + " bounds the added cache and retains V3's source-frame preparation")
		map.free()

func _atlas() -> ImageTexture:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64: image.set_pixel(x, y, Color.GREEN if x < 16 and y >= 48 else Color.RED)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _measure(image: Image) -> Vector3:
	var result := Vector3.ZERO
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			result.x += c.r
			result.y += c.g
			if c.r + c.g > 0.01: result.z += 1
	return result

func _capture(drop: bool, legacy: bool, scale: float) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(255, 255)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0, 0, 5) if drop else Vector3(0, 5, 0)
	camera.look_at(Vector3.ZERO, Vector3.UP if drop else Vector3.FORWARD)
	camera.current = true
	var blood := ELCombatBlood.new()
	world.add_child(blood)
	blood.set_process(false)
	var code := blood.DROP_SHADER if drop else blood.PRINT_SHADER
	if legacy: code = code.replace("ATLAS_FUNCTION", "").replace("sprite_atlas(atlas, UV, atlas_slot, grid)", "texture(atlas, UV)")
	var material := blood._material(code, _atlas())
	check(material.get_shader_parameter("atlas_max_lod") == 4.0, ("drop" if drop else "print") + " material bounds sampling to its 16-pixel cell mips")
	if drop:
		blood._drop_node = blood._layer(QuadMesh.new(), material, 1)
		blood.drops = [{"p": Vector3.ZERO, "previous": Vector3.ZERO, "size": scale, "cell": Vector2i(0, 3)}]
		blood._draw_drops()
	else:
		blood._print_node = blood._layer(PlaneMesh.new(), material, 1)
		blood.prints = [{"at": Vector3.ZERO, "age": 1.0, "half": scale, "rate": 1.0, "alpha": 1.0, "cell": Vector2i(0, 3), "yaw": 0.0}]
		blood._draw_prints()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--render needs a real renderer")
		return
	await _upload_benchmark()
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if not folder.is_empty(): DirAccess.make_dir_recursive_absolute(folder)
	for drop in [true, false]:
		for tiny in [false, true]:
			var scale := 0.004 if tiny else (2.4 if drop else 1.2)
			var old := await _capture(drop, true, scale)
			var current := await _capture(drop, false, scale)
			var a := _measure(old)
			var b := _measure(current)
			var key := ("drop" if drop else "print") + ("_tiny" if tiny else "_large")
			print("METRIC blood_%s: V3_rgbpixels=%s V4_rgbpixels=%s" % [key, a, b])
			check(a.x > 0.05 and b.x < 0.01 and b.y > 0.1, key + " removes neighbouring blood colours at the actual rendered mip level")
			check(a.z == b.z, key + " retains the same covered pixels")
			if not folder.is_empty():
				old.save_png(folder.path_join("effects_perf_blood_" + key + "_v3.png"))
				current.save_png(folder.path_join("effects_perf_blood_" + key + "_v4.png"))

func _upload_benchmark() -> void:
	# Both complete submission paths run in the same real-renderer process.
	# Await a rendered frame after each batch so uploads cannot accumulate
	# unboundedly. Report only CPU submission time; GPU driver timing is not
	# comparable to a hardware game benchmark on this software renderer.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	camera.position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var map := ELAdventureEffects.new()
	world.add_child(map)
	map.set_process(false)
	var file := _file([1, 17, 65, 2, 145, 34, 9, 90, 8], 4)
	var material := ShaderMaterial.new()
	material.shader = ELAdventureEffects._shader(false)
	ELParticleFile.set_atlas(material, _atlas(), Vector2(4, 4))
	var effects: Array[Dictionary] = []
	var old_capacity := file.max_count * ceili(float(file.frames) / file.loop_end)
	for i in 12:
		var effect := _map_effect(map, file)
		effect.node.material_override = material
		effect.node.position = Vector3((i % 4) * 3.0 - 5.0, 0, (i / 4) * 3.0 - 4.0)
		effect.node.custom_aabb = file.sprite_bounds()
		effects.append(effect)
	var phases: Array[PackedInt32Array] = []
	for frame in 4:
		phases.append(file.visible_frames(40 + frame))
		map._frame_data(file, phases[-1])
	for frame in file.frames: file.instances(frame)
	for effect: Dictionary in effects: map._draw(effect, phases[0])
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var old_times: Array[int] = []
	var new_times: Array[int] = []
	var stable := true
	for repeat in 4:
		for legacy in [true, false]:
			var expected := old_capacity if legacy else file.visible_capacity()
			for effect: Dictionary in effects: effect.node.multimesh.instance_count = expected
			var elapsed := 0
			for frame in 12:
				var frames := phases[frame % phases.size()]
				var at := Time.get_ticks_usec()
				for effect: Dictionary in effects:
					if legacy:
						var mesh: MultiMesh = effect.node.multimesh
						var buffer := _legacy_map_buffer(file, frames)
						var count := 0
						for phase: int in frames: count += file.starts[phase + 1] - file.starts[phase]
						mesh.buffer = buffer
						mesh.visible_instance_count = count
					else: map._draw(effect, frames)
					stable = stable and effect.node.multimesh.instance_count == expected
				elapsed += Time.get_ticks_usec() - at
				await process_frame
				await RenderingServer.frame_post_draw
			(old_times if legacy else new_times).append(elapsed)
	old_times.sort()
	new_times.sort()
	print("BENCHMARK_JSON: " + JSON.stringify({"name": "map_frame_submission_" + RenderingServer.get_current_rendering_method(),
		"v3_ms": (old_times[1] + old_times[2]) / 2000.0, "v4_ms": (new_times[1] + new_times[2]) / 2000.0,
		"runs": 4, "emitters": 12, "rendered_frames_per_run": 12, "v3_capacity": old_capacity,
		"v4_capacity": file.visible_capacity(), "scope": "script CPU preparation and MultiMesh submission; real frames drained between batches; excludes waiting and hardware GPU performance"}))
	check(stable, "complete map draws retain one fixed GPU capacity through changing loop counts")
	var mesh: MultiMesh = effects[0].node.multimesh
	var data := map._frame_data(file, phases[3])
	var readback := mesh.buffer
	var expected: PackedFloat32Array = data.buffer
	var exact := readback.size() == expected.size()
	var colour_error := 0.0
	for i in mini(readback.size(), expected.size()):
		if i % 16 < 12: exact = exact and readback[i] == expected[i]
		else: colour_error = maxf(colour_error, absf(readback[i] - expected[i]))
	print("METRIC map_gpu_readback: transform_exact=%s custom_colour_max_error=%.8f capacity=%d visible=%d" % [exact, colour_error, mesh.instance_count, mesh.visible_instance_count])
	# Compatibility stores MultiMesh custom colours in reduced precision.
	# Position/size/cell transforms must stay exact; allow at most one byte
	# of colour error, never an unbounded approximate buffer comparison.
	check(exact and colour_error <= 1.0 / 255.0 and mesh.visible_instance_count == data.count, "the actual renderer receives exact transforms/cells and bounded-precision custom colours")
	var shadow := ELParticleFile.shadow_twin(effects[0].node, false)
	map._draw(effects[0], phases[1])
	check(shadow.multimesh == mesh and shadow.multimesh.visible_instance_count == map._frame_data(file, phases[1]).count,
		"shadow twins share the same stable allocation and current visible count")
	viewport.queue_free()
	await process_frame
