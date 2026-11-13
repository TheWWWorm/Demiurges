extends SceneTree
## Headless check of what a report says about how the previous session ended
## and about memory (ELCrashReport):
## - Android's exit record of a process becomes the report lines "exit",
##   "exit_detail" and "exit_memory" (a native crash with its signal, low
##   memory, not responding, a kill by a signal, an unknown number);
## - a session found at the next start carries those lines into the report,
##   and a record older than the session (another process with the same
##   number) is left out; a session closed on the user's request (a force
##   stop, an update of the game) is not offered as a crash;
## - the memory of the device is read from the system's own table where the
##   engine gives no numbers, and each session records total, free and used
##   memory.
##
##   godot --headless --path game --script ../tools/crash_exit_reason_check.gd
##
## Markers go to user://crash_exit_reason_check/ (removed afterwards); the
## game's own crash markers are not touched. The exit record itself exists
## on Android only, so a stand-in supplies it here.

const FOLDER := "user://crash_exit_reason_check"

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
func _marker(pid: int, started_unix: int) -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var config := ConfigFile.new()
	for pair: Array in [["session", "%012x" % pid], ["pid", pid], ["renderer", "mobile / vulkan"], ["where", "battle el1 campaign"],
			["uptime_s", 2259], ["state", "foreground"], ["focus", "in"], ["updated", "2026-11-12T17:35:29"], ["started_unix", started_unix]]:
		config.set_value("session", pair[0], pair[1])
	config.save(FOLDER.path_join("%s%d.cfg" % [ELCrashReport.MARK_PREFIX, pid]))

func _run() -> void:
	ELCrashReport.enabled = false
	ELCrashReport.handheld = true

	# The exit record as report lines.
	var native := ELCrashReport.exit_lines({"reason": 5, "status": 11, "description": "crash", "pss_kb": 1500000, "rss_kb": 1800000})
	check(str(native.get("exit", "")) == "native crash (signal 11 SIGSEGV)", "a native crash names its signal: %s" % native.get("exit", ""))
	check(str(native.get("exit_detail", "")) == "crash", "the system's description is kept")
	check(str(native.get("exit_memory", "")) == "pss 1464 MB, rss 1757 MB", "the process memory at its end: %s" % native.get("exit_memory", ""))
	var low := ELCrashReport.exit_lines({"reason": 3, "status": 0, "description": "", "pss_kb": 0, "rss_kb": 0})
	check(str(low.get("exit", "")).contains("low memory"), "a low-memory kill is named: %s" % low.get("exit", ""))
	check(not low.has("exit_detail") and not low.has("exit_memory"), "empty details are left out")
	check(not ELCrashReport._info_text("Previous session", low).contains("exit_reason"), "the reason's number is not a report line")
	check(str(ELCrashReport.exit_lines({"reason": 6}).get("exit", "")).contains("not responding"), "a hang (ANR) is named")
	check(str(ELCrashReport.exit_lines({"reason": 2, "status": 9}).get("exit", "")) == "killed by a signal (signal 9 SIGKILL)", "a kill by a signal names it")
	check(str(ELCrashReport.exit_lines({"reason": 1, "status": 3}).get("exit", "")) == "the game exited by itself (code 3)", "an exit by itself shows its code")
	check(str(ELCrashReport.exit_lines({"reason": 10}).get("exit", "")).contains("user"), "a close by the user is named")
	check(str(ELCrashReport.exit_lines({"reason": 99, "status": 0}).get("exit", "")) == "reason 99", "an unknown number is shown as it is")
	check(ELCrashReport.exit_lines({}).is_empty(), "no record gives no lines")

	# A session found at the next start.
	_clear()
	var dead := 999_999_002
	var started := 1_794_500_000
	_marker(dead, started)
	var asked: Array[int] = []
	ELCrashReport.exit_source = func(pid: int) -> Dictionary:
		asked.append(pid)
		return {"reason": 5, "status": 11, "description": "", "pss_kb": 2048000, "rss_kb": 0, "time_ms": (started + 2259) * 1000}
	var found := ELCrashReport.scan(OS.get_process_id(), FOLDER)
	check(str(found.get("session", "")) == "%012x" % dead, "the session that ended unexpectedly is found")
	check(asked == [dead], "its process number is looked up")
	check(str(found.get("exit", "")) == "native crash (signal 11 SIGSEGV)", "the found session says how it ended: %s" % found.get("exit", ""))
	check(not FileAccess.file_exists(FOLDER.path_join("%s%d.cfg" % [ELCrashReport.MARK_PREFIX, dead])), "its marker is removed")
	var report := ELCrashReport.new()
	var text := report.report_text(found, 20)
	check(text.contains("\nexit: native crash (signal 11 SIGSEGV)\n"), "the report has the exit line")
	check(text.contains("\nexit_memory: pss 2000 MB\n"), "the report has the memory at the end")
	check(text.find("exit: native crash") < text.find("== This session =="), "the exit line is in the previous session's part")

	# A record from before the session started is another process.
	_marker(dead, started)
	ELCrashReport.exit_source = func(_pid: int) -> Dictionary:
		return {"reason": 3, "status": 0, "time_ms": (started - 3600) * 1000}
	var stale := ELCrashReport.scan(OS.get_process_id(), FOLDER)
	check(not stale.is_empty() and not stale.has("exit"), "an older record of the same process number is left out")
	# No record (an older Android, a computer).
	_marker(dead, started)
	ELCrashReport.exit_source = func(_pid: int) -> Dictionary: return {}
	var bare := ELCrashReport.scan(OS.get_process_id(), FOLDER)
	check(not bare.is_empty() and not bare.has("exit"), "a session without a record is still reported")
	# A force stop and an update of the game are not crashes.
	for reason: int in [10, 16]:
		_marker(dead, started)
		ELCrashReport.exit_source = func(_pid: int) -> Dictionary: return {"reason": reason, "status": 0, "time_ms": (started + 60) * 1000}
		check(ELCrashReport.scan(OS.get_process_id(), FOLDER).is_empty(), "a session closed on request (reason %d) is not offered as a crash" % reason)
		check(not FileAccess.file_exists(FOLDER.path_join("%s%d.cfg" % [ELCrashReport.MARK_PREFIX, dead])), "its marker is removed all the same")
	ELCrashReport.exit_source = Callable()
	_clear()
	DirAccess.remove_absolute(FOLDER)

	# Memory.
	var table := "MemTotal:       11732920 kB\nMemFree:          212345 kB\nMemAvailable:    5012345 kB\nBuffers:            1234 kB\n"
	var parsed := ELCrashReport.meminfo(table)
	check(int(parsed.get("physical_mb", -1)) == 11457 and int(parsed.get("available_mb", -1)) == 4894, "the system's memory table is read: %s" % parsed)
	check(ELCrashReport.meminfo("").is_empty(), "an empty table gives nothing")
	var now := ELCrashReport.memory()
	check(int(now.get("physical_mb", -1)) > 0 and int(now.get("available_mb", -1)) > 0, "this machine's total and free memory are known: %s" % now)
	report._collect()
	check(int(report.info.get("memory_mb", -1)) > 0, "the session records the total memory")
	check(int(report.info.get("memory_free_mb", -1)) > 0, "the session records the free memory")
	check(int(report.info.get("memory_used_mb", -1)) > 0, "the session records the game's own memory")
	var block := ELCrashReport._info_text("This session", report.info)
	check(block.contains("\nmemory_free_mb: ") and block.contains("\nmemory_used_mb: "), "the report shows free and used memory")
	report.free()

	print("CRASH EXIT REASON: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
