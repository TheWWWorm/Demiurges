extends SceneTree
## Asset-free model playback regressions and optional CPU microbenchmark.
## The reference sampler below preserves V3's byte-decoding algorithm.
## This measures synthetic animation work, not the full game's frame rate.
##
## godot --headless --path game --script ../tools/model_performance_check.gd -- --benchmark

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_keys()
	_mesh_reuse()
	_morph_playback()
	_afterimages()
	_hidden_clock()
	_workers()
	if "--benchmark" in OS.get_cmdline_user_args(): _benchmark()
	if "--render" in OS.get_cmdline_user_args(): await _render_parity()
	print("MODEL PERFORMANCE: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _track_bytes(rotations: int, positions: int, scales: int, morphs := 0, constant := false) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(12 + rotations * 16 + positions * 12 + scales * 12 + 8 + morphs * 3 * 12)
	var at := 0
	data.encode_u32(at, rotations)
	at += 4
	for index in rotations:
		var angle := 0.25 if constant else float(index) * 0.25
		var q := Quaternion(Vector3(0.3, 0.7, 0.1).normalized(), angle)
		# File order is w, x, y, z. Non-unit keys exercise normalisation.
		data.encode_float(at, q.w * 1.5)
		data.encode_float(at + 4, q.x * 1.5)
		data.encode_float(at + 8, -q.z * 1.5)
		data.encode_float(at + 12, q.y * 1.5)
		at += 16
	data.encode_u32(at, positions)
	at += 4
	for index in positions:
		var phase := 0.2 if constant else float(index) / 7.0
		data.encode_float(at, sin(phase) * 0.4)
		data.encode_float(at + 4, cos(phase) * 0.3)
		data.encode_float(at + 8, phase * 0.1)
		at += 12
	data.encode_u32(at, scales)
	at += 4
	for index in scales:
		var phase := 0.0 if constant else float(index) * 0.05
		data.encode_float(at, -1.0 - phase)
		data.encode_float(at + 4, 0.75 + phase)
		data.encode_float(at + 8, 1.25 + phase)
		at += 12
	data.encode_u32(at, morphs)
	data.encode_u32(at + 4, 3 if morphs > 0 else 0)
	at += 8
	for frame in morphs:
		for vertex in 3:
			data.encode_float(at, 0.0)
			data.encode_float(at + 4, -float(frame) * 0.1 if vertex == 2 else 0.0)
			data.encode_float(at + 8, float(frame) * 0.05)
			at += 12
	return data

func _model(track: Dictionary, count := 1) -> ELModel:
	var model := ELModel.new()
	model.clip = "cidle"
	model.idle_specials = false
	model.clips.cidle = {}
	for index in count:
		var name := "part_%d" % index
		var part := MeshInstance3D.new()
		model.add_child(part)
		model.parts[name] = part
		model.clips.cidle[name] = track
	return model

func _keys() -> void:
	check(ELFigure.track(PackedByteArray([1, 2, 3])).is_empty(), "malformed tracks are rejected before key preparation")
	var data := _track_bytes(7, 4, 3)
	var track := ELFigure.track(data)
	check(track.data == data and track.rotation_count == 7 and track.position_count == 4 and track.scale_count == 3, "preparation preserves original bytes and channel counts")
	check(track.rotation_keys.size() == 7 and track.position_keys.size() == 4 and track.scale_keys.size() == 3, "moving channels retain every authored key")
	var model := _model(track)
	var reference := _model(track)
	var positions_ok := true
	var rotations_ok := true
	var scales_ok := true
	for frame in [-3.0, 0.0, 0.01, 0.25, 0.5, 0.99, 1.0, 1.75, 2.99, 3.0, 5.5, 6.0, 20.0]:
		model.apply_frame(frame)
		_reference_apply(reference, frame)
		var actual: MeshInstance3D = model.parts.part_0
		var expected: MeshInstance3D = reference.parts.part_0
		positions_ok = positions_ok and actual.position.distance_to(expected.position) < 0.000002
		rotations_ok = rotations_ok and actual.quaternion.is_equal_approx(expected.quaternion)
		scales_ok = scales_ok and actual.scale.distance_to(expected.scale) < 0.000002
	check(positions_ok, "prepared translations match V3 at fractional keys, negative seeks and held final frames")
	check(rotations_ok, "prepared rotations match V3's normalised quaternion interpolation")
	check(scales_ok, "prepared scales preserve mirrored axes and unequal channel lengths")
	model.free()
	reference.free()
	var constant := ELFigure.track(_track_bytes(61, 61, 61, 0, true))
	check(constant.rotation_keys.size() == 1 and constant.position_keys.size() == 1 and constant.scale_keys.size() == 1, "61 repeated transform keys occupy one prepared value per channel")
	check(constant.rotation_count == 61 and constant.position_count == 61 and constant.frames == 61, "constant-channel compression does not shorten authored clip timing")
	model = _model(constant)
	reference = _model(constant)
	model.apply_frame(41.75)
	_reference_apply(reference, 41.75)
	check((model.parts.part_0 as Node3D).transform.is_equal_approx((reference.parts.part_0 as Node3D).transform), "compressed constant channels preserve their complete transform")
	model.free()
	reference.free()
	var empty := ELFigure.track(_track_bytes(0, 0, 0))
	model = _model(empty)
	var part: MeshInstance3D = model.parts.part_0
	part.rotation = Vector3(0.1, 0.3, 0.2)
	var before := part.quaternion
	part.position = Vector3(2, 3, 4)
	part.scale = Vector3(2, 2, 2)
	model.apply_frame(0.5)
	check(part.quaternion.is_equal_approx(before) and part.position == Vector3.ZERO and part.scale.is_equal_approx(Vector3.ONE), "missing channels retain rotation and reset translation/scale exactly as V3")
	model.free()
	var zeros := _track_bytes(1, 0, 0)
	for offset in [4, 8, 12, 16]: zeros.encode_float(offset, 0.0)
	check(ELFigure.track(zeros).rotation_keys[0] == Quaternion.IDENTITY, "a zero-length rotation key remains a finite identity quaternion")
	# Two instances share immutable prepared arrays; playback never edits them.
	model = _model(track)
	reference = _model(track)
	var original_keys: Array[Quaternion] = (track.rotation_keys as Array[Quaternion]).duplicate()
	model.apply_frame(1.25)
	reference.apply_frame(4.75)
	check(track.rotation_keys == original_keys and model.clips.cidle.part_0 == reference.clips.cidle.part_0, "instances share prepared keys while sampling independent poses")
	model.free()
	reference.free()

func _figure() -> Dictionary:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.4, -0.4, 0), Vector3(0.4, -0.4, 0), Vector3(0, 0.5, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
	return {"arrays": arrays, "source_indices": PackedInt32Array([0, 1, 2])}

func _playable() -> ELModel:
	var model := _model(ELFigure.track(_track_bytes(4, 4, 4, 4)))
	model.figures.part_0 = _figure()
	model._mesh_cache["base/part_0"] = ELFigure.mesh(model.figures.part_0)
	model.clips.uattack = model.clips.cidle
	model.clips.crun = {"part_0": ELFigure.track(_track_bytes(8, 8, 8))}
	model.clips.cstand = {"part_0": ELFigure.track(_track_bytes(31, 31, 31, 0, true))}
	model.clips.chold = {}
	model._animations = ELArchive.new()
	for clip: String in model.clips: model._animations.entries[clip] = Vector2i.ZERO
	return model

func _mesh_reuse() -> void:
	var model := _playable()
	var base: ArrayMesh = model._mesh_cache["base/part_0"]
	var warm := ELModel.clip_meshes(model.figures, "crun", model.clips.crun)
	check(warm.is_empty(), "worker warm-up allocates no duplicate mesh for a rigid clip")
	warm = ELModel.clip_meshes(model.figures, "cidle", model.clips.cidle)
	check(warm.size() == 1 and warm["cidle/part_0"].get_blend_shape_count() == 4, "worker warm-up still builds every actual morph frame")
	model._mesh_cache.merge(warm)
	model.play("crun")
	check(model.parts.part_0.mesh == base and not model._mesh_cache.has("crun/part_0"), "a rigid clip reuses the existing base GPU mesh")
	model.play("cstand")
	check(model.parts.part_0.mesh == base and model.clip_frames() == 31, "switching rigid clips reuses the mesh without changing the animation clock")
	model.play("cidle")
	var morph: Mesh = model.parts.part_0.mesh
	check(morph == warm["cidle/part_0"] and morph != base, "a morphing clip receives its prepared deforming mesh")
	model.apply_frame(2.4)
	model.play("crun")
	check(model.parts.part_0.mesh == base and model._previous_morphs.is_empty(), "leaving a morph clears its weights before restoring the base mesh")
	model.play("chold")
	check(model.parts.part_0.mesh == base, "a part with no track also reuses its base geometry")
	model.play("uattack")
	check(model.parts.part_0.mesh != base and model.parts.part_0.mesh.get_blend_shape_count() == 4, "a lazily entered morph clip still creates its own correct mesh")
	check(base.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == model.figures.part_0.arrays[Mesh.ARRAY_VERTEX], "clip changes leave shared base geometry untouched")
	model.free()

func _morph_playback() -> void:
	var model := _playable()
	model.play("cidle")
	var part: MeshInstance3D = model.parts.part_0
	var good := true
	for frame in [0.0, 0.25, 0.75, 1.0, 1.75, 2.9, 3.0, 15.0, 1.5, 0.0, -4.0]:
		model.apply_frame(frame)
		var at := clampf(frame, 0, 3)
		var a := int(at)
		var b := mini(a + 1, 3)
		for index in 4:
			var expected := 0.0
			if index == a: expected = 1.0 - (at - a) if a != b else 1.0
			elif index == b: expected = at - a
			good = good and is_equal_approx(part.get_blend_shape_value(index), expected)
		good = good and model._previous_morphs.part_0 == [a, b]
	check(good, "morph weights retain V3 values across interpolation, skipping, reverse seeks and wraparound")
	var pair: Array = model._previous_morphs.part_0
	model.apply_frame(2.5)
	check(pair == [2, 3], "morph playback reuses its active-frame pair instead of allocating one per sample")
	var bounds: Array = part.mesh.get_meta("morph_bounds")
	var expected := AABB((bounds[2] as AABB).position.lerp((bounds[3] as AABB).position, 0.5), (bounds[2] as AABB).size.lerp((bounds[3] as AABB).size, 0.5))
	check(model.posed_part_bounds("part_0").is_equal_approx(expected), "posed bounds still follow the same active morph pair and weights")
	model.play("uattack")
	check(is_equal_approx(part.get_blend_shape_value(0), 1.0) and is_zero_approx(part.get_blend_shape_value(2)) and is_zero_approx(part.get_blend_shape_value(3)), "a different morph clip begins without weights from its predecessor")
	model.free()

func _hidden_clock() -> void:
	var model := _playable()
	model.skip_hidden_pose = true
	model.timing.cidle = {"frames": 3, "events": [1, 2]}
	model.timing.uattack = {"frames": 3, "events": [1, 2]}
	root.add_child(model)
	model.set_process(false)
	var events: Array[String] = []
	model.frame_event.connect(func(clip: String): events.append("event:" + clip))
	model.animation_looped.connect(func(clip: String): events.append("loop:" + clip))
	model.animation_finished.connect(func(clip: String): events.append("finished:" + clip))
	model.play("cidle")
	model.set_process(false)
	model.hide()
	var sampled := model.sample_count
	model._process(2.5 / 30.0)
	check(model.sample_count == sampled and is_equal_approx(model.frame, 2.5) and events == ["event:cidle", "event:cidle"], "hidden figures retain their clock and cues without sampling geometry")
	model._process(1.0 / 30.0)
	check(is_equal_approx(model.frame, 0.5) and events.back() == "loop:cidle", "hidden looping clips keep their original wrap and signal")
	model.show()
	check(model.sample_count == sampled + 1 and not model._pose_stale, "revealing a hidden figure immediately samples its current fractional pose")
	model.play("uattack")
	model.hide()
	sampled = model.sample_count
	model._process(4.0 / 30.0)
	check(not model.playing and model.sample_count == sampled and events.back() == "finished:uattack", "hidden one-shot clips finish on time without extra pose work")
	model.show()
	check(model.sample_count == sampled + 1 and model.frame == 3.0, "revealing a finished hidden clip restores its held final pose")
	model.free()

func _afterimages() -> void:
	var model := _playable()
	root.add_child(model)
	var trail := ELMeleePlayback.MovementTrail.new()
	root.add_child(trail)
	model.parts.part_0.material_override = StandardMaterial3D.new()
	model.play("cidle")
	model.set_process(false)
	model.apply_frame(0.25)
	trail.sample(model)
	var ghost: MeshInstance3D = trail._samples[0].parts.part_0
	var frozen := ghost.transform
	model.apply_frame(2.5)
	check(ghost.get_meta("morphs") == [0, 1] and is_equal_approx(ghost.get_blend_shape_value(0), 0.75) and is_equal_approx(ghost.get_blend_shape_value(1), 0.25), "a real afterimage keeps its frozen morph indices and weights as the live figure advances")
	check(ghost.transform.is_equal_approx(frozen) and ghost.mesh == model.parts.part_0.mesh, "afterimages retain their captured transform while sharing immutable mesh geometry")
	for frame in [2.5, 1.25, 3.0]:
		trail.advance(0.05)
		model.apply_frame(frame)
		trail.sample(model)
	var clean := true
	for index in 4:
		clean = clean and is_equal_approx(ghost.get_blend_shape_value(index), 1.0 if index == 3 else 0.0)
	check(clean and ghost.get_meta("morphs") == [3, 3], "recycling an afterimage clears its own prior weights without leaving a distorted blended pose")
	check(trail._samples.size() == ELMeleePlayback.MovementTrail.SAMPLE_COUNT and trail.get_child_count() == 3, "repeated afterimages retain the existing three-snapshot node budget")
	model.play("crun")
	model.set_process(false)
	trail.advance(0.05)
	trail.sample(model)
	var rigid: MeshInstance3D = trail._samples[1].parts.part_0
	check(rigid.mesh == model._mesh_cache["base/part_0"] and (rigid.get_meta("morphs") as Array).is_empty(), "a recycled afterimage can switch from morphing to shared rigid geometry")
	model.free()
	check(is_instance_valid(ghost.mesh) and not trail.advance(1.0), "afterimages remain safe after the source is freed and finish their normal lifetime")
	trail.free()

func _workers() -> void:
	var data := _track_bytes(9, 7, 4, 4)
	var jobs: Array[Dictionary] = []
	for index in 12: jobs.append({})
	var task := WorkerThreadPool.add_group_task(func(index: int): jobs[index].track = ELFigure.track(data), jobs.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var expected := ELFigure.track(data)
	var good := true
	for job in jobs:
		good = good and job.track.rotation_keys == expected.rotation_keys and job.track.position_keys == expected.position_keys and job.track.scale_keys == expected.scale_keys and job.track.data == data
	check(good, "independent worker decodes prepare identical keys without modifying shared input")

## Original V3 sampling path, retained only as an independent regression and
## benchmark reference. It deliberately redecodes bytes for each sample.
func _reference_apply(model: ELModel, at: float) -> void:
	for name: String in model.clips.get(model.clip, {}):
		var track: Dictionary = model.clips[model.clip][name]
		var node: MeshInstance3D = model.parts[name]
		var bytes: PackedByteArray = track.data
		var rc: int = track.rotation_count
		if rc > 0:
			var f := clampf(at, 0, rc - 1)
			var a := int(f)
			var b := mini(a + 1, rc - 1)
			node.quaternion = ELFigure.quaternion(bytes, track.rotation_offset + a * 16).slerp(ELFigure.quaternion(bytes, track.rotation_offset + b * 16), f - a)
		node.position = _reference_vector(track, "position", at, Vector3.ZERO)
		node.scale = _reference_vector(track, "scale", at, Vector3.ONE, true)

func _reference_vector(track: Dictionary, field: String, at: float, default: Vector3, scaling := false) -> Vector3:
	var count: int = track[field + "_count"]
	if count == 0: return default
	var bytes: PackedByteArray = track.data
	var f := clampf(at, 0, count - 1)
	var a := int(f)
	var b := mini(a + 1, count - 1)
	var off: int = track[field + "_offset"]
	var first := Vector3(bytes.decode_float(off + a * 12), bytes.decode_float(off + a * 12 + 4), bytes.decode_float(off + a * 12 + 8))
	var second := Vector3(bytes.decode_float(off + b * 12), bytes.decode_float(off + b * 12 + 4), bytes.decode_float(off + b * 12 + 8))
	var value := first.lerp(second, f - a)
	return Vector3(value.x, value.z, value.y) if scaling else ELFigure.vector(value)

func _benchmark() -> void:
	for constant in [false, true]:
		var track := ELFigure.track(_track_bytes(61, 61, 61, 0, constant))
		var model := _model(track, 128)
		var old_times: Array[int] = []
		var new_times: Array[int] = []
		# Interleave the two paths to reduce order and clock bias. This is a
		# CPU microbenchmark of detached nodes, not a GPU or game FPS claim.
		for round_index in 7:
			for path in 2:
				var original := (round_index + path) % 2 == 0
				var start := Time.get_ticks_usec()
				for frame in 240:
					if original: _reference_apply(model, fmod(float(frame) * 0.5, 60.0))
					else: model.apply_frame(fmod(float(frame) * 0.5, 60.0))
				var elapsed := Time.get_ticks_usec() - start
				if round_index > 0:
					if original: old_times.append(elapsed)
					else: new_times.append(elapsed)
		old_times.sort()
		new_times.sort()
		var old_median := (old_times[2] + old_times[3]) * 0.5
		var new_median := (new_times[2] + new_times[3]) * 0.5
		print("METRIC: %s transforms, 128 parts x 240 poses, median of 6 interleaved runs: V3 %.3f ms; prepared %.3f ms; ratio %.4f" % ["constant" if constant else "varying", old_median / 1000.0, new_median / 1000.0, new_median / old_median])
		model.free()

func _render_parity() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	var model := _playable()
	viewport.add_child(model)
	model.set_process(false)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.albedo_color = Color(0.18, 0.8, 0.48)
	model.parts.part_0.material_override = skin
	model.play("crun")
	model.set_process(false)
	model.apply_frame(1.4)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var optimized := viewport.get_texture().get_image()
	# Replace only the geometry with the V3 duplicate allocation and sample
	# using the original byte path, so colour/depth/silhouette can be compared.
	model.parts.part_0.mesh = ELFigure.mesh(model.figures.part_0, model.clips.crun.part_0)
	_reference_apply(model, 1.4)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var reference := viewport.get_texture().get_image()
	check(optimized.get_data() == reference.get_data(), "rendered rigid geometry is pixel-identical to V3's duplicate mesh and byte sampler")
	var nonblack := 0
	for y in optimized.get_height():
		for x in optimized.get_width():
			var colour := optimized.get_pixel(x, y)
			if colour.g > colour.r * 2.0 and colour.g > 0.2: nonblack += 1
	check(nonblack > 200, "rendered parity compares a visible coloured figure, not an empty viewport")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var directory := arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(directory)
			optimized.save_png(directory.path_join("model_prepared_playback.png"))
	model.play("cidle")
	model.set_process(false)
	var morph_parity := true
	for frame in [0.35, 1.25, 3.0, 0.5]:
		model.apply_frame(frame)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		optimized = viewport.get_texture().get_image()
		_reference_apply(model, frame)
		var part: MeshInstance3D = model.parts.part_0
		# V3 cleared every old weight and then rewrote the active pair.
		for index in 4: part.set_blend_shape_value(index, 0.0)
		var a := int(frame)
		var b := mini(a + 1, 3)
		part.set_blend_shape_value(a, 1.0 - (frame - a) if a != b else 1.0)
		if a != b: part.set_blend_shape_value(b, frame - a)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		reference = viewport.get_texture().get_image()
		morph_parity = morph_parity and optimized.get_data() == reference.get_data()
	check(morph_parity, "rendered morph poses are pixel-identical to V3 through interpolation, held end and a reverse seek")
	viewport.queue_free()
	await process_frame
