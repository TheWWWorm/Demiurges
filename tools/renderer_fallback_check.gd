extends SceneTree
## Headless check of the start-up renderer fallback (ELCrashReport) and the
## renderer command line (ELHardwareCheck.renderer_args): a session that
## ended unexpectedly while starting on Vulkan moves the player's Vulkan
## choice back to Compatibility once, says so in the crash box, and leaves
## the markers for the report; other unexpected ends change nothing. Phones
## and tablets start the Vulkan choice on the Mobile renderer.
##
##   godot --headless --path game --script ../tools/renderer_fallback_check.gd
##
## Markers go to user://renderer_fallback_check/ (removed afterwards); the
## game's own crash markers are not touched.

const FOLDER := "user://renderer_fallback_check"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _clear() -> void:
	if not DirAccess.dir_exists_absolute(FOLDER): return
	for file in DirAccess.get_files_at(FOLDER): DirAccess.remove_absolute(FOLDER.path_join(file))

## A marker as a killed session leaves it.
func _marker(pid: int, renderer: String, where: String, uptime: int, state := "foreground", focus := "in") -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var config := ConfigFile.new()
	for pair: Array in [["session", "%012x" % pid], ["pid", pid], ["renderer", renderer], ["where", where], ["uptime_s", uptime],
			["state", state], ["focus", focus], ["updated", "2026-11-12T11:08:53"]]:
		config.set_value("session", pair[0], pair[1])
	config.save(FOLDER.path_join("%s%d.cfg" % [ELCrashReport.MARK_PREFIX, pid]))

func _vulkan_choice() -> Dictionary:
	return {"renderer": 1, "path_tracing": true, "upscaler": 0, "upscaling": 0, "frame_generation": 0, "ray_reconstruction": false}

func _run() -> void:
	var own := OS.get_process_id()
	var dead := 999_999_001
	_clear()

	# The reported case: Forward+ ended 7 s after start, at the menu's battle.
	_marker(dead, "forward_plus / vulkan", "(start)", 7)
	var values := _vulkan_choice()
	check(ELCrashReport.early_vulkan_crash(own, FOLDER) == "forward_plus", "a start-up end on Forward+ is found")
	check(ELCrashReport.renderer_fallback(values, own, FOLDER), "the Vulkan choice falls back after it")
	check(int(values.renderer) == 0 and values.path_tracing == false, "renderer back to Compatibility, path tracing off")
	check(ELCrashReport.renderer_fell_back == "forward_plus", "the fallback is noted for the crash box")
	check(FileAccess.file_exists(FOLDER.path_join("%s%d.cfg" % [ELCrashReport.MARK_PREFIX, dead])), "the marker stays for the report")
	check(not ELCrashReport.renderer_fallback(values, own, FOLDER), "a second start does not fall back again (Compatibility already chosen)")

	# The crash box says it once.
	var box := ELCrashReportBox.open(root, {"session": "c08f218300cf", "where": "(start)"})
	check(box.rows.has_node("RendererFallback"), "the crash box carries the renderer note")
	check(ELCrashReport.renderer_fell_back == "", "the note is shown once")
	box.free()
	var later := ELCrashReportBox.open(root, {"session": "c08f218300cf"})
	check(not later.rows.has_node("RendererFallback"), "a later crash box has no renderer note")
	later.free()

	# The Mobile renderer counts as Vulkan too.
	_clear()
	_marker(dead, "mobile / vulkan", "(start)", 12)
	values = _vulkan_choice()
	check(ELCrashReport.renderer_fallback(values, own, FOLDER) and int(values.renderer) == 0, "a start-up end on the Mobile renderer falls back as well")
	ELCrashReport.renderer_fell_back = ""

	# Unexpected ends that are not start-up crashes on Vulkan change nothing.
	var cases := [
		["gl_compatibility / opengl3", "(start)", 5, "foreground", "in", false, "on Compatibility"],
		["forward_plus / vulkan", "battle el1 campaign", 900, "foreground", "in", false, "after a long session"],
		["forward_plus / vulkan", "(start)", 5, "background", "in", false, "in the background"],
		["forward_plus / vulkan", "(start)", 5, "foreground", "out", true, "closed from the recent apps (phone)"],
	]
	for item: Array in cases:
		_clear()
		_marker(dead, item[0], item[1], item[2], item[3], item[4])
		ELCrashReport.handheld = item[5]
		values = _vulkan_choice()
		check(not ELCrashReport.renderer_fallback(values, own, FOLDER) and int(values.renderer) == 1, "no fallback " + item[6])
	ELCrashReport.handheld = OS.has_feature("mobile")
	_clear()
	_marker(dead, "forward_plus / vulkan", "(start)", 5)
	values = {"renderer": 0}
	check(not ELCrashReport.renderer_fallback(values, own, FOLDER), "no fallback when Compatibility is already chosen")
	_clear()
	_marker(own, "forward_plus / vulkan", "(start)", 5)
	check(ELCrashReport.early_vulkan_crash(own, FOLDER) == "", "this session's own marker is not a crash")
	_clear()
	DirAccess.remove_absolute(FOLDER)

	# The renderer command line.
	check(Array(ELHardwareCheck.renderer_args(true, false)) == ["--rendering-method", "forward_plus", "--rendering-driver", "vulkan"], "a computer starts the Vulkan choice on Forward+")
	check(Array(ELHardwareCheck.renderer_args(true, true)) == ["--rendering-method", "mobile", "--rendering-driver", "vulkan"], "a phone starts the Vulkan choice on the Mobile renderer")
	check(Array(ELHardwareCheck.renderer_args(false, true)) == ["--rendering-method", "gl_compatibility"], "Compatibility stays Compatibility")

	print("RENDERER FALLBACK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
