class_name ELGraphicsSDK
extends Node
## Optional NVIDIA DLSS and AMD FSR upscaling and frame generation, for the
## Windows build whose engine includes the vendors' SDKs (Forward+ on Vulkan).
## Everything here goes through Engine.get_singleton, ClassDB constants and
## Object.set, so it parses and stays inert on stock Godot: the Compatibility
## renderer, the browser, Android, Linux, macOS and ordinary Windows builds
## see every choice as unavailable and their viewport is never touched.
##
## Settings (shared, see ELSettings): "upscaler" (0 off, 1 AMD FSR, 2 NVIDIA
## DLSS), "fsr_version" (4 or 3 for FSR 3.1; AMD upscaling and frame
## generation), "upscale_quality" (0 full-resolution AA / DLAA, 1 Quality, 2 Balanced,
## 3 Performance), "frame_generation" (0 off, 1 AMD FSR, 2 NVIDIA DLSS) and
## "ray_reconstruction" (DLSS Ray Reconstruction in place of the path
## tracer's own smoothing, see ELPathTracing). A setting is a request: only
## the SDK's own status says whether it renders.
##
## One vendor owns presentation per start. The engine reads the owner from
## OWNER_FILE when it starts; the game writes it, and a change of owner needs
## a restart. DLSS Frame Generation needs DLSS upscaling; AMD frame
## generation works with or without FSR upscaling; the vendors never mix.
##
## As a node (a child of the game) it switches frame generation on only
## while a map or battle is on screen: not in menus, loading screens or
## movies, while paused or when the window loses focus. While AMD frame
## generation runs it caps the frame rate below half the display's refresh
## rate as the SDK recommends (Vulkan has no frame latency object), keeping a
## lower cap of the player's, and returns the player's cap when it stops.

const OFF := 0
const AMD := 1
const NVIDIA := 2
const OWNER_FILE := "user://graphics_sdk.cfg"
const STATUS_FILE := "user://graphics-sdk-status.json"
const OWNER_NAMES := ["", "amd", "nvidia"]
## Render scale per "upscale_quality".
const FSR_SCALES := [1.0, 1.0 / 1.5, 1.0 / 1.7, 0.5]
const DLSS_SCALES := [1.0, 2.0 / 3.0, 0.58, 0.5]
## Streamline.set_parameter: NVIDIA Reflex mode.
const REFLEX_MODE := 0
## Viewport meta: the scaling the viewport had before an SDK upscaler.
const SAVED_SCALING := &"graphics_sdk_saved_scaling"

const UPSCALING_HELP := "Renders the 3D map and battle scenes at a lower resolution and rebuilds the picture with AMD FSR or NVIDIA DLSS, which also smooth edges in place of Anti-aliasing. Switching between AMD and NVIDIA takes a restart."
const VERSION_HELP := "Which AMD FSR to use for upscaling and frame generation. FSR 4 needs a supported Radeon GPU; FSR 3.1 also runs on other GPUs."
const QUALITY_HELP := "Native AA keeps the full resolution (DLAA with NVIDIA DLSS). Quality, Balanced and Performance render fewer pixels for a higher frame rate."
const FRAME_GENERATION_HELP := "Adds generated frames between the rendered ones on maps and in battles. It pauses in menus, loading screens and movies and while the window is in the background. NVIDIA needs DLSS upscaling and turns on NVIDIA Reflex. The frame rate counter then shows the frames shown and the frames rendered."
const UPSCALER_CHOICES :=["Off", "AMD FSR Upscaling", "NVIDIA DLSS"]
const VERSION_CHOICES := ["FSR 4", "FSR 3.1"]
const VERSION_VALUES := [4, 3]
const QUALITY_CHOICES := ["Native AA (DLAA with NVIDIA DLSS)", "Quality", "Balanced", "Performance"]
const FRAME_GENERATION_CHOICES := ["Off", "AMD FSR Frame Generation", "NVIDIA DLSS Frame Generation"]
const RAY_RECONSTRUCTION_HELP := "With NVIDIA DLSS upscaling, the path-traced light goes unsmoothed to DLSS Ray Reconstruction, which removes its noise in place of the path tracer's own smoothing and keeps moving light and shadows sharper."

const NO_NVIDIA := "This build does not include NVIDIA DLSS."
const NO_AMD := "This build does not include AMD FSR."
const NEED_API := "Needs Windows and the Forward+ (Vulkan) renderer: choose Forward+ (Vulkan) above and restart."
const NEED_RESTART := "Restart the game to switch between AMD and NVIDIA."
const NEED_DLSS := "NVIDIA DLSS is not available on this GPU or driver, or its runtime could not be loaded."
const NEED_DLSS_FG := "DLSS Frame Generation is not available: it needs a GeForce RTX 40 series or newer GPU, a current driver and Windows hardware-accelerated GPU scheduling."
const NEED_FSR4 := "FSR 4 is not available on this GPU or driver. Choose FSR 3.1."
const NEED_FSR3 := "FSR 3.1 is not available on this GPU or driver, or its runtime could not be loaded."
const NEED_FSR4_FG := "FSR 4 frame generation needs Windows 11 and a Radeon RX 9000 series or newer GPU. Choose FSR 3.1."
const NEED_FSR3_FG := "AMD FSR Frame Generation is not available on this GPU or driver."
const NEED_DLSS_UPSCALING := "Choose NVIDIA DLSS upscaling first."
const NEED_UPSCALER := "Choose AMD FSR or NVIDIA DLSS upscaling first."
const NO_MIXING := "NVIDIA DLSS and AMD FSR cannot be used together."
const FAILED := "Stopped after an error. Restart the game to try again."
const NO_RR := "This build's NVIDIA DLSS does not include Ray Reconstruction."
const NEED_RR := "DLSS Ray Reconstruction is not available on this GPU or driver, or its runtime could not be loaded."
const NEED_PATH_TRACING := "Switch on path-traced lighting first."

## The owner the engine started with when it does not say (read once).
static var _startup_owner := ""
static var _startup_read := false

# --- What the running engine offers ------------------------------------------

static func streamline() -> Object:
	return Engine.get_singleton("Streamline") if Engine.has_singleton("Streamline") else null

static func fidelityfx() -> Object:
	return Engine.get_singleton("FidelityFX") if Engine.has_singleton("FidelityFX") else null

static func _bridge(vendor: int) -> Object:
	return streamline() if vendor == NVIDIA else fidelityfx() if vendor == AMD else null

## The SDK's status dictionary, or an empty one.
static func status(vendor: int) -> Dictionary:
	var native := _bridge(vendor)
	if native == null or not native.has_method("get_status"): return {}
	var value: Variant = native.call("get_status")
	return value if value is Dictionary else {}

## The engine has the vendor's SDK compiled in (whatever the GPU).
static func compiled(vendor: int) -> bool:
	var constant := "SCALING_3D_MODE_DLSS" if vendor == NVIDIA else "SCALING_3D_MODE_FSR_SDK"
	return _bridge(vendor) != null and ClassDB.class_has_integer_constant("Viewport", constant) and bool(status(vendor).get("compiled", false))

## Either SDK is compiled in.
static func engine_has_sdk() -> bool:
	return compiled(AMD) or compiled(NVIDIA)

## Windows, Forward+ and Vulkan, with a window.
static func platform_ready() -> bool:
	return DisplayServer.get_name() != "headless" and OS.get_name() == "Windows" \
		and RenderingServer.get_current_rendering_method() == "forward_plus" \
		and RenderingServer.get_current_rendering_driver_name() == "vulkan"

## The vendor owning presentation in this run: NVIDIA, AMD or OFF.
static func running_owner() -> int:
	# The engine names the owner it started with ("" for none).
	var amd := status(AMD)
	if amd.has("requested_owner"):
		var requested := OWNER_NAMES.find(str(amd.requested_owner))
		return requested if requested > 0 else OFF
	for vendor: int in [NVIDIA, AMD]:
		var state := status(vendor)
		if state.has("requested"):
			if bool(state.requested): return vendor
	if not _startup_read:
		_startup_read = true
		_startup_owner = read_owner_file()
		for arg: String in OS.get_cmdline_args():
			if arg.begins_with("--graphics-sdk="): _startup_owner = arg.trim_prefix("--graphics-sdk=")
	var named := OWNER_NAMES.find(_startup_owner)
	# A vendor whose status reports the request flag has already answered.
	if named > 0 and not status(named).has("requested"): return named
	return OFF

static func _fsr_version(values: Dictionary) -> int:
	return 3 if int(values.get("fsr_version", 4)) == 3 else 4

## Facts about one vendor in this run.
static func facts(vendor: int) -> Dictionary:
	var state := status(vendor)
	var result := {"engine": compiled(vendor), "api": platform_ready(), "owner": running_owner() == vendor,
		"runtime_error": bool(state.get("initialized", false)) and int(state.get("last_error", 0)) != 0}
	if vendor == NVIDIA:
		# Before Streamline is set up, its setup reason says why; frame
		# generation also needs it to own presentation.
		var ready := bool(state.get("initialized", false))
		var setup := str(state.get("init_reason", ""))
		var owns := bool(state.get("owner", true))
		var generation := bool(state.get("fg_supported", false))
		result.sr = bool(state.get("sr_supported", false))
		result.fg = generation and bool(state.get("reflex_supported", false)) and owns
		result.rr = bool(state.get("rr_supported", false))
		result.rr_error = int(state.get("rr_last_error", 0)) != 0
		result.sr_reason = str(state.get("sr_support_reason", "")) if ready else setup
		result.rr_reason = str(state.get("rr_support_reason", "")) if ready else setup
		if not ready or not owns: result.fg_reason = setup
		elif not generation: result.fg_reason = str(state.get("fg_support_reason", ""))
		else: result.fg_reason = str(state.get("reflex_support_reason", ""))
	else:
		# A runtime that did not load says why in place of each feature; frame
		# generation also needs FidelityFX to own presentation.
		var loaded := bool(state.get("runtime_loaded", true))
		var presents := bool(state.get("presentation_owner", true))
		for key: String in ["sr3", "sr4", "fg3", "fg4"]:
			result[key] = bool(state.get(key + "_supported", false))
			var reason := str(state.get(key + "_reason", state.get(key + "_support_reason", "")))
			if not loaded and state.has("runtime_reason"): reason = str(state.runtime_reason)
			elif key.begins_with("fg") and not presents:
				result[key] = false
				reason = str(state.get("presentation_owner_reason", reason))
			result[key + "_reason"] = reason
	return result

## A reason with the SDK's own words after it (kept apart by " · ", so the
## translated part and the SDK's English stay separate).
static func _with(reason: String, detail: String) -> String:
	return reason if detail.is_empty() else reason + " · " + detail

## Whether a restart must use Forward+ on Vulkan for these choices.
static func needs_forward_plus(values: Dictionary) -> bool:
	return OS.get_name() == "Windows" and engine_has_sdk() and not wanted_owner(values).is_empty()

# --- Reasons a choice cannot be used ----------------------------------------

## Why upscaler `choice` cannot be chosen with `values` ("" when it can; a
## choice for the vendor not owning this run can be chosen and asks for a
## restart).
static func upscaler_reason(choice: int, values: Dictionary) -> String:
	if choice == OFF: return ""
	var info := facts(choice)
	if not info.engine: return NO_NVIDIA if choice == NVIDIA else NO_AMD
	if not info.api: return NEED_API
	if not info.owner: return ""
	if choice == NVIDIA:
		if not info.sr: return FAILED if info.runtime_error else _with(NEED_DLSS, info.sr_reason)
		return ""
	var version := _fsr_version(values)
	if not info["sr%d" % version]:
		if info.runtime_error: return FAILED
		return _with(NEED_FSR4 if version == 4 else NEED_FSR3, info["sr%d_reason" % version])
	return ""

## Why frame generation `choice` cannot be chosen with `values`.
static func frame_generation_reason(choice: int, values: Dictionary) -> String:
	if choice == OFF: return ""
	var upscaler := int(values.get("upscaler", OFF))
	var info := facts(choice)
	if not info.engine: return NO_NVIDIA if choice == NVIDIA else NO_AMD
	if not info.api: return NEED_API
	if choice == NVIDIA and upscaler != NVIDIA: return NEED_DLSS_UPSCALING
	if choice == AMD and upscaler == NVIDIA: return NO_MIXING
	if not info.owner: return ""
	if choice == NVIDIA:
		if not info.sr: return FAILED if info.runtime_error else _with(NEED_DLSS, info.sr_reason)
		if not info.fg: return FAILED if info.runtime_error else _with(NEED_DLSS_FG, info.fg_reason)
		return ""
	var version := _fsr_version(values)
	if not info["fg%d" % version]:
		if info.runtime_error: return FAILED
		return _with(NEED_FSR4_FG if version == 4 else NEED_FSR3_FG, info["fg%d_reason" % version])
	return ""

## Why the FSR version `version` (4 or 3) cannot be chosen.
static func version_reason(version: int, values: Dictionary) -> String:
	var proposed := values.duplicate()
	proposed.fsr_version = version
	var upscaler := int(values.get("upscaler", OFF))
	var generation := int(values.get("frame_generation", OFF))
	if upscaler != AMD and generation != AMD: return upscaler_reason(AMD, proposed)
	var reason := upscaler_reason(AMD, proposed) if upscaler == AMD else ""
	if reason.is_empty() and generation == AMD: reason = frame_generation_reason(AMD, proposed)
	return reason

## Why the quality choice cannot be changed.
static func quality_reason(values: Dictionary) -> String:
	var upscaler := int(values.get("upscaler", OFF))
	return NEED_UPSCALER if upscaler == OFF else upscaler_reason(upscaler, values)

## The engine takes Ray Reconstruction guides from scripts.
static func ray_reconstruction_compiled() -> bool:
	return compiled(NVIDIA) and ClassDB.class_has_method("RenderSceneBuffersRD", "set_dlss_ray_reconstruction") \
		and ClassDB.class_has_method("RenderSceneDataRD", "get_ray_projection")

## Why DLSS Ray Reconstruction cannot be chosen with `values` ("" when it
## can). `path_tracing`: the path tracer is available and switched on.
static func ray_reconstruction_reason(values: Dictionary, path_tracing := true) -> String:
	var info := facts(NVIDIA)
	if not info.engine: return NO_NVIDIA
	if not ray_reconstruction_compiled(): return NO_RR
	if not info.api: return NEED_API
	if not path_tracing: return NEED_PATH_TRACING
	if int(values.get("upscaler", OFF)) != NVIDIA: return NEED_DLSS_UPSCALING
	# DLSS chosen for the next start: the upscaling row offers the restart.
	if not info.owner: return ""
	var upscaling := upscaler_reason(NVIDIA, values)
	if not upscaling.is_empty(): return upscaling
	if not info.rr: return FAILED if info.rr_error else _with(NEED_RR, info.rr_reason)
	return ""

## Ray Reconstruction is chosen and can run now (DLSS upscaling rendering).
static func ray_reconstruction_active(values: Dictionary) -> bool:
	return bool(values.get("ray_reconstruction", false)) and active_upscaler(values) == NVIDIA \
		and ray_reconstruction_reason(values).is_empty()

## The frame-rate cap with AMD frame generation recommending
## `recommended` (0: none): the lower of it and the player's cap
## (`user_rate`: 0 V-Sync, -1 unlimited, otherwise a cap). Engine.max_fps.
static func frame_rate_cap(user_rate: int, recommended: int) -> int:
	if recommended <= 0: return maxi(0, user_rate)
	return recommended if user_rate <= 0 else mini(user_rate, recommended)

## Settings that cannot go together are set apart: DLSS Frame Generation
## without DLSS, AMD frame generation with DLSS. Returns whether any changed.
static func normalize(values: Dictionary) -> bool:
	var upscaler := int(values.get("upscaler", OFF))
	var generation := int(values.get("frame_generation", OFF))
	if (generation == NVIDIA and upscaler != NVIDIA) or (generation == AMD and upscaler == NVIDIA):
		values.frame_generation = OFF
		return true
	return false

# --- Presentation owner ------------------------------------------------------

## The vendor `values` need to own presentation ("" for none).
static func wanted_owner(values: Dictionary) -> String:
	var upscaler := int(values.get("upscaler", OFF))
	var generation := int(values.get("frame_generation", OFF))
	if upscaler == NVIDIA or generation == NVIDIA: return "nvidia"
	if upscaler == AMD or generation == AMD: return "amd"
	return ""

static func read_owner_file() -> String:
	var config := ConfigFile.new()
	if config.load(OWNER_FILE) != OK: return ""
	var owner := str(config.get_value("startup", "owner", ""))
	return owner if owner in OWNER_NAMES else ""

## Writes the owner the next start sets up; only on an engine with an SDK.
## Returns whether the file changed.
static func write_owner_file(values: Dictionary) -> bool:
	if not engine_has_sdk(): return false
	var owner := wanted_owner(values)
	if FileAccess.file_exists(OWNER_FILE) and read_owner_file() == owner: return false
	var config := ConfigFile.new()
	config.set_value("startup", "owner", owner)
	return config.save(OWNER_FILE) == OK

## The choices need another presentation owner than this run's.
static func needs_restart(values: Dictionary) -> bool:
	if not engine_has_sdk() or not platform_ready(): return false
	var owner := wanted_owner(values)
	if owner.is_empty(): return false
	var vendor := OWNER_NAMES.find(owner)
	return compiled(vendor) and running_owner() != vendor

## The upscaler rendering now: AMD, NVIDIA or OFF.
static func active_upscaler(values: Dictionary) -> int:
	var choice := int(values.get("upscaler", OFF))
	if choice == OFF or running_owner() != choice: return OFF
	return choice if upscaler_reason(choice, values).is_empty() else OFF

## Frame generation the settings allow now (ignoring what is on screen).
static func available_frame_generation(values: Dictionary) -> int:
	var choice := int(values.get("frame_generation", OFF))
	if choice == OFF or running_owner() != choice: return OFF
	return choice if frame_generation_reason(choice, values).is_empty() else OFF

# --- Applying ----------------------------------------------------------------

## The window's viewport takes the chosen SDK upscaler (after the ordinary
## display options were applied: multisampling and screen-space smoothing
## give way to it). Sub-viewports and stock engines are left alone, and the
## previous scaling returns when the upscaler stops.
static func apply_upscaling(viewport: Viewport, values: Dictionary) -> void:
	if viewport == null or not (viewport is Window) or viewport.get_parent() != null: return
	var vendor := active_upscaler(values)
	if vendor == OFF:
		if viewport.has_meta(SAVED_SCALING):
			var saved: Array = viewport.get_meta(SAVED_SCALING)
			viewport.remove_meta(SAVED_SCALING)
			viewport.scaling_3d_mode = int(saved[0]) as Viewport.Scaling3DMode
			viewport.scaling_3d_scale = float(saved[1])
		return
	var sdk_modes := [ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"), ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_FSR_SDK")]
	if not viewport.has_meta(SAVED_SCALING) and int(viewport.scaling_3d_mode) not in sdk_modes:
		viewport.set_meta(SAVED_SCALING, [int(viewport.scaling_3d_mode), viewport.scaling_3d_scale])
	var quality := clampi(int(values.get("upscale_quality", 1)), 0, 3)
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	var constant := "SCALING_3D_MODE_DLSS"
	if vendor == AMD:
		fidelityfx().call("set_upscaler_version", _fsr_version(values))
		constant = "SCALING_3D_MODE_FSR_SDK"
	viewport.scaling_3d_scale = (DLSS_SCALES if vendor == NVIDIA else FSR_SCALES)[quality]
	viewport.set("scaling_3d_mode", ClassDB.class_get_integer_constant("Viewport", constant))

## A report of both SDKs and the requests, for the status file and logs.
static func status_report(values: Dictionary) -> Dictionary:
	return {"platform_ready": platform_ready(), "running_owner": OWNER_NAMES[running_owner()],
		"wanted_owner": wanted_owner(values), "owner_file": read_owner_file(),
		"requested": {"upscaler": int(values.get("upscaler", 0)), "fsr_version": _fsr_version(values),
			"upscale_quality": int(values.get("upscale_quality", 1)), "frame_generation": int(values.get("frame_generation", 0)),
			"ray_reconstruction": bool(values.get("ray_reconstruction", false))},
		"active_upscaler": active_upscaler(values),
		"upscaler_reason": upscaler_reason(int(values.get("upscaler", 0)), values),
		"frame_generation_reason": frame_generation_reason(int(values.get("frame_generation", 0)), values),
		"ray_reconstruction_reason": ray_reconstruction_reason(values, bool(values.get("path_tracing", false))),
		"ray_reconstruction_active": ray_reconstruction_active(values),
		"path_tracing_ray_reconstruction": ELPathTracing.ray_reconstruction_report,
		"max_fps": Engine.max_fps,
		"nvidia": status(NVIDIA), "amd": status(AMD)}

# --- Frame generation while playing -------------------------------------------

## The game's settings.
var settings: ELSettings
## Returns what on screen stops frame generation now (menus, loading,
## movies, no map or battle shown): an Array of short names.
var scene_blockers: Callable
## The upscaler started or stopped rendering (an SDK failure, a change of
## settings): the display options should be applied again.
signal upscaling_changed

var _generation := OFF
var _upscaling := OFF
var _telemetry := 0.0
var _blockers: Array = []
var _meter := FrameMeter.new()
var _capped := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No per-frame work without an SDK in a Windows Forward+ Vulkan run.
	set_process(engine_has_sdk() and platform_ready())

func _process(delta: float) -> void:
	if settings == null: return
	var values := settings.values
	var upscaling := active_upscaler(values)
	if upscaling != _upscaling:
		_upscaling = upscaling
		upscaling_changed.emit()
	var root := get_tree().root
	var wanted := int(values.get("frame_generation", OFF))
	var blockers: Array = []
	if wanted == OFF: blockers.append("option_off")
	elif available_frame_generation(values) == OFF: blockers.append("unavailable")
	if get_tree().paused: blockers.append("paused")
	if not root.has_focus(): blockers.append("window_unfocused")
	if root.get_camera_3d() == null: blockers.append("no_camera")
	if scene_blockers.is_valid(): blockers.append_array(scene_blockers.call())
	_blockers = blockers
	_set_generation(wanted if blockers.is_empty() else OFF)
	_keep_fsr_version(values)
	_cap_frame_rate(values)
	_telemetry += delta
	if _telemetry >= 1.0:
		_telemetry = 0.0
		var report := status_report(values)
		report.frame_generation_blockers = blockers
		report.rendered_fps = Engine.get_frames_per_second()
		var out := FileAccess.open(STATUS_FILE, FileAccess.WRITE)
		if out != null: out.store_string(JSON.stringify(report, "\t") + "\n")

func _set_generation(vendor: int) -> void:
	if vendor == _generation: return
	var root := get_tree().root
	if _generation != OFF and _generation != vendor: _switch(_generation, false, root)
	_generation = vendor
	root.set("frame_generation", vendor != OFF)
	if vendor != OFF: _switch(vendor, true, root)
	_meter.reset()

func _switch(vendor: int, on: bool, root: Window) -> void:
	if vendor == NVIDIA:
		# NVIDIA Reflex is required by DLSS Frame Generation.
		streamline().call("set_parameter", REFLEX_MODE, 1.0 if on else 0.0)
	elif vendor == AMD:
		fidelityfx().call("set_frame_generation_version", _fsr_version(settings.values) if on else 0)
	if not on: root.set("frame_generation", false)

## The FSR version the SDK runs follows the setting (changed while running,
## frame generation would otherwise keep the version it started with): FSR 4
## never quietly runs as 3.1, and an unavailable version stops instead.
func _keep_fsr_version(values: Dictionary) -> void:
	if _upscaling != AMD and _generation != AMD: return
	var version := _fsr_version(values)
	var state := status(AMD)
	if _upscaling == AMD and int(state.get("upscaler_version_requested", version)) != version:
		fidelityfx().call("set_upscaler_version", version)
	# Frame generation runs here only while its reason for `version` is empty.
	if _generation == AMD and int(state.get("frame_generation_version_requested", version)) != version:
		fidelityfx().call("set_frame_generation_version", version)

## While AMD frame generation is active, Engine.max_fps follows the SDK's
## recommendation (or the player's lower cap); the player's cap returns after.
func _cap_frame_rate(values: Dictionary) -> void:
	var state := status(AMD)
	var recommended := int(state.get("recommended_max_fps", 0)) if bool(state.get("frame_generation_active", false)) else 0
	if recommended > 0:
		_capped = true
		var cap := frame_rate_cap(int(values.get("frame_rate", 0)), recommended)
		if Engine.max_fps != cap: Engine.max_fps = cap
	elif _capped:
		_restore_frame_rate()

func _restore_frame_rate() -> void:
	_capped = false
	Engine.max_fps = maxi(0, int(settings.values.get("frame_rate", 0))) if settings != null else 0

func _exit_tree() -> void:
	if _generation != OFF and is_inside_tree(): _switch(_generation, false, get_tree().root)
	_generation = OFF
	if _capped: _restore_frame_rate()

## What stops frame generation this frame (empty while it runs).
func blockers() -> Array:
	return _blockers

## The frame rate counter's text: with frame generation running, the frames
## shown (measured from the SDK's present counters) and the frames rendered.
func fps_text(translate := Callable()) -> String:
	var rendered := roundi(Engine.get_frames_per_second())
	var state := status(_generation) if _generation != OFF else {}
	var rates := _meter.sample(state, Time.get_ticks_usec(), rendered)
	return FrameMeter.label_text(rates, translate)

## Presented and rendered frame rates from the SDK's counters over the same
## interval; nothing is assumed about how many frames are generated.
class FrameMeter:
	var _presented := -1
	var _rendered := -1
	var _usec := -1

	func reset() -> void:
		_presented = -1
		_rendered = -1
		_usec = -1

	## `state`: an SDK status; `now` in microseconds; `fallback` the engine's
	## own frame rate. presented_fps is -1 when unknown.
	func sample(state: Dictionary, now: int, fallback: int) -> Dictionary:
		var result := {"presented_fps": -1.0, "rendered_fps": float(fallback)}
		if not bool(state.get("frame_generation_active", false)) or not state.has("presented_frames") or not state.has("game_presents"):
			reset()
			return result
		var presented := int(state.presented_frames)
		var rendered := int(state.game_presents)
		var elapsed := now - _usec
		# A first sample, a counter reset, a clock going back or a long
		# suspension starts a fresh interval.
		if _usec >= 0 and elapsed > 0 and elapsed <= 4_000_000 and presented >= _presented and rendered >= _rendered:
			var seconds := elapsed / 1_000_000.0
			result.presented_fps = (presented - _presented) / seconds
			result.rendered_fps = (rendered - _rendered) / seconds
		_presented = presented
		_rendered = rendered
		_usec = now
		return result

	static func label_text(rates: Dictionary, translate := Callable()) -> String:
		var presented := float(rates.get("presented_fps", -1.0))
		var rendered := roundi(float(rates.get("rendered_fps", 0.0)))
		if presented < 0.0: return "%d FPS" % rendered
		var template := "%d FPS (%d rendered)"
		if translate.is_valid(): template = translate.call(template)
		return template % [roundi(presented), rendered]

# --- Attribution ----------------------------------------------------------------

## Credits for the SDKs the running engine includes ("" on stock engines).
## The export of an SDK build may also mark them in the project settings.
const NVIDIA_FLAG := "application/graphics_sdk/nvidia"
const AMD_FLAG := "application/graphics_sdk/amd"
const ATTRIBUTION_TITLE := "Graphics technologies"
const NVIDIA_CREDIT := "NVIDIA DLSS and NVIDIA Reflex via NVIDIA Streamline."
const NVIDIA_SOURCE := "This software contains source code provided by NVIDIA Corporation."
const NVIDIA_MARKS := "NVIDIA, the NVIDIA logo, GeForce RTX and DLSS are trademarks and/or registered trademarks of NVIDIA Corporation in the U.S. and other countries."
const AMD_CREDIT := "AMD FSR Upscaling and AMD FSR Frame Generation via the AMD FidelityFX SDK."
const AMD_MARKS := "AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of Advanced Micro Devices, Inc."
const LICENSES := "Full license and copyright notices are included in the licenses folder."
const NVIDIA_LOGO := "res://assets/branding/vendors/nvidia-geforce-rtx.tres"
const AMD_UPSCALING_LOGO := "res://assets/branding/vendors/amd-fsr-upscaling-white.png"
const AMD_FRAME_GENERATION_LOGO := "res://assets/branding/vendors/amd-fsr-frame-generation-white.png"

static func credits_nvidia() -> bool:
	return compiled(NVIDIA) or bool(ProjectSettings.get_setting(NVIDIA_FLAG, false))

static func credits_amd() -> bool:
	return compiled(AMD) or bool(ProjectSettings.get_setting(AMD_FLAG, false))

static func credits_bbcode(translate := Callable()) -> String:
	var nvidia := credits_nvidia()
	var amd := credits_amd()
	if not nvidia and not amd: return ""
	var t := func(text: String) -> String: return translate.call(text) if translate.is_valid() else text
	var text: String = "[center][font_size=22]" + t.call(ATTRIBUTION_TITLE) + "[/font_size]\n\n"
	if nvidia:
		text += "[img width=240 height=72]" + NVIDIA_LOGO + "[/img]\n\n"
		text += "[font_size=16]" + t.call(NVIDIA_CREDIT) + "[/font_size]\n"
		text += "[font_size=13]" + t.call(NVIDIA_SOURCE) + "\n" + t.call(NVIDIA_MARKS) + "[/font_size]\n\n"
	if amd:
		text += "[img width=150 height=94]" + AMD_UPSCALING_LOGO + "[/img]      "
		text += "[img width=173 height=94]" + AMD_FRAME_GENERATION_LOGO + "[/img]\n\n"
		text += "[font_size=16]" + t.call(AMD_CREDIT) + "[/font_size]\n"
		text += "[font_size=13]" + t.call(AMD_MARKS) + "[/font_size]\n\n"
	text += "[font_size=13]" + t.call(LICENSES) + "[/font_size][/center]"
	return text
