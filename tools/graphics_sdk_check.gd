extends SceneTree
## Headless check of the upscaling and frame generation settings
## (ELGraphicsSDK) on a stock engine: every DLSS / FSR choice is unavailable
## with a reason, saved choices from an SDK build load harmlessly (older files
## move to the upscaler, its quality and the frame generation switch), and the
## display options leave the window's viewport exactly as without them.
## Also: the frame-rate cap under AMD frame generation and the path tracer's
## Ray Reconstruction guide program (compiled where a rendering device exists).
##
##   godot --headless --path game --script ../tools/graphics_sdk_check.gd
##
## On an engine with the SDKs the stock-only checks are skipped.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _viewport_state(viewport: Viewport) -> Array:
	return [viewport.scaling_3d_mode, viewport.scaling_3d_scale, viewport.msaa_3d, viewport.screen_space_aa, viewport.use_taa, viewport.has_meta(ELGraphicsSDK.SAVED_SCALING)]

func _run() -> void:
	var sdk := ELGraphicsSDK
	var stock := not Engine.has_singleton("Streamline") and not Engine.has_singleton("FidelityFX")
	print("Engine %s, renderer %s/%s, %s" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), "stock" if stock else "with SDK singletons"])
	var defaults := ELSettings.new().values
	check(int(defaults.upscaler) == 0 and int(defaults.upscale_quality) == 1 and defaults.frame_generation == false and defaults.ray_reconstruction == false and not defaults.has("upscaling") and not defaults.has("fsr_version"), "new settings start with upscaling and frame generation off")

	# Saved choices from a Windows SDK build: version 4 files (frame generation
	# by vendor) and version 5 files (one "upscaling" code) move to the
	# upscaler, its quality and the frame generation switch.
	var path := "user://graphics_sdk_check_settings.json"
	var load := func(data: Dictionary) -> ELSettings:
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(data))
		out.close()
		var result := ELSettings.new()
		result.load_file(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return result
	# [file version, shared, upscaler, quality, frame generation, what]
	var cases := [
		[4, {"upscaler": 2, "frame_generation": 2, "fsr_version": 99, "upscale_quality": 7}, 2, 3, true, "DLSS Performance (quality clamped) with DLSS Frame Generation"],
		[4, {"upscaler": 2, "frame_generation": 0, "upscale_quality": 0}, 2, 0, false, "DLAA"],
		[4, {"upscaler": 1, "frame_generation": 1, "fsr_version": 3, "upscale_quality": 2}, 1, 2, true, "FSR Balanced with AMD frame generation"],
		[4, {"upscaler": 0, "frame_generation": 1, "upscale_quality": 1}, 0, 1, true, "AMD frame generation without upscaling"],
		[4, {"upscaler": 1, "frame_generation": 2, "upscale_quality": 1}, 1, 1, false, "FSR with DLSS Frame Generation (never allowed): frame generation off"],
		[4, {"upscaler": 2, "frame_generation": 1, "upscale_quality": 3}, 2, 3, false, "DLSS with AMD frame generation (never allowed): frame generation off"],
		[4, {"upscaler": "x", "frame_generation": null}, 0, 1, false, "nonsense values: off"],
		[5, {"upscaling": 22, "frame_generation": true}, 2, 2, true, "DLSS Balanced with frame generation"],
		[5, {"upscaling": 20, "frame_generation": false}, 2, 0, false, "DLAA"],
		[5, {"upscaling": 13, "frame_generation": true}, 1, 3, true, "FSR Performance with frame generation"],
		[5, {"upscaling": 0, "frame_generation": true}, 0, 1, true, "AMD frame generation without upscaling"],
		[5, {"upscaling": 99}, 0, 1, false, "a code that names no choice: off"],
		[5, {"upscaling": 15}, 0, 1, false, "a quality past Performance: off"],
	]
	for item: Array in cases:
		var shared: Dictionary = item[1].duplicate()
		shared.ray_reconstruction = true
		var migrated: Dictionary = load.call({"version": item[0], "shared": shared}).values
		check(int(migrated.upscaler) == item[2] and int(migrated.upscale_quality) == item[3] and migrated.frame_generation == item[4] and migrated.ray_reconstruction == true and not migrated.has("upscaling"),
			"version %d file: %s -> upscaler %d, quality %d, frame generation %s" % [item[0], item[5], item[2], item[3], item[4]])
	var flat: Dictionary = load.call({"upscaler": 1, "frame_generation": 1, "upscale_quality": 0}).values
	check(int(flat.upscaler) == 1 and int(flat.upscale_quality) == 0 and flat.frame_generation == true, "a file without a version (flat keys) migrates too")
	var loaded: ELSettings = load.call({"version": ELSettings.SETTINGS_VERSION, "shared": {"upscaler": 2, "upscale_quality": 1, "frame_generation": true, "ray_reconstruction": true, "antialiasing": 2}})
	var values := loaded.values
	check(int(values.upscaler) == 2 and int(values.upscale_quality) == 1 and values.frame_generation == true and values.ray_reconstruction == true, "saved version %d choices load as they are" % ELSettings.SETTINGS_VERSION)
	for wrong: Variant in [9, -3, 3]:
		check(int(load.call({"version": ELSettings.SETTINGS_VERSION, "shared": {"upscaler": wrong}}).values.upscaler) == 0, "an upscaler value %s that names no vendor loads as off" % wrong)
	check(int(load.call({"version": ELSettings.SETTINGS_VERSION, "shared": {"upscale_quality": 9}}).values.upscale_quality) == 3, "a quality past Performance is clamped")
	loaded.save_file(path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(int(saved.version) == ELSettings.SETTINGS_VERSION and not saved.shared.has("upscaling") and not saved.shared.has("fsr_version") and int(saved.shared.upscaler) == 2 and int(saved.shared.upscale_quality) == 1 and saved.shared.frame_generation == true, "saved files keep only the current keys")

	# What the choices mean.
	check(sdk.UPSCALERS == [sdk.OFF, sdk.NVIDIA, sdk.AMD], "the upscaler list: Off, NVIDIA DLSS, AMD FSR")
	check(sdk.upscaler_of({"upscaler": 2}) == sdk.NVIDIA and sdk.upscaler_of({"upscaler": 7}) == sdk.OFF and sdk.quality_of({"upscale_quality": 2}) == 2 and sdk.quality_of({}) == 1, "vendor and quality")
	check(sdk.generation_of({"upscaler": 2, "frame_generation": true}) == sdk.NVIDIA and sdk.generation_of({"upscaler": 1, "frame_generation": true}) == sdk.AMD and sdk.generation_of({"upscaler": 0, "frame_generation": true}) == sdk.AMD and sdk.generation_of({"upscaler": 2, "frame_generation": false}) == sdk.OFF, "frame generation follows the upscaler's vendor (AMD without upscaling)")
	check(sdk.upscaler_name(sdk.OFF) == "Off" and sdk.upscaler_name(sdk.NVIDIA) == "NVIDIA DLSS" and sdk.quality_name(0, sdk.NVIDIA) == "DLAA" and sdk.quality_name(0, sdk.AMD) == "Native AA" and sdk.quality_name(2, sdk.AMD) == "Balanced", "upscaler and quality names")
	if stock: check(sdk.upscaler_name(sdk.AMD) == "AMD FSR", "FSR names no version the SDK has not reported")
	var mixed := {"upscaler": 5}
	check(sdk.normalize(mixed) and int(mixed.upscaler) == 0, "an upscaler value that names no vendor becomes off")
	check(sdk.wanted_owner({"upscaler": 2}) == "nvidia" and sdk.wanted_owner({"frame_generation": true}) == "amd" and sdk.wanted_owner({"upscaler": 1}) == "amd" and sdk.wanted_owner({}) == "", "presentation owner follows the vendor")
	check(sdk.restart_message({}, {"frame_generation": true}) == "" or not stock, "stock engine: no restart message")

	# Reasons and frame counting do not depend on the engine.
	var meter := ELGraphicsSDK.FrameMeter.new()
	var state := {"frame_generation_active": true, "presented_frames": 1000, "game_presents": 500}
	check(meter.sample(state, 1_000_000, 60).presented_fps < 0, "first sample does not invent a presented frame rate")
	state.presented_frames += 45
	state.game_presents += 30
	var rates := meter.sample(state, 1_500_000, 60)
	check(is_equal_approx(rates.presented_fps, 90) and is_equal_approx(rates.rendered_fps, 60) and ELGraphicsSDK.FrameMeter.label_text(rates) == "90 FPS (60 rendered)", "presented and rendered frame rates come from the counters, not an assumed doubling")
	state.frame_generation_active = false
	check(ELGraphicsSDK.FrameMeter.label_text(meter.sample(state, 2_000_000, 44)) == "44 FPS", "without frame generation the counter shows the engine's frame rate")

	# AMD frame generation's frame-rate cap against the player's Frame rate.
	check(sdk.frame_rate_cap(0, 0) == 0 and sdk.frame_rate_cap(-1, 0) == 0 and sdk.frame_rate_cap(144, 0) == 144, "no recommendation: the player's cap stays (V-Sync and unlimited are 0)")
	check(sdk.frame_rate_cap(0, 71) == 71 and sdk.frame_rate_cap(-1, 71) == 71 and sdk.frame_rate_cap(240, 71) == 71, "frame generation caps V-Sync, unlimited and higher caps to the recommendation")
	check(sdk.frame_rate_cap(50, 71) == 50, "a lower player cap is kept under frame generation")

	# The Ray Reconstruction guide program: only the define differs from the
	# ordinary smoothing program, which keeps its exact source.
	var shaders := preload("res://src/render/path_trace_shaders.gd")
	var guides: String = shaders.FILTER.replace("#version 460\n", "#version 460\n#define RAY_RECONSTRUCTION\n")
	check(guides != shaders.FILTER and guides.count("#define RAY_RECONSTRUCTION") == 1, "the guide program adds its define once")
	check(not shaders.FILTER.contains("#define RAY_RECONSTRUCTION") and shaders.FILTER.count("#ifdef RAY_RECONSTRUCTION") == 4, "the ordinary smoothing program leaves every guide block out")
	var rd := RenderingServer.get_rendering_device()
	if rd != null:
		for source: String in [shaders.FILTER, guides]:
			var program := RDShaderSource.new()
			program.source_compute = source
			var spirv := rd.shader_compile_spirv_from_source(program)
			check(spirv.compile_error_compute.is_empty(), "%s compiles: %s" % ["guide program" if source == guides else "smoothing program", spirv.compile_error_compute])
	else:
		print("No rendering device: shader compilation skipped.")

	if not stock:
		print("SDK singletons present: stock-engine checks skipped.")
		print("Ray Reconstruction inputs: %s; reason with DLSS and path tracing: '%s'" % [sdk.ray_reconstruction_compiled(), sdk.ray_reconstruction_reason({"upscaler": 2, "ray_reconstruction": true})])
		print("Running owner: %s" % sdk.OWNER_NAMES[sdk.running_owner()])
	else:
		check(not sdk.engine_has_sdk() and not sdk.compiled(sdk.AMD) and not sdk.compiled(sdk.NVIDIA), "stock engine: no SDK compiled")
		check(sdk.running_owner() == sdk.OFF, "stock engine: no presentation owner")
		for vendor: int in [sdk.NVIDIA, sdk.AMD]:
			var reason := sdk.upscaling_reason(vendor)
			check(not reason.is_empty(), "upscaler %s unavailable: %s" % [sdk.upscaler_name(vendor), reason])
			var proposed := values.duplicate()
			proposed.upscaler = vendor
			proposed.frame_generation = true
			reason = sdk.frame_generation_reason(proposed)
			check(not reason.is_empty(), "frame generation with %s unavailable: %s" % [sdk.upscaler_name(vendor), reason])
		check(not sdk.frame_generation_reason({"upscaler": 0, "frame_generation": true}).is_empty(), "frame generation without upscaling unavailable: " + sdk.frame_generation_reason({"upscaler": 0}))
		check(sdk.fsr_version("sr") == 0 and sdk.fsr_version("fg") == 0, "stock engine: no FSR version reported")
		check(sdk.restart_message({}, values).is_empty(), "stock engine: no restart message")
		check(sdk.active_upscaler(values) == sdk.OFF and sdk.available_frame_generation(values) == sdk.OFF, "saved DLSS choices stay unused")
		check(not sdk.ray_reconstruction_compiled() and sdk.ray_reconstruction_reason(values) == sdk.NO_NVIDIA, "Ray Reconstruction unavailable: " + sdk.ray_reconstruction_reason(values))
		check(not sdk.ray_reconstruction_active(values), "saved Ray Reconstruction stays unused")
		var tracer := ELPathTracing.new()
		tracer.settings = loaded
		check(not tracer._ray_reconstruction(), "the path tracer asks for no Ray Reconstruction")
		tracer.free()
		check(not ClassDB.class_has_method("RenderSceneBuffersRD", "set_dlss_ray_reconstruction"), "stock engine: no Ray Reconstruction inputs")
		check(not sdk.needs_restart(values) and not sdk.needs_forward_plus(values), "saved DLSS choices ask for no restart and no renderer change")
		check(not sdk.write_owner_file(values), "stock engine: the owner file is not written")
		check(sdk.credits_bbcode().is_empty(), "stock engine: no SDK credits or About page")

		# The window's viewport with and without the saved SDK choices.
		var plain := ELSettings.new().values
		plain.antialiasing = 2
		ELSettings.apply_display(root, plain)
		var before := _viewport_state(root)
		ELSettings.apply_display(root, values)
		check(_viewport_state(root) == before, "apply_display with saved DLSS choices leaves the viewport as without them %s" % [before])
		sdk.apply_upscaling(root, values)
		check(_viewport_state(root) == before, "apply_upscaling leaves the stock viewport unchanged")
		var fps_before := Engine.max_fps
		var node := ELGraphicsSDK.new()
		node.settings = loaded
		root.add_child(node)
		await process_frame
		check(not node.is_processing(), "stock engine: no per-frame work")
		check(Engine.max_fps == fps_before, "stock engine: the frame-rate cap is left alone")
		check(root.get("frame_generation") == null, "stock engine: the viewport has no frame generation property")
		node.queue_free()

	print("%d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)
