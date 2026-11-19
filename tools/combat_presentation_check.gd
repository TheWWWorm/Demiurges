extends SceneTree
## Asset-free regressions for combat presentation. Run with the game's
## Godot 4.7 runtime (the project uses its path-tracing APIs):
##   godot --headless --path game --script ../tools/combat_presentation_check.gd
## No game folders, settings writes, network or imported textures required.
## For a labelled synthetic visual check, run windowed with:
##   ... -- --render --shots=/absolute/output/folder

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_numbers()
	_blood()
	await _captions()
	if OS.get_cmdline_user_args().has("--render"): await _preview()
	print("Combat presentation: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _numbers() -> void:
	var symbols := ELCombatSymbols.new()
	root.add_child(symbols)
	symbols.set_process(false)
	symbols.add_number(Vector3.ZERO, 5, 2)
	symbols.add_number(Vector3.ZERO, -7, 2)
	symbols.add_number(Vector3.ZERO, 0, 2)
	check(symbols.floating.size() == 2 and symbols.floating[0].colour == ELCombatSymbols.RED and symbols.floating[1].colour == ELCombatSymbols.GREEN,
		"damage and healing retain their original colours; zero makes no number")
	check(symbols.floating[0].stack == 0 and symbols.floating[1].stack == 1, "simultaneous numbers retain separate stacking slots")
	symbols._process(2.99)
	check(symbols.floating.size() == 2 and symbols.floating[0].colour.a == 1.0, "rising numbers keep their original opacity through their lifetime")
	symbols._process(0.02)
	check(symbols.floating.is_empty(), "finished numbers are removed")
	symbols.free()

func _blood() -> void:
	var blood := ELCombatBlood.new()
	root.add_child(blood)
	blood.set_process(false)
	var shader := Shader.new()
	shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	blood._drop_node = blood._layer(QuadMesh.new(), material, ELCombatBlood.DROP_LIMIT)
	blood._print_node = blood._layer(PlaneMesh.new(), material, ELCombatBlood.PRINT_LIMIT)
	blood.drops.append({"p": Vector3(0, 0, 1), "previous": Vector3(0, 0, 1), "v": Vector3(0.3, 0, -0.1),
		"size": 0.1, "gravity": -0.1, "terminal": -0.6, "floor": 0.0, "cell": Vector2i.ZERO})
	blood._process(ELCombatBlood.TICK)
	check((blood.drops[0].p as Vector3).is_equal_approx(Vector3(0.3, 0, 0.9)) and (blood.drops[0].v as Vector3).is_equal_approx(Vector3(0.3, 0, -0.2)),
		"blood retains the original fixed-tick movement and gravity")
	blood._process(ELCombatBlood.TICK * 0.5)
	check(blood.drop_position(blood.drops[0]).is_equal_approx(Vector3(0.15, 0.95, 0)), "blood positions interpolate halfway between simulation ticks")
	if DisplayServer.get_name() != "headless":
		var drawn := blood._drop_node.multimesh.get_instance_transform(0).origin
		check(drawn.is_equal_approx(Vector3(0.15, 0.95, 0)), "the rendered blood instance uses that interpolated position")
	else:
		print("SKIP: GPU instance readback (headless dummy renderer; exercised with --render)")
	blood.clear()
	check(blood._clock == 0.0 and blood._drop_node.multimesh.visible_instance_count == 0, "clearing effects also clears interpolation history")
	for burst in 32: blood.burst(Vector3(burst * 10.0, 2, 0))
	check(blood.prints.size() == ELCombatBlood.PRINT_LIMIT and blood.drops.size() <= ELCombatBlood.DROP_LIMIT, "crowded deaths keep both effect pools bounded")
	check((blood.prints[-1].at as Vector3).x > 308.0 and (blood.prints[0].at as Vector3).x >= 160.0, "new impacts replace the oldest prints instead of being hidden")
	blood.advance_prints(1.0)
	check(blood.visible_prints() == ELCombatBlood.PRINT_LIMIT, "the retained prints appear on their original timeline")
	blood.advance_prints(25.0)
	check(blood.prints.is_empty() and blood.visible_prints() == 0, "all prints expire at their original lifetime")
	blood.free()

func _captions() -> void:
	# Compose only the exercised presentation pieces. Never add the battle
	# view itself to the tree, which would start normal game discovery.
	var view: Node = load("res://src/duel/view.gd").new()
	var stage := Node3D.new()
	root.add_child(stage)
	view.stage = stage
	var model := ELModel.new()
	stage.add_child(model)
	model.set_process(false)
	view.models[7] = model
	view._float_text(7, "Resisted", Color.WHITE)
	view._float_text(7, "Blocked", Color.WHITE)
	var labels: Array = view._floating.get(7, [])
	check(labels.size() == 2 and is_equal_approx(labels[0].position.y, 2.0) and is_equal_approx(labels[1].position.y, 2.7), "captions use the original fixed origin and stacking")
	var label: Label3D = labels[0]
	for tween: Tween in get_processed_tweens(): tween.custom_step(0.45)
	check(is_equal_approx(label.position.y, 2.75) and label.modulate.a == 1.0, "original captions rise linearly at constant opacity")
	for tween: Tween in get_processed_tweens(): tween.custom_step(0.46)
	await process_frame
	check(not is_instance_valid(label), "finished captions are freed")
	stage.free()
	view.free()

func _preview() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--render requires a windowed rendering backend")
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("18212a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.72
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.4
	camera.position = Vector3(0, 7.5, 10.5)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	var ui := Control.new()
	root.add_child(ui)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = "SYNTHETIC COMBAT PRESENTATION CHECK"
	heading.position = Vector2(30, 22)
	heading.add_theme_font_size_override("font_size", 24)
	heading.modulate = Color("efd8ad")
	ui.add_child(heading)
	var note := Label.new()
	note.text = "Generated stand-ins and glyphs; no original-game assets.  |  " + RenderingServer.get_current_rendering_method()
	note.position = Vector2(30, 58)
	note.add_theme_font_size_override("font_size", 16)
	note.modulate = Color("b2c0cd")
	ui.add_child(note)
	var battle: Node = load("res://src/duel/view.gd").new()
	battle.stage = stage
	for i in 2:
		var x := -2.15 if i == 0 else 2.15
		var gradient := 0.16 if i == 0 else -0.14
		var floor := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(4.1, 5.0)
		floor.mesh = plane
		floor.position.x = x
		floor.basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3(0, gradient, 1))
		var floor_material := StandardMaterial3D.new()
		floor_material.albedo_color = Color("c4c3b5") if i == 0 else Color("252f38")
		floor_material.roughness = 0.94
		floor.material_override = floor_material
		stage.add_child(floor)
		var model := ELModel.new()
		stage.add_child(model)
		model.set_process(false)
		model.position = Vector3(x, 0, 0)
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.26
		capsule.height = 2.6
		body.mesh = capsule
		body.position.y = 1.3
		var body_material := StandardMaterial3D.new()
		body_material.albedo_color = Color("775644") if i == 0 else Color("7c9eaa")
		body_material.roughness = 0.7
		body.material_override = body_material
		model.add_child(body)
		model.parts.body = body
		battle.models[i + 2] = model
		var description := Label.new()
		description.text = "LIGHT SLOPING GROUND" if i == 0 else "DARK SLOPING GROUND"
		description.position = Vector2(176 + 660 * i, 700)
		description.add_theme_font_size_override("font_size", 19)
		description.modulate = Color("dce3e8")
		ui.add_child(description)
	var symbols := ELCombatSymbols.new()
	ui.add_child(symbols)
	symbols.set_process(false)
	symbols.camera = camera
	symbols.sheet = _synthetic_sheet()
	symbols.figures = [{"top": Vector3(2.15, 2.85, 0), "numbers": ELCombatSymbols.number_row(12, 8, true, false)}]
	symbols.add_number(Vector3(2.15, 3.65, 0), 7, 3)
	symbols.add_number(Vector3(2.15, 3.65, 0), -4, 3)
	symbols.queue_redraw()
	battle._float_text(2, "Resisted", Color("e9e2d3"))
	# Freeze a readable point of the caption instead of racing its rise
	# while shaders compile on a new renderer.
	for tween: Tween in get_processed_tweens(): tween.pause()
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if folder.is_empty():
		check(false, "--render needs --shots=/absolute/output/folder")
	else:
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("combat_presentation_%s.png" % RenderingServer.get_current_rendering_method())
		check(root.get_texture().get_image().save_png(path) == OK, "saved labelled synthetic screenshot: " + path)
	ui.free()
	stage.free()
	battle.free()

## Deliberately simple seven-segment digits, only for this synthetic check.
## Runtime readouts continue to use the original CombatSymbols sheet.
func _synthetic_sheet() -> Texture2D:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var segments := [Rect2i(4, 2, 8, 2), Rect2i(11, 3, 2, 5), Rect2i(11, 8, 2, 5), Rect2i(4, 12, 8, 2),
		Rect2i(3, 8, 2, 5), Rect2i(3, 3, 2, 5), Rect2i(4, 7, 8, 2)]
	var masks := [0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110, 0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111]
	for digit in 10:
		var origin := Vector2i((digit + 1) * 16, 0)
		for segment in 7:
			if masks[digit] & (1 << segment): image.fill_rect(Rect2i(origin + segments[segment].position, segments[segment].size), Color.WHITE)
	for y in range(3, 14): image.fill_rect(Rect2i(12 - y / 2, y, 2, 1), Color.WHITE)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
