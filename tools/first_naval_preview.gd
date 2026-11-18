extends SceneTree
## Reproducible schematic previews from synthetic content, plus optional
## native-renderer checks of the fallback ship and setup screen.
## godot --headless --path game --script ../tools/first_naval_preview.gd -- --out=/absolute/directory
## Omit --headless and add --render to capture actual rendered frames too.
const Fixture = preload("first_random_map_fixture.gd")
var output := "user://naval_previews"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var profile: ELProfile = Fixture.profile()
	if "--render" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			printerr("--render requires a real display and renderer.")
			quit(1)
			return
		await _render_ship(profile)
		await _render_setup(profile)
	var reports := {}
	for layout: String in ELFirstRandomMap.LAYOUTS:
		var generator := ELFirstRandomMap.new()
		var map := generator.generate(profile, {"seed": "naval-worlds", "size": 128, "players": 4, "layout": layout, "naval": true})
		if map == null:
			printerr(layout + ": " + generator.error)
			quit(1)
			return
		var result := ELFirstRandomMapScreen.preview_image(map).save_png(output.path_join(layout + ".png"))
		if result != OK:
			printerr("Could not save preview: " + layout)
			quit(1)
			return
		reports[layout] = generator.report
	var file := FileAccess.open(output.path_join("map_reports.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	print("NAVAL PREVIEWS: eight generated schematics" + (", ship and setup rendered" if "--render" in OS.get_cmdline_user_args() else ""))
	quit()

func _capture(name: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	if result != OK: printerr("Could not capture " + name)

func _render_ship(profile: ELProfile) -> void:
	root.size = Vector2i(960, 640)
	var world := Node3D.new()
	root.add_child(world)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	sea.mesh = plane
	sea.material_override = ELFirstNavalVisuals._material(Color("294f68"))
	sea.position = Vector3(8, -0.08, -8)
	world.add_child(sea)
	var land := MeshInstance3D.new()
	var beach := PlaneMesh.new()
	beach.size = Vector2(6, 16)
	land.mesh = beach
	land.material_override = ELFirstNavalVisuals._material(Color("818457"))
	land.position = Vector3(3, -0.01, -8)
	world.add_child(land)
	var map := ELAdventureMap.new()
	map.profile = profile
	map.width = 8
	map.height = 8
	map.set_meta("first_naval", {"version": 1, "ports": [{"id": 0, "land": [2, 4], "water": [3, 4]}]})
	var docks := ELFirstNavalVisuals.new()
	world.add_child(docks)
	docks.build(map)
	docks.set_fog(PackedByteArray())
	var boat := ELModel.new()
	world.add_child(boat)
	ELFirstNavalVisuals.build_boat(boat, profile, 2)
	boat.position = Vector3(8.0, 0, -9.4)
	boat.rotation.y = -0.35
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("223746")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	camera.position = Vector3(11.5, 7.0, -3.2)
	camera.look_at(Vector3(6.5, 0.3, -9.0))
	camera.current = true
	await _capture("ship_and_harbor")
	world.queue_free()
	await process_frame

func _render_setup(profile: ELProfile) -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1000, 740)
	var screen := ELFirstRandomMapScreen.new()
	root.add_child(screen)
	screen.build(profile)
	screen.configuration = ELFirstRandomMap.normalize({"seed": "naval-worlds", "size": 128, "players": 4, "layout": "archipelago", "naval": true})
	screen._sync_fields()
	screen.popup_centered_clamped(Vector2i(920, 680), 0.94)
	await screen.generate_preview()
	await _capture("naval_setup")
	print("SETUP full: window=", screen.size, " minimum=", screen.get_contents_minimum_size(), " root=", root.size, " rootcontent=", root.content_scale_size, " preview=", screen._preview.get_global_rect(), " play=", screen._play.get_global_rect())
	root.size = Vector2i(800, 600)
	screen.size = Vector2i(740, 550)
	await _capture("naval_setup_800x600")
	print("SETUP small: window=", screen.size, " minimum=", screen.get_contents_minimum_size(), " root=", root.size, " preview=", screen._preview.get_global_rect(), " play=", screen._play.get_global_rect())
	screen.queue_free()
	await process_frame
