extends SceneTree
## Compare frame intervals on the same rendered battle while Smarter repeatedly
## thinks on its normal background worker. Run without --headless:
##   godot --path game --resolution 1280x720 --script ../tools/duel_ai_frame_bench.gd -- --out=<json>
## The default board needs EL1. Pass --board=<save> to measure another
## installed edition or --think-ms=<milliseconds> to change the search time.
## The board stays fixed between decisions.

var samples := PackedInt64Array()
var recording := false
var previous := 0

func _initialize() -> void:
	_run.call_deferred()

func _drawn() -> void:
	var now := Time.get_ticks_usec()
	if recording and previous > 0: samples.append(now - previous)
	previous = now

func _run() -> void:
	var output := ""
	var think_ms := ELCombatSearch.smart_engine_ms
	var board_path := "res://../tools/duel_ai_positions/el1_survive_cutters.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--think-ms="): think_ms = maxi(1, int(arg.trim_prefix("--think-ms=")))
		if arg.begins_with("--board="): board_path = arg.trim_prefix("--board=")
	var view = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	var board: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(board_path))
	var battle := ELDuel.new()
	var edition := String(board.get("state", {}).get("profile", ""))
	if not view.profiles.has(edition) or not battle.restore(view.profiles[edition], board):
		printerr("Cannot restore ", board_path, " with ", edition, ": ", battle.error, " (installed ", view.profiles.keys(), ")")
		quit(1)
		return
	view.demo = false
	view._start(edition, {}, battle)
	view.mode_select.select(1)
	battle.smart_sides = [battle.active_side()]
	RenderingServer.frame_post_draw.connect(_drawn)
	await create_timer(3.0).timeout
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.is_empty() or view.models.is_empty():
		printerr("A rendered battle with models is required")
		quit(1)
		return
	var hardware := ELCombatSearch.available_processors()
	var report := {"adapter": adapter, "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size),
		"fps_limit": Engine.max_fps, "display_hz": DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"models": view.models.size(), "board": board_path, "logical_processors": hardware, "think_ms": think_ms, "batches": []}
	ELCombatSearch.smart_engine_ms = think_ms
	for mode: String in ["idle", "serial", "auto", "all", "all", "auto", "serial", "idle"]:
		view.ai_frame_budget = ELPracticeAI.FrameBudget.new()
		ELCombatSearch.smart_engine_workers = hardware if mode == "all" else (1 if mode == "serial" else 0)
		var calls := 0
		var positions := 0
		var peak := 0
		var limits := []
		samples.clear()
		await RenderingServer.frame_post_draw
		previous = Time.get_ticks_usec()
		var start := Time.get_ticks_msec()
		recording = true
		while Time.get_ticks_msec() - start < 8000:
			if mode == "idle":
				await RenderingServer.frame_post_draw
				continue
			ELCombatSearch.reset_caches()
			limits.append(view.ai_frame_budget.limit)
			var result: Variant = ELPracticeAI._background(battle, false, view.ai_frame_budget.limit)
			while result == null:
				await RenderingServer.frame_post_draw
				if ELPracticeAI.thinking(battle): continue
				result = ELPracticeAI._background(battle, false, view.ai_frame_budget.limit)
			if result.command.is_empty():
				printerr("No command returned")
				quit(1)
				return
			calls += 1
			peak = maxi(peak, int(result.stats.get("workers", 1)))
			positions += int(result.stats.get("positions", 0))
		recording = false
		report.batches.append({"mode": mode, "calls": calls, "positions": positions, "peak_workers": peak,
			"elapsed_ms": Time.get_ticks_msec() - start, "worker_limits": limits, "frame_usec": Array(samples)})
		print("FRAME ", mode, " frames=", samples.size(), " decisions=", calls, " peak_workers=", peak)
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write ", output)
			quit(1)
			return
		file.store_string(JSON.stringify(report))
		file.close()
	else: print(JSON.stringify(report))
	quit()
