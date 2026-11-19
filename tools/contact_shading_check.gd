extends SceneTree
## No original assets required. Logic checks run headless; for a labelled
## synthetic A/B render, add -- --render --shots=/absolute/output/folder.
## Forward+ draws SSAO; Compatibility verifies the disabled fallback.

const ContactShading := preload("res://src/render/contact_shading.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_settings()
	var env := Environment.new()
	env.ambient_light_color = Color(0.8, 0.7, 0.6)
	env.ambient_light_energy = 0.65
	ContactShading.enabled = false
	check(not ContactShading.sync(env) and not env.ssao_enabled, "contact shading starts disabled")
	ContactShading.enabled = true
	var supported := RenderingServer.get_current_rendering_method() == "forward_plus" and not OS.has_feature("mobile") and not OS.has_feature("web")
	check(ContactShading.sync(env) == supported and env.ssao_enabled == supported, "contact shading follows the active renderer and platform")
	check(env.ambient_light_color.is_equal_approx(Color(0.8, 0.7, 0.6)) and is_equal_approx(env.ambient_light_energy, 0.65), "authored ambient colour and strength are unchanged")
	if supported:
		check(is_zero_approx(env.ssao_light_affect) and is_zero_approx(env.ssao_ao_channel_affect) and env.ssao_radius < 0.6, "short-range occlusion leaves direct light and material AO unchanged")
	env.set_meta(ELEffectLook.TRACED, true)
	check(not ContactShading.sync(env) and not env.ssao_enabled, "path tracing suppresses contact shading")
	env.remove_meta(ELEffectLook.TRACED)
	check(ContactShading.sync(env) == supported and env.ssao_enabled == supported, "raster contact shading returns after path tracing stops")
	ContactShading.enabled = false
	check(not ContactShading.sync(env) and not env.ssao_enabled, "disabling the preference removes it immediately")
	check(not ContactShading.sync(null), "an absent environment needs no special lifecycle handling")
	# Exercise the game's real use/sync and PT ownership route, rather than
	# only the small helper. No ray-tracing device is required for ownership.
	ELEffectLook.use({"contact_shading": true})
	ELEffectLook.sync(env)
	check(env.ssao_enabled == supported, "shared presentation preferences apply contact shading to a live environment")
	var tracing := ELPathTracing.new()
	tracing._env = env
	tracing._bloom(true)
	check(env.has_meta(ELEffectLook.TRACED) and not env.ssao_enabled, "the actual PT activation hook disables raster contact shading")
	tracing._bloom(false)
	check(not env.has_meta(ELEffectLook.TRACED) and env.ssao_enabled == supported, "the actual PT deactivation hook restores the current raster preference")
	tracing._bloom(true)
	ELEffectLook.use({"contact_shading": false})
	ELEffectLook.sync(env)
	tracing._bloom(false)
	check(not env.ssao_enabled, "changing the preference during PT is respected when PT stops")
	tracing.free()
	ELEffectLook.use({})
	if OS.get_cmdline_user_args().has("--render"): await _render()
	ContactShading.enabled = false
	print("Contact shading: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _settings() -> void:
	var settings := ELSettings.new()
	check(settings.values.get("contact_shading") == false, "new and existing settings default to no contact shading")
	settings.use_edition("el1")
	settings.values.contact_shading = true
	settings.use_edition("el2")
	check(settings.values.contact_shading == true, "the preference is shared across editions")
	# Only this disposable file is written. The player's settings are never
	# read or changed; the normal settings serializer is still exercised.
	var folder := OS.get_temp_dir().path_join("demiurges_contact_shading_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("settings.json")
	check(settings.save_file(path), "the new preference saves through the ordinary settings serializer")
	var loaded := ELSettings.new()
	loaded.load_file(path)
	check(loaded.values.contact_shading == true, "a saved preference survives reload")
	var plain := FileAccess.open(path, FileAccess.WRITE)
	plain.store_string('{"version":6,"shared":{}}')
	plain.close()
	var legacy := ELSettings.new()
	legacy.load_file(path)
	check(legacy.values.contact_shading == false, "a previous settings file without this key stays unchanged visually")
	for filename: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	var help := "Subtle shade where lit figures meet the ground and nearby surfaces. Requires Forward+; switches off during path tracing. Unlit scenery is unchanged."
	check(ELRemakeText.russian("Contact shading") != "Contact shading" and ELRemakeText.russian(help) != help, "the setting name and complete help have Russian translations")

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "render mode requires a windowed renderer")
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	world.environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("18212a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 0.52
	sun.shadow_enabled = false
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.2
	camera.position = Vector3(6.5, 6.0, 9.0)
	camera.look_at(Vector3(0, 0.75, 0))
	camera.current = true
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9, 7)
	floor.mesh = plane
	# Exercise the actual arena lighting shader, not only stock materials.
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color("999183"))
	var floor_material := ShaderMaterial.new()
	floor_material.shader = preload("res://src/render/arena_lit.gdshader")
	floor_material.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(image))
	floor_material.set_shader_parameter("ambient_light", Vector3.ONE * 0.65)
	floor_material.set_shader_parameter("encoded_sun_pass", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	floor.material_override = floor_material
	stage.add_child(floor)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 2.2
	capsule.radial_segments = 10
	capsule.rings = 4
	_mesh(stage, capsule, Vector3(-0.75, 1.1, 0.15), Color("858f80"))
	for feet in [-1.0, -0.5]:
		var foot := BoxMesh.new()
		foot.size = Vector3(0.30, 0.28, 0.62)
		_mesh(stage, foot, Vector3(feet, 0.14, 0.38), Color("616958"))
	var plinth := BoxMesh.new()
	plinth.size = Vector3(1.45, 0.55, 1.25)
	_mesh(stage, plinth, Vector3(1.05, 0.275, -0.45), Color("8a8073"))
	var column := CylinderMesh.new()
	column.top_radius = 0.36
	column.bottom_radius = 0.44
	column.height = 1.2
	column.radial_segments = 8
	_mesh(stage, column, Vector3(1.05, 1.15, -0.45), Color("9f9380"))
	var wall := BoxMesh.new()
	wall.size = Vector3(3.8, 0.8, 0.28)
	_mesh(stage, wall, Vector3(0, 0.4, -1.75), Color("7a7e82"))
	var unlit := PlaneMesh.new()
	unlit.size = Vector2(1.2, 1.2)
	var control := _mesh(stage, unlit, Vector3(-2.35, 0.02, 0.2), Color("6b8795"))
	(control.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ui := Control.new()
	root.add_child(ui)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.position = Vector2(30, 22)
	heading.add_theme_font_size_override("font_size", 24)
	heading.modulate = Color("efd8ad")
	ui.add_child(heading)
	var note := Label.new()
	note.position = Vector2(30, 62)
	note.text = "Generated geometry; actual arena ground shader. No original-game assets. Sun shadows disabled to isolate contact shade."
	note.add_theme_font_size_override("font_size", 15)
	note.modulate = Color("b2c0cd")
	ui.add_child(note)
	var footer := Label.new()
	footer.position = Vector2(30, 740)
	footer.text = "Short-range ambient occlusion only. Blue tile is an unlit control. " + RenderingServer.get_current_rendering_method()
	footer.add_theme_font_size_override("font_size", 16)
	footer.modulate = Color("c4d0d9")
	ui.add_child(footer)
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if folder.is_empty():
		check(false, "render mode needs --shots=/absolute/output/folder")
		ui.free()
		stage.free()
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var captures: Array[Image] = []
	for on: bool in [false, true]:
		ContactShading.enabled = on
		ContactShading.sync(env)
		heading.text = "SYNTHETIC CONTACT SHADING CHECK — " + ("ON" if on else "OFF")
		for frame in 16: await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		captures.append(shot)
		var path := folder.path_join("contact_shading_%s_%s.png" % [RenderingServer.get_current_rendering_method(), "on" if on else "off"])
		check(shot.save_png(path) == OK, "saved synthetic A/B: " + path)
	# Sample projection-derived floor points, safely away from object edges,
	# and the centre of the unlit tile. Report the result without assuming
	# the same precise framebuffer encoding across drivers.
	var darkening := {}
	for entry: Array in [["open floor", Vector3(2.8, 0, 1.8)], ["figure contact", Vector3(-0.75, 0, 0.82)],
			["plinth contact", Vector3(1.05, 0, 0.31)], ["unlit control", Vector3(-2.35, 0.02, 0.2)]]:
		var pixel := Vector2i(camera.unproject_position(entry[1]))
		var before := _brightness(captures[0], pixel)
		var after := _brightness(captures[1], pixel)
		darkening[entry[0]] = before - after
		print("SAMPLE %s: %.5f -> %.5f (delta %.5f) at %s" % [entry[0], before, after, after - before, pixel])
	check(absf(darkening["open floor"]) < 0.006 and absf(darkening["unlit control"]) < 0.006, "rendered open terrain and unlit art keep their brightness")
	if ContactShading.available():
		check(darkening["figure contact"] > 0.003 and darkening["plinth contact"] > 0.003, "rendered contact areas receive local ambient shade")
	else:
		check(absf(darkening["figure contact"]) < 0.001 and absf(darkening["plinth contact"]) < 0.001, "an unsupported renderer remains visually unchanged")
	ui.free()
	stage.free()

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.86
	node.material_override = material
	parent.add_child(node)
	return node

func _brightness(image: Image, pixel: Vector2i) -> float:
	var sum := 0.0
	for y in range(pixel.y - 2, pixel.y + 3):
		for x in range(pixel.x - 2, pixel.x + 3):
			var colour := image.get_pixel(x, y)
			sum += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
	return sum / 25.0
