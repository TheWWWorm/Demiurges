extends SceneTree
## What the game costs from launch to its main menu and while the menu stands:
## time to the menu, the worst start-up frame, then frame and process times,
## memory, video memory and node count while idling on the menu, and after a
## game switch. Starts the scene as the launched game does (launch_as_game).
## Needs both games mounted; windowed so frames include real draws:
## godot --path game --resolution 1280x720 --script ../tools/menu_start_timing.gd -- --no-movies

var _last := 0
var _frames: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func _frame() -> void:
	var now := Time.get_ticks_usec()
	_frames.append((now - _last) / 1000.0)
	_last = now

func _run() -> void:
	var started := Time.get_ticks_usec()
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.launch_as_game = true
	root.add_child(view)
	var ready_ms := (Time.get_ticks_usec() - started) / 1000.0
	_last = Time.get_ticks_usec()
	process_frame.connect(_frame)
	var waited := 0
	while (view.front_menu == null or not view.front_menu.is_visible_in_tree()) and waited < 600:
		await process_frame
		waited += 1
	if view.front_menu == null or not view.profiles.has("el1") or not view.profiles.has("el2"):
		print("MENU START: the menu did not open with both games mounted")
		quit(1)
		return
	var to_menu := (Time.get_ticks_usec() - started) / 1000.0
	var start_frames := _frames.duplicate()
	start_frames.sort()
	print("MENU START: scene ready %.0f ms, menu shown %.0f ms, worst start-up frame %.1f ms" % [ready_ms, to_menu, start_frames.back() if not start_frames.is_empty() else 0.0])
	# Settle background work before reading the idle numbers.
	for i in 240: await process_frame
	await _idle(view, "idle on menu (" + view.front_menu.edition + ")")
	view.front_menu._choice._chosen("el2" if view.front_menu.edition == "el1" else "el1")
	for i in 240: await process_frame
	await _idle(view, "idle after a switch (" + view.front_menu.edition + ")")
	print("MENU START: battle behind the menu: %s" % ("none" if view.duel == null else view.profile.id))
	quit(0)

func _idle(view: Node, what: String) -> void:
	_frames.clear()
	var process_ms := 0.0
	for i in 120:
		await process_frame
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var sorted := _frames.duplicate()
	sorted.sort()
	var mean: float = sorted.reduce(func(a, b): return a + b) / sorted.size()
	print("MENU START %s: frame mean %.2f ms, worst %.1f ms, process %.2f ms/frame, static memory %.0f MB, video memory %.0f MB, nodes %d" % [what, mean, sorted.back(), process_ms / 120.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
