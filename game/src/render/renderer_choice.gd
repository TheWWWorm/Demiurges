class_name ELRendererChoice
extends RefCounted
## Which renderer the saved settings start the game with, and the command
## line that starts it again with that renderer. Shared by the start-up screen
## (scenes/boot.tscn) and the game (view.gd's _ensure_renderer,
## ELGraphicsSDK, ELHardwareCheck).
##
## Names no other game class: the start-up screen runs this before the game's
## scripts are compiled, so a start that has to change renderer starts again
## at once instead of compiling everything twice.

## ELSettings' file and its current format (ELSettings.SETTINGS_VERSION).
const SETTINGS_FILE := "user://settings.json"
const SETTINGS_VERSION := 6
## ELGraphicsSDK's upscaler values and presentation owners.
const OFF := 0
const AMD := 1
const NVIDIA := 2
const UPSCALERS := [OFF, NVIDIA, AMD]
const OWNER_FILE := "user://graphics_sdk.cfg"
## ELCrashReport's session markers: one left behind is a session that ended
## unexpectedly, which can change the renderer (ELCrashReport.renderer_fallback).
const CRASH_DIR := "user://crash"
const CRASH_MARK_PREFIX := "running_"
## ELHardwareCheck.PROBE_ARG: the hidden copy that tests the renderer.
const PROBE_ARG := "--renderer-probe="
## Marks a start that was already started again for its renderer.
const RESTARTED_ARG := "--renderer-restarted"

## The engine has an upscaling SDK compiled in (ELGraphicsSDK.engine_has_sdk).
static func engine_has_sdk() -> bool:
	for vendor: int in [AMD, NVIDIA]:
		var singleton := "Streamline" if vendor == NVIDIA else "FidelityFX"
		var constant := "SCALING_3D_MODE_DLSS" if vendor == NVIDIA else "SCALING_3D_MODE_FSR_SDK"
		if not Engine.has_singleton(singleton) or not ClassDB.class_has_integer_constant("Viewport", constant): continue
		var native := Engine.get_singleton(singleton)
		var state: Variant = native.call("get_status") if native != null and native.has_method("get_status") else {}
		if state is Dictionary and bool(state.get("compiled", false)): return true
	return false

## The vendor the settings' upscaler or frame generation needs to own
## presentation ("" for none): "nvidia" or "amd".
static func owner_for(values: Dictionary) -> String:
	var upscaler := int(values.get("upscaler", OFF))
	if upscaler not in UPSCALERS: upscaler = OFF
	var generation := OFF
	if bool(values.get("frame_generation", false)): generation = NVIDIA if upscaler == NVIDIA else AMD
	if upscaler == NVIDIA or generation == NVIDIA: return "nvidia"
	if upscaler == AMD or generation == AMD: return "amd"
	return ""

## The upscaler choices need Forward+ (Windows, an engine with an SDK).
static func owner_needs_vulkan(values: Dictionary, has_sdk: bool) -> bool:
	return OS.get_name() == "Windows" and has_sdk and not owner_for(values).is_empty()

## The settings start the game on Forward+ (Vulkan), not Compatibility.
static func wants_vulkan(values: Dictionary, has_sdk: bool) -> bool:
	return int(values.get("renderer", 0)) == 1 or owner_needs_vulkan(values, has_sdk)

static func renderer_args(vulkan: bool, mobile := OS.has_feature("mobile")) -> PackedStringArray:
	if not vulkan: return PackedStringArray(["--rendering-method", "gl_compatibility"])
	return PackedStringArray(["--rendering-method", "mobile" if mobile else "forward_plus", "--rendering-driver", "vulkan"])

## This game's command line with the renderer `vulkan` asks for in place of
## any named one, and `sdk_owner` as the presentation owner (null: an engine
## without an SDK); `marked` adds the note that stops a second automatic
## restart.
static func relaunch_args(vulkan: bool, sdk_owner: Variant, marked: bool) -> PackedStringArray:
	var args := PackedStringArray()
	# A game run from its project folder (not exported) names that folder.
	if not OS.has_feature("template"): args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	var skip := false
	for arg: String in OS.get_cmdline_args():
		if skip:
			skip = false
		elif arg in ["--rendering-method", "--rendering-driver"]:
			skip = true
		elif arg.begins_with("--graphics-sdk="):
			# The saved choice replaces any stale command-line owner.
			pass
		else:
			args.append(arg)
	args.append_array(renderer_args(vulkan))
	if sdk_owner is String: args.append("--graphics-sdk=" + sdk_owner)
	var user := PackedStringArray(OS.get_cmdline_user_args())
	if user.has(RESTARTED_ARG): user.remove_at(user.find(RESTARTED_ARG))
	if marked: user.append(RESTARTED_ARG)
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	return args

## The saved settings' renderer choices, read as ELSettings.load_file reads
## them; empty when the file is missing, unreadable or of another format
## version (ELSettings migrates those, so the game decides).
static func saved_choices(path := SETTINGS_FILE) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("shared") is Dictionary: return {}
	var version: Variant = raw.get("version", 0)
	if not (version is int or version is float) or int(version) != SETTINGS_VERSION: return {}
	var shared: Dictionary = raw.shared
	var number := func(key: String) -> int:
		var value: Variant = shared.get(key)
		return int(value) if (value is int or value is float) and is_finite(float(value)) else 0
	var frame_generation: Variant = shared.get("frame_generation")
	return {"renderer": clampi(number.call("renderer"), 0, 1), "upscaler": number.call("upscaler"),
		"frame_generation": frame_generation if frame_generation is bool else false}

## A session marker is left: the game may step the renderer back (or another
## copy is running), so it decides itself.
static func session_marker_left(folder := CRASH_DIR) -> bool:
	if not DirAccess.dir_exists_absolute(folder): return false
	for file: String in DirAccess.get_files_at(folder):
		if file.begins_with(CRASH_MARK_PREFIX) and file.ends_with(".cfg"): return true
	return false

## The start-up screen's check, before the game's scripts load: when the
## saved settings want the other renderer, writes the presentation owner (as
## the game does) and starts the game again with it, then quits; true then.
## Covers what can be known before the game runs. Everything else
## (migrated or missing settings, a session that ended unexpectedly, the SDK
## owner of a Forward+ run) stays with view.gd's _ensure_renderer.
static func restart_early(tree: SceneTree) -> bool:
	if OS.has_feature("editor") or OS.has_feature("web") or OS.has_feature("mobile"): return false
	if DisplayServer.get_name() == "headless": return false
	var user := OS.get_cmdline_user_args()
	if user.has(RESTARTED_ARG) or OS.get_cmdline_args().has("--rendering-method"): return false
	for arg: String in user:
		if arg.begins_with(PROBE_ARG): return false
	var values := saved_choices()
	if values.is_empty() or session_marker_left(): return false
	var has_sdk := engine_has_sdk()
	var wanted := "forward_plus" if wants_vulkan(values, has_sdk) else "gl_compatibility"
	if RenderingServer.get_current_rendering_method() == wanted: return false
	if has_sdk: write_owner(owner_for(values))
	print("Starting again on %s (saved renderer choice)" % wanted)
	OS.create_process(OS.get_executable_path(), relaunch_args(wanted == "forward_plus", owner_for(values) if has_sdk else null, true))
	tree.quit()
	return true

## ELGraphicsSDK.write_owner_file's file: the owner the next start sets up.
static func write_owner(owner: String) -> void:
	var config := ConfigFile.new()
	if config.load(OWNER_FILE) == OK and str(config.get_value("startup", "owner", "")) == owner: return
	config = ConfigFile.new()
	config.set_value("startup", "owner", owner)
	config.save(OWNER_FILE)
