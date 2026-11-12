extends SceneTree
## Headless check of the upscaling and frame generation settings
## (ELGraphicsSDK) on a stock engine: every DLSS / FSR choice is unavailable
## with a reason, saved choices from an SDK build load harmlessly, and the
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
	check(int(defaults.upscaler) == 0 and int(defaults.frame_generation) == 0 and int(defaults.fsr_version) == 4 and int(defaults.upscale_quality) == 1 and defaults.ray_reconstruction == false, "new settings start with upscaling and frame generation off")

	# Saved choices from a Windows SDK build, some out of range.
	var path := "user://graphics_sdk_check_settings.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": ELSettings.SETTINGS_VERSION, "shared": {"upscaler": 2, "frame_generation": 2, "fsr_version": 99, "upscale_quality": 7, "ray_reconstruction": true, "antialiasing": 2}}))
	file.close()
	var loaded := ELSettings.new()
	loaded.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var values := loaded.values
	check(int(values.upscaler) == 2 and int(values.frame_generation) == 2 and int(values.fsr_version) == 4 and int(values.upscale_quality) == 3 and values.ray_reconstruction == true, "saved DLSS choices load, clamped to their ranges")
	var mixed := {"upscaler": 1, "frame_generation": 2}
	check(sdk.normalize(mixed) and int(mixed.frame_generation) == 0, "DLSS Frame Generation without DLSS upscaling is switched off")
	mixed = {"upscaler": 2, "frame_generation": 1}
	check(sdk.normalize(mixed) and int(mixed.frame_generation) == 0, "AMD frame generation never goes with DLSS")
	mixed = {"upscaler": 0, "frame_generation": 1}
	check(not sdk.normalize(mixed) and int(mixed.frame_generation) == 1, "AMD frame generation works without upscaling")
	check(sdk.wanted_owner({"upscaler": 2}) == "nvidia" and sdk.wanted_owner({"frame_generation": 1}) == "amd" and sdk.wanted_owner({}) == "", "presentation owner follows the vendor")

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
		for choice: int in [1, 2]:
			var reason := sdk.upscaler_reason(choice, values)
			check(not reason.is_empty(), "upscaler %s unavailable: %s" % [sdk.UPSCALER_CHOICES[choice], reason])
			var proposed := values.duplicate()
			proposed.upscaler = choice
			reason = sdk.frame_generation_reason(choice, proposed)
			check(not reason.is_empty(), "frame generation %s unavailable: %s" % [sdk.FRAME_GENERATION_CHOICES[choice], reason])
		for version: int in [4, 3]:
			var reason := sdk.version_reason(version, values)
			check(not reason.is_empty(), "FSR %d unavailable: %s" % [version, reason])
		check(not sdk.quality_reason(values).is_empty(), "upscale quality unavailable: " + sdk.quality_reason(values))
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
