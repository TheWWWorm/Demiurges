extends SceneTree
## Times campaign map loading as the game does it (view._begin_campaign), per
## stage, plus the first frames once the map is up. Run windowed:
##   <godot> --path game --rendering-method forward_plus --rendering-driver vulkan
##     --resolution 1280x720 --script ../tools/campaign_load_probe.gd --
##     --no-movies --game=el1 --maps=mission20,mission261,mission25 [--out=<json>]
##     [--frames=90] [--shots=<folder>] (a still frame of each map with time
##     held from the moment it is up; no frame timing)
## The first map of a run is a cold load (fresh process), the others warm.

var timeline: Array = []
var started := 0
var _world_children := 0

func _initialize() -> void:
	_run.call_deferred()

func mark(label: String) -> void:
	timeline.append([Time.get_ticks_usec() - started, label])

func _run() -> void:
	await process_frame
	var game := "el1"
	var maps: PackedStringArray = []
	var out := ""
	var frame_count := 90
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="): game = arg.trim_prefix("--game=")
		elif arg.begins_with("--maps="): maps = arg.trim_prefix("--maps=").split(",")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="): frame_count = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	var launch := Time.get_ticks_usec()
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	for i in 3: await process_frame
	print("PROBE view ready after %.1f ms" % ((Time.get_ticks_usec() - launch) / 1000.0))
	if not view.profiles.has(game):
		print("PROBE: no %s profile" % game)
		quit(1)
		return
	view.settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(view.settings).persist = false
	view.child_entered_tree.connect(_view_child)
	var results := []
	for map_id: String in maps:
		var row := _row(view.profiles[game], map_id)
		if row.is_empty():
			print("PROBE: %s not in a campaign" % map_id)
			continue
		timeline.clear()
		_world_children = 0
		started = Time.get_ticks_usec()
		mark("begin")
		await view._begin_campaign(game, row, 1)
		mark("ready")
		# Shots hold time from the moment the map is up (and skip the frame
		# timing), so runs of the same map compare.
		if not shots.is_empty(): Engine.time_scale = 0.0
		var total := Time.get_ticks_usec() - started
		var map: ELAdventureView = view.campaign_view
		if map == null:
			print("PROBE: %s did not open" % map_id)
			continue
		var frame_times := []
		var draw_times := []
		var last := Time.get_ticks_usec()
		var pre := [0]
		var mark_pre := func() -> void: pre[0] = Time.get_ticks_usec()
		RenderingServer.frame_pre_draw.connect(mark_pre)
		for i in (0 if not shots.is_empty() else frame_count):
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frame_times.append((now - last) / 1000.0)
			draw_times.append((now - int(pre[0])) / 1000.0)
			last = now
		RenderingServer.frame_pre_draw.disconnect(mark_pre)
		if not shots.is_empty():
			for i in 12: await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shots.path_join(map_id + ".png"))
			Engine.time_scale = 1.0
		var stages := []
		for i in range(1, timeline.size()):
			stages.append([timeline[i][1], (timeline[i][0] - timeline[i - 1][0]) / 1000.0])
		var worst := 0.0
		var over := 0
		var first10 := 0.0
		for i in frame_times.size():
			worst = maxf(worst, frame_times[i])
			if frame_times[i] > 33.0: over += 1
			if i < 10: first10 += frame_times[i]
		var record := {"map": map_id, "total_ms": total / 1000.0, "stages": stages,
			"world_build_ms": map.world.build_usec / 1000.0, "objects": map.world.objects_loaded,
			"batches": map.world.batches, "frames_first10_ms": first10, "frame_worst_ms": worst,
			"frames_over_33ms": over, "frames": frame_times, "draws": draw_times}
		results.append(record)
		print("PROBE %s %s total %.1f ms (world %.1f ms, %d objects, %d batches)" % [game, map_id, total / 1000.0, record.world_build_ms, record.objects, record.batches])
		for stage: Array in stages: print("PROBE   %-34s %9.1f ms" % [stage[0], stage[1]])
		print("PROBE   first 10 frames %.1f ms, worst frame %.1f ms, %d frames > 33 ms" % [first10, worst, over])
		print("PROBE   frames: " + ", ".join(frame_times.slice(0, 20).map(func(f: float) -> String: return "%.0f" % f)))
		print("PROBE   draws:  " + ", ".join(draw_times.slice(0, 20).map(func(f: float) -> String: return "%.0f" % f)))
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  "))
	view.queue_free()
	for i in 3: await process_frame
	quit(0)

## The map's campaign row, as the chapter list starts it.
func _row(profile: ELProfile, map_id: String) -> Dictionary:
	for campaign_id: String in ELCampaign.available(profile):
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if str(scenario.file_name) == map_id:
				var row := scenario.duplicate()
				row.campaign = campaign_id
				return row
	return {}

func _view_child(node: Node) -> void:
	if node.name == "ChapterLoading": mark("loading cover built")
	if node is ELAdventureView:
		mark("two frames under the cover")
		var map: ELAdventureView = node
		var progress: Callable = map.loading_progress
		map.loading_progress = func(fraction: float) -> void:
			mark({0.15: "map file parse", 0.25: "session start (scripts, AI)", 0.4: "director build",
				0.75: "world sun, fog, colourless", 0.85: "audio, apply settings", 1.0: "effects, presentation, autosave"}.get(fraction, "progress %.2f" % fraction))
			if progress.is_valid(): progress.call(fraction)
		map.child_entered_tree.connect(_map_child)

func _map_child(node: Node) -> void:
	if node is ELAdventureScene:
		mark("map title, art")
		node.child_entered_tree.connect(_world_child)
	elif node is Camera3D: mark("selection rings")
	elif node is ELAdventureAudio: mark("HUD and interface")

func _world_child(node: Node) -> void:
	_world_children += 1
	if node is ELAdventureTerrain: mark("world setup")
	elif _world_children == 2: mark("terrain build")
	elif node is WorldEnvironment: mark("objects + models + batches")
	elif node is ELAdventureEffects: mark("(effects node)")
