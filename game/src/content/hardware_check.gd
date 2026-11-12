class_name ELHardwareCheck
extends Node
## The first start's hardware check, run once per installation:
## 1. On the Compatibility renderer, a small off-screen copy of the game is
##    started on Forward+ (Vulkan). When it really runs on Vulkan, the game
##    switches to Forward+ and starts again (path tracing and the other
##    Forward+ features need it).
## 2. On the renderer it then runs, a battlefield is drawn off-screen with
##    shadows and terrain detail, and the optional extras the GPU can keep
##    at 60 frames per second are switched on.
## The settings' "hardware_check" records the stage reached (0 none, 1
## renderer chosen, 2 done), so a player's own later choices are never
## overridden.

signal finished(restart: bool)

const PROBE_ARG := "--renderer-probe="
const PROBE_SECONDS := 15.0
## GPU milliseconds per frame (shadows and terrain detail at the window's
## size) under which the extras are switched on.
const FULL_BUDGET_MS := 7.0
const BASIC_BUDGET_MS := 11.0

var settings: ELSettings
var profile: ELProfile
var _probe_file := ""
var _probe_pid := -1
var _probe_started := 0.0
var _bench: SubViewport
var _bench_frames := 0
var _gpu_times: PackedFloat32Array = []
var _frame_times: PackedFloat32Array = []
var _last_tick := 0

## The probe copy of the game: reports its renderer and quits. True when this
## process is one (the caller then does nothing else).
static func run_probe(tree: SceneTree) -> bool:
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(PROBE_ARG): path = arg.trim_prefix(PROBE_ARG)
	if path.is_empty(): return false
	tree.root.get_window().mode = Window.MODE_WINDOWED
	_report_probe.call_deferred(tree, path)
	return true

static func _report_probe(tree: SceneTree, path: String) -> void:
	# A few frames so the device has really drawn.
	for i in 3: await tree.process_frame
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name()}))
		file.close()
	tree.quit()

## The command-line options that start the game on the chosen renderer.
## The Vulkan choice is Forward+ on a computer; phones and tablets get the
## engine's Mobile renderer, its Vulkan renderer for those GPUs (Forward+
## is not made for them and can end the game at its first battlefield).
static func renderer_args(vulkan: bool, mobile := OS.has_feature("mobile")) -> PackedStringArray:
	if not vulkan: return PackedStringArray(["--rendering-method", "gl_compatibility"])
	return PackedStringArray(["--rendering-method", "mobile" if mobile else "forward_plus", "--rendering-driver", "vulkan"])

## Whether the check still has work on this start.
static func pending(preferences: ELSettings) -> bool:
	# Forced from the command line (checks, or a player redoing it).
	if OS.get_cmdline_user_args().has("--hardware-check"): return int(preferences.values.get("hardware_check", 0)) < 2 or not OS.get_cmdline_user_args().has("--renderer-restarted")
	if OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("editor"): return false
	if OS.get_cmdline_args().has("--rendering-method") and not OS.get_cmdline_user_args().has("--renderer-restarted"): return false
	return int(preferences.values.get("hardware_check", 0)) < 2

## Starts the stage this start needs; `finished` follows.
func begin(args_for_restart: Callable) -> void:
	if int(settings.values.get("hardware_check", 0)) == 0:
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			_renderer_chosen()
		else:
			_start_probe(args_for_restart)
		return
	_start_bench()

func _start_probe(_args_for_restart: Callable) -> void:
	_probe_file = ProjectSettings.globalize_path("user://renderer_probe.json")
	DirAccess.remove_absolute(_probe_file)
	var args := PackedStringArray()
	if not OS.has_feature("template"): args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "--audio-driver", "Dummy",
		"--windowed", "--resolution", "64x64", "--position", "-4000,-4000", "--", PROBE_ARG + _probe_file])
	_probe_pid = OS.create_process(OS.get_executable_path(), args)
	_probe_started = Time.get_ticks_msec() / 1000.0
	if _probe_pid <= 0: _renderer_chosen()

func _process(_delta: float) -> void:
	if _probe_pid > 0:
		_poll_probe()
	elif _bench != null:
		_step_bench()

func _poll_probe() -> void:
	var waited := Time.get_ticks_msec() / 1000.0 - _probe_started
	var report := FileAccess.get_file_as_string(_probe_file) if FileAccess.file_exists(_probe_file) else ""
	var result: Variant = JSON.parse_string(report) if not report.is_empty() else null
	if result is not Dictionary and waited < PROBE_SECONDS and OS.is_process_running(_probe_pid): return
	if OS.is_process_running(_probe_pid): OS.kill(_probe_pid)
	_probe_pid = -1
	DirAccess.remove_absolute(_probe_file)
	var vulkan: bool = result is Dictionary and String(result.get("method", "")) == "forward_plus" and String(result.get("driver", "")) == "vulkan"
	print("Hardware check: Vulkan ", "available on " + String(result.get("adapter", "")) if vulkan else "unavailable")
	if vulkan and int(settings.values.renderer) == 0:
		settings.values.renderer = 1
		settings.values.hardware_check = 1
		settings.save_file()
		finished.emit(true)
		return
	_renderer_chosen()

func _renderer_chosen() -> void:
	settings.values.hardware_check = 1
	settings.save_file()
	_start_bench()

## Draws a battlefield off-screen with the extras on and times the GPU.
func _start_bench() -> void:
	if profile == null or not profile.table("CombatSceneDB").has("Green.001"):
		_done({})
		return
	_bench = SubViewport.new()
	_bench.size = get_viewport().get_visible_rect().size
	_bench.own_world_3d = true
	_bench.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bench)
	var arena := ELArena.new()
	_bench.add_child(arena)
	if not arena.build(profile, "Green.001"):
		_done({})
		return
	arena.light.shadow_enabled = true
	arena.light.shadow_blur = 2.0
	arena.set_detail(true)
	var camera := Camera3D.new()
	camera.environment = arena.environment_settings
	_bench.add_child(camera)
	camera.position = Vector3(0, 11, 17)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	RenderingServer.viewport_set_measure_render_time(_bench.get_viewport_rid(), true)
	_bench_frames = 0
	_last_tick = Time.get_ticks_usec()

func _step_bench() -> void:
	_bench_frames += 1
	var now := Time.get_ticks_usec()
	# The first frames compile shaders and upload textures.
	if _bench_frames > 30:
		_gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(_bench.get_viewport_rid()))
		_frame_times.append((now - _last_tick) / 1000.0)
	_last_tick = now
	if _bench_frames < 150: return
	var gpu := _median(_gpu_times)
	var frame := _median(_frame_times)
	_bench.queue_free()
	_bench = null
	_done({"gpu": gpu, "frame": frame})

static func _median(values: PackedFloat32Array) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func _done(result: Dictionary) -> void:
	var gpu := float(result.get("gpu", 0.0))
	# Without GPU timing (some drivers), the whole frame stands in for it;
	# it includes the rest of the game, so the budget is looser.
	var cost := gpu if gpu > 0.0 else maxf(0.0, float(result.get("frame", 0.0)) - 6.0)
	if not result.is_empty() and cost > 0.0:
		if cost <= FULL_BUDGET_MS:
			for key: String in ["shadows", "soft_shadows", "terrain_detail", "enhanced_water"]: settings.values[key] = true
		elif cost <= BASIC_BUDGET_MS:
			for key: String in ["shadows", "terrain_detail", "enhanced_water"]: settings.values[key] = true
		print("Hardware check: %.1f ms per frame (GPU %.1f ms); extras %s" % [float(result.frame), gpu,
			"all on" if cost <= FULL_BUDGET_MS else ("partly on" if cost <= BASIC_BUDGET_MS else "unchanged")])
	settings.values.hardware_check = 2
	settings.save_file()
	finished.emit(false)
