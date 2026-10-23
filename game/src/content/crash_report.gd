class_name ELCrashReport
extends Node
## Logs and crash reports, adapted from the Cursed Lands engine (Apache-2.0).
## Godot writes every print and error to user://logs/godot.log (file logging
## is on for every platform but the web; earlier runs' logs are kept as
## godot<date>.log). `trace` adds one line at each step of a session (game
## loaded, battle start and end, map, save, load, settings), so the last lines
## tell where a run stopped.
## A running session keeps a marker, user://crash/running_<pid>.cfg, with its
## system and session information. A clean quit removes it; a marker left at
## the next start means that session ended unexpectedly, and the game offers a
## report to save or copy (ELCrashReportBox). On Android and iOS a session
## closed by the system while in the background, or after losing the focus
## (closed from the recent apps), is not a crash and is only noted in the log.
## Reports go where the player can find them: Android → the shared Download
## folder, else the app's Documents folder; a computer → Downloads, else
## Documents; user://reports last; the web → a browser download.

const DIR := "user://crash"
const LOG_DIR := "user://logs"
const LOG_FILE := "user://logs/godot.log"
const CLIP_LINES := 200
const FILE_LINES := 5000
const MARK_PREFIX := "running_"

static var instance: ELCrashReport
## Checks: where reports are saved instead of the player's folders.
static var save_dir_override := ""
## Off on the web: a closed tab never quits cleanly, and there is no log file.
static var enabled := not OS.has_feature("web")
## Android / iOS: a marker left without the focus is a close from the recent
## apps, not a crash. Checks set it on a computer.
static var handheld := OS.has_feature("mobile")

## The previous session that ended unexpectedly ({} = none), with "log" = its
## log file. Offered once.
var previous := {}
var info := {}
## Returns a short summary of the player's options for the report.
var options_summary: Callable
var _marker := ""
var _done := false

## One line for the log at a step of the session; never per frame. The log
## is flushed at each line (application/run/flush_stdout_on_print).
static func trace(what: String) -> void:
	print("[trace %s +%dms] %s" % [Time.get_time_string_from_system(), Time.get_ticks_msec(), what])
	note(what)

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "CrashReport"
	if not enabled: return
	var sid := "%08x%04x" % [randi(), Time.get_ticks_usec() & 0xffff]
	info = {"session": sid, "pid": OS.get_process_id(), "started": Time.get_datetime_string_from_system(false, true),
		"state": "foreground", "focus": "in", "where": "(start)", "last": ""}
	_collect()
	trace("session %s: Demiurges %s, %s, %s, %s" % [sid, info.version, info.os, info.gpu, info.renderer])
	previous = scan(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(DIR)
	_marker = DIR.path_join("%s%d.cfg" % [MARK_PREFIX, OS.get_process_id()])
	_write()

## Version, system, graphics and options.
func _collect() -> void:
	info.version = String(ProjectSettings.get_setting("application/config/version", "?"))
	info.engine = String(Engine.get_version_info().get("string", ""))
	info.os = "%s %s" % [OS.get_name(), OS.get_version()]
	if OS.get_distribution_name() != "" and OS.get_distribution_name() != OS.get_name():
		info.os += " (%s)" % OS.get_distribution_name()
	info.device = OS.get_model_name()
	info.cpu = "%s × %d" % [OS.get_processor_name(), OS.get_processor_count()]
	var memory := int(OS.get_memory_info().get("physical", -1))
	info.memory_mb = memory >> 20 if memory > 0 else -1
	info.gpu = "%s %s" % [RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()]
	info.gpu_api = RenderingServer.get_video_adapter_api_version()
	info.renderer = "%s / %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()]
	var hz := DisplayServer.screen_get_refresh_rate()
	info.screen = "%s @ %s Hz, window %s" % [DisplayServer.screen_get_size(), "%.0f" % hz if hz > 0.0 else "?", DisplayServer.window_get_size()]
	info.locale = OS.get_locale()
	if options_summary.is_valid(): info.options = String(options_summary.call())

## Markers left by sessions that did not quit cleanly (not `own_pid`, not a
## game still running) are removed; returns the newest one that was in the
## foreground (a crash), with "log" = its log file, or {}.
static func scan(own_pid: int) -> Dictionary:
	var best := {}
	if not DirAccess.dir_exists_absolute(DIR): return best
	for file in DirAccess.get_files_at(DIR):
		if not (file.begins_with(MARK_PREFIX) and file.ends_with(".cfg")): continue
		var config := ConfigFile.new()
		var path := DIR.path_join(file)
		if config.load(path) != OK:
			DirAccess.remove_absolute(path)
			continue
		var pid := int(config.get_value("session", "pid", -1))
		if instance != null and path == instance._marker: continue
		if pid != own_pid and alive(pid): continue
		var session := {}
		for key in config.get_section_keys("session"):
			session[key] = config.get_value("session", key)
		DirAccess.remove_absolute(path)
		if String(session.get("state", "")) != "foreground":
			trace("previous session %s was closed by the system in the background (not a crash)" % session.get("session", "?"))
			continue
		if handheld and String(session.get("focus", "")) == "out":
			trace("previous session %s was closed without the focus, from the recent apps (not a crash)" % session.get("session", "?"))
			continue
		if best.is_empty() or String(session.get("updated", "")) > String(best.get("updated", "")):
			best = session
	if not best.is_empty():
		best.log = find_log(String(best.get("session", "")))
		trace("previous session %s ended unexpectedly in %s; its log: %s" % [best.get("session", "?"), best.get("where", "?"), best.log])
	return best

## A process `pid` runs (Linux / Android: /proc). Elsewhere a second game
## window's marker counts as left.
static func alive(pid: int) -> bool:
	return pid > 0 and (OS.has_feature("linuxbsd") or OS.has_feature("android")) and DirAccess.dir_exists_absolute("/proc/%d" % pid)

## The earlier log that holds session `sid`, else the newest earlier log.
static func find_log(sid: String) -> String:
	var logs := older_logs()
	for path: String in logs.slice(0, 4):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_buffer(mini(file.get_length(), 65536)).get_string_from_utf8().contains("session " + sid):
			return path
	return logs[0] if not logs.is_empty() else ""

## Earlier runs' logs (Godot renames godot.log at each start), newest first.
static func older_logs() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(LOG_DIR): return out
	for file in DirAccess.get_files_at(LOG_DIR):
		if file.ends_with(".log") and file != LOG_FILE.get_file(): out.append(LOG_DIR.path_join(file))
	out.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return out

static func tail(path: String, count: int) -> String:
	if path.is_empty() or not FileAccess.file_exists(path): return "(no log file)\n"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "(log not readable)\n"
	var size := file.get_length()
	var take := mini(size, count * 400)
	file.seek(size - take)
	var lines := file.get_buffer(take).get_string_from_utf8().split("\n")
	if take < size and lines.size() > 0: lines.remove_at(0)
	if lines.size() > count: lines = lines.slice(lines.size() - count)
	return "\n".join(lines)

## The last step and where the player was go into the marker.
static func note(what: String) -> void:
	if instance == null or instance._marker.is_empty() or instance._done: return
	instance.info.last = what
	instance._write()

## Where the player is (menu, battle, map …), kept in the marker.
static func where(place: String) -> void:
	if instance == null or not enabled: return
	if instance.info.get("where", "") == place: return
	instance.info.where = place
	trace("now in " + place)

func _write() -> void:
	if _marker.is_empty() or _done: return
	info.updated = Time.get_datetime_string_from_system(false, true)
	info.uptime_s = Time.get_ticks_msec() / 1000
	var config := ConfigFile.new()
	for key: String in info:
		config.set_value("session", key, info[key])
	config.save(_marker)

func _notification(what: int) -> void:
	if not enabled or _marker.is_empty(): return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			info.state = "background"
			trace("app paused (background)")
		NOTIFICATION_APPLICATION_RESUMED:
			info.state = "foreground"
			trace("app resumed")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			info.focus = "out"
			if handheld: trace("app focus out")
			else: _write()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			info.focus = "in"
			_write()
		NOTIFICATION_OS_MEMORY_WARNING:
			trace("system memory warning")

func _exit_tree() -> void:
	clean_exit()

## The session ends normally: its marker goes.
func clean_exit() -> void:
	if _done or _marker.is_empty(): return
	trace("clean exit")
	_done = true
	DirAccess.remove_absolute(_marker)

## Checks: as if the session were killed (the marker stays); `paused`: in the
## background; `focus_out`: after losing the focus.
func simulate_kill(paused: bool, focus_out := false) -> void:
	info.state = "background" if paused else "foreground"
	info.focus = "out" if focus_out else "in"
	_write()
	_done = true

static func _info_text(title: String, session: Dictionary) -> String:
	var text := "== %s ==\n" % title
	for key in ["session", "version", "engine", "os", "device", "cpu", "memory_mb", "gpu", "gpu_api", "renderer",
			"screen", "locale", "options", "started", "updated", "uptime_s", "where", "last", "state", "focus"]:
		if session.has(key): text += "%s: %s\n" % [key, session[key]]
	return text

## The report: the previous session that ended unexpectedly (`prev`, may be
## {}) with its log, then this session's information and log; `lines` per log.
func report_text(prev: Dictionary, lines: int) -> String:
	_collect()
	var text := "Demiurges report, %s\n\n" % Time.get_datetime_string_from_system(false, true)
	if not prev.is_empty():
		text += _info_text("Previous session (ended unexpectedly)", prev)
		text += "\n== Log of the previous session: %s ==\n%s\n" % [String(prev.get("log", "")).get_file(), tail(String(prev.get("log", "")), lines)]
	text += "\n" + _info_text("This session", info)
	if prev.is_empty():
		var older := older_logs()
		if not older.is_empty():
			text += "\n== Log of the previous run: %s ==\n%s\n" % [String(older[0]).get_file(), tail(older[0], lines / 2)]
	text += "\n== Log of this session: %s ==\n%s\n" % [LOG_FILE.get_file(), tail(LOG_FILE, lines if prev.is_empty() else lines / 4)]
	return text

## Folders a player can open, best first.
static func save_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	if save_dir_override != "":
		out.append(save_dir_override)
		return out
	if OS.has_feature("android"):
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS, true))
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false))
	else:
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))
		out.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	out.append(ProjectSettings.globalize_path("user://reports"))
	return out

## Writes the report; returns the file's full path, or "" if no folder took it.
func save_report(prev: Dictionary) -> String:
	var text := report_text(prev, FILE_LINES)
	var file_name := "Demiurges-report-%s.txt" % Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "text/plain")
		trace("report downloaded: " + file_name)
		return file_name
	for folder in save_dirs():
		if folder.is_empty(): continue
		if not DirAccess.dir_exists_absolute(folder):
			# Never create the player's shared folders.
			if folder != save_dir_override and not folder.ends_with("reports"): continue
			DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			trace("report: %s not writable (%s)" % [folder, error_string(FileAccess.get_open_error())])
			continue
		file.store_string(text)
		file.close()
		if FileAccess.file_exists(path):
			trace("report saved: " + path)
			return path
	return ""

func copy_report(prev: Dictionary) -> void:
	DisplayServer.clipboard_set(report_text(prev, CLIP_LINES))
	trace("report copied to the clipboard")
