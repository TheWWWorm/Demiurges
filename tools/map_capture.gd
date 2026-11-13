extends SceneTree
## Opens a second-game map straight from the command line (a custom map or a
## shipped one, as the single-mission list starts it) and saves frames of it,
## for visual checks of map effects and the fog. Not headless: it renders.
##
##   godot --path game --resolution 1280x720 --script ../tools/map_capture.gd -- \
##       --map=<id> --shots=<folder> [--times=4,10] [--map-root=<folder>] \
##       [--reveal-after=<s> --reveal-move=<dx>,<dy>]
##
## --map: the map id or its end ("T100" finds Maps/Custom/T100).
## --map-root: a folder holding the custom map's files, read as one more
##   Maps/Custom folder (as custom_maps_check.gd's folders).
## --times: seconds after the map opened for each frame (shot-<s>.png).
## --reveal-after: after the last frame, moves the local player's first hero
##   by --reveal-move tiles (default 8,0) and saves the fog reveal at 0, 0.15,
##   0.3, 0.5, 0.8, 1.2 and 2.5 s (reveal-<ms>.png).
## The game's own --capture flag keeps the front end closed; this script
## passes it through itself, so the game never writes that capture.

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.split("=", true, 1)[1]
	return fallback

func _initialize() -> void:
	var root_folder := _arg("map-root", "")
	if not root_folder.is_empty(): ELCustomMaps.extra_roots.append(root_folder.replace("\\", "/"))
	_run.call_deferred()

func _shot(folder: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
	print("frame ", folder.path_join(name + ".png"))

func _run() -> void:
	if _arg("capture", "").is_empty():
		printerr("Pass --capture=<unused.png> --capture-after=99999 after -- to keep the front end closed.")
		quit(1)
		return
	var scene: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 5: await process_frame
	if not scene.profiles.has("el2"):
		printerr("Etherlords II is required (user://profiles.json).")
		quit(1)
		return
	var profile: ELProfile = scene.profiles["el2"]
	var wanted := _arg("map", "").to_lower()
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(profile):
		var id := str(found.id).to_lower()
		if id == wanted or id.ends_with("/" + wanted): entry = found
	if wanted.is_empty() or entry.is_empty():
		printerr("No map " + wanted)
		quit(1)
		return
	await scene._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var view: Node = scene.campaign_view
	if view == null:
		printerr("The map did not open")
		quit(1)
		return
	var folder := _arg("shots", OS.get_user_data_dir().path_join("map_capture"))
	DirAccess.make_dir_recursive_absolute(folder)
	var opened := Time.get_ticks_msec()
	for time: String in _arg("times", "6").split(","):
		while Time.get_ticks_msec() - opened < float(time) * 1000.0: await process_frame
		await _shot(folder, "shot-" + time)
	if not _arg("reveal-after", "").is_empty():
		while Time.get_ticks_msec() - opened < float(_arg("reveal-after", "0")) * 1000.0: await process_frame
		await _reveal(view, folder)
	quit()

func _reveal(view: Node, folder: String) -> void:
	var state: ELAdventureSession = view.state
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and int(item.get("owner", 0)) == state.current_player:
			hero = item
			break
	if hero.is_empty():
		printerr("No hero to move")
		return
	var move := _arg("reveal-move", "8,0").split(",")
	hero.x = int(hero.x) + int(move[0])
	hero.y = int(hero.y) + int(move[1] if move.size() > 1 else "0")
	ELFog.refresh(state)
	view.world.update_object(hero)
	view.following = -1
	view.target = ELAdventureScene.world_position(float(hero.x), float(hero.y))
	var started := Time.get_ticks_msec()
	for time: float in [0.0, 0.15, 0.3, 0.5, 0.8, 1.2, 2.5]:
		while Time.get_ticks_msec() - started < time * 1000.0: await process_frame
		await _shot(folder, "reveal-%04d" % int(time * 1000.0))
