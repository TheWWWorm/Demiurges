extends SceneTree
## Per-frame timings while the front menu switches between the two games.
## Needs both games mounted. Windowed, so the frames include real draws:
## godot --path game --resolution 1280x720 --script ../tools/menu_switch_timing.gd
## Prints the worst frame while the menu readies the other game in the
## background, one line per switch with the worst frames after the click, and
## exits 1 when a game is missing or leaving the menu keeps the wrong game's
## battle.

const SWITCHES := 6
const FRAMES_AFTER := 90

var _last := 0
var _frames: Array[float] = []
var _recording := false

func _initialize() -> void:
	_run.call_deferred()

func _frame() -> void:
	var now := Time.get_ticks_usec()
	if _recording: _frames.append((now - _last) / 1000.0)
	_last = now

func _run() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	# Started as the launched game is: the front end with no battle behind it.
	view.launch_as_game = true
	root.add_child(view)
	process_frame.connect(_frame)
	for i in 30: await process_frame
	if view.front_menu == null or not view.profiles.has("el1") or not view.profiles.has("el2"):
		print("MENU SWITCH: both games must be mounted")
		quit(1)
		return
	if view.front_menu.edition != "el1": view.front_menu._choice._chosen("el1")
	_frames.clear()
	_last = Time.get_ticks_usec()
	_recording = true
	for i in 60: await process_frame
	_recording = false
	var idle := _frames.duplicate()
	idle.sort()
	print("MENU SWITCH idle after showing the menu: worst frames %s ms" % str(idle.slice(idle.size() - 3).map(func(x: float) -> String: return "%.1f" % x)))
	var order := ["el2", "el1"]
	var worst_all := 0.0
	for n in SWITCHES:
		var target: String = order[n % 2]
		_frames.clear()
		_last = Time.get_ticks_usec()
		_recording = true
		var started := Time.get_ticks_usec()
		view.front_menu._choice._chosen(target)
		var click_ms := (Time.get_ticks_usec() - started) / 1000.0
		for i in FRAMES_AFTER: await process_frame
		_recording = false
		var sorted := _frames.duplicate()
		sorted.sort()
		sorted.reverse()
		var over := _frames.filter(func(ms: float) -> bool: return ms > 33.4).size()
		worst_all = maxf(worst_all, sorted[0])
		var median: float = _frames.duplicate().map(func(x): return x).reduce(func(a, b): return a + b) / _frames.size()
		print("MENU SWITCH %d -> %s: click handler %.1f ms; worst frames %s ms; frames > 33 ms: %d; mean %.1f ms; menu %s, battle %s" % [n + 1, target, click_ms, str(sorted.slice(0, 4).map(func(x: float) -> String: return "%.1f" % x)), over, median, view.front_menu.edition, "none" if view.duel == null else view.profile.id])
	print("MENU SWITCH: worst frame %.1f ms" % worst_all)
	# Leaving the menu for the duel setup builds the chosen game's battle.
	view.front_menu._choice._chosen("el2")
	await process_frame
	view.front_menu.duel_requested.emit()
	await process_frame
	var settled: bool = view.profile.id == "el2" and view.duel != null
	print("MENU SWITCH: battle after leaving the menu: %s (%s)" % [view.profile.id, "ok" if settled else "WRONG"])
	quit(0 if settled else 1)
