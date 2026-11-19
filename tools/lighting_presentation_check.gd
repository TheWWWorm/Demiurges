extends SceneTree
## Asset-free checks for light priority, lamp recycling and shadow stability.
## Add -- --render --shots=/absolute/folder for real-renderer evidence.

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _source(at: Vector3, power := 4.0, rank := 0) -> Array:
	return [at, 0.5, Vector3(1.0, 0.55, 0.23) * power, rank == 2, 1 if rank == 1 else 0]

func _run() -> void:
	var lights := ELGlowLights.new()
	root.add_child(lights)
	var spell := _source(Vector3(0, 2, 0))
	var fire := _source(Vector3(0.1, 2, 0), 30.0, 2)
	var inputs := [spell, fire]
	var before := inputs.duplicate(true)
	var merged := ELGlowLights.merged(inputs)
	check(merged.size() == 2, "a spell beside a brighter standing fire keeps its own light and shadow eligibility")
	check(inputs == before, "light grouping leaves effect-owned source data unchanged")
	check(ELGlowLights.merged([spell, _source(Vector3(0.2, 2, 0))]).size() == 1, "patches of the same spell still share one lamp")
	var figures := []
	for i in ELGlowLights.LIMIT: figures.append(_source(Vector3(i * 10, 2, 0), 8.0, 1))
	lights.show_sources(figures, 0.0)
	check(lights.lit() == ELGlowLights.LIMIT, "six character glows fill the lamp budget")
	var incoming := _source(Vector3(-8, 2, 0), 12.0)
	lights.show_sources([incoming], 1.0 / 60.0)
	var arrives := false
	var retained := 0
	for lamp: OmniLight3D in lights.get_children():
		if lamp.visible and lamp.global_position.is_equal_approx(incoming[0]): arrives = true
		if lamp.visible and lamp.get_meta(&"figure", false): retained += 1
	check(arrives and retained == ELGlowLights.LIMIT - 1, "an incoming spell takes one slot while five character glows fade smoothly")
	check(lights.get_child_count() == ELGlowLights.LIMIT and lights.lit() <= ELGlowLights.LIMIT, "replacing a source allocates no extra lamp or shadow-map node")
	for frame in 120:
		var moving := []
		for i in ELGlowLights.LIMIT: moving.append(_source(Vector3(i * 10, 2, frame * 6), 3.0 + i))
		lights.show_sources(moving, 1.0 / 60.0)
	check(lights.get_child_count() == ELGlowLights.LIMIT and lights.lit() == ELGlowLights.LIMIT, "rapidly replaced effects keep the actual lamp pool bounded, not only the visible count")
	for frame in 120: lights.show_sources([], 1.0 / 60.0)
	check(lights.lit() == 0, "all departed spell lights finish fading")
	var origin := Vector3(0, 2, 0)
	lights.show_sources([_source(origin, 8.0, 1)], 0.0)
	var figure_lamp: OmniLight3D
	for lamp: OmniLight3D in lights.get_children():
		if lamp.visible: figure_lamp = lamp
	var figure_energy := figure_lamp.light_energy
	lights.show_sources([_source(origin, 12.0)], 1.0 / 60.0)
	check(figure_lamp.get_meta(&"figure", false) and figure_lamp.light_energy > figure_energy * 0.9, "a spell at a hero's feet does not steal or recolour the hero's continuing aura")
	lights.free()
	_shadow_checks()
	if "--render" in OS.get_cmdline_user_args(): await _render()
	print("LIGHTING PRESENTATION: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _shadow_checks() -> void:
	var lights := ELGlowLights.new()
	root.add_child(lights)
	var a := _source(Vector3(-4, 3, 0), 4.0)
	var b := _source(Vector3(4, 3, 0), 3.8)
	lights.show_sources([a, b], 0.0)
	if ELGlowLights.shadows_available():
		var owner := lights._shadow_lamp
		check(owner != null and owner.global_position.is_equal_approx(a[0]), "the initially brighter spell supplies the single shadow")
		var stable := true
		for frame in 40:
			b[2] = Vector3(1.0, 0.55, 0.23) * (4.2 if frame % 2 else 3.8)
			lights.show_sources([a, b], 0.0)
			stable = stable and lights._shadow_lamp == owner
		check(stable, "minor brightness crossings do not hand the shadow back and forth")
		b[2] = Vector3(1.0, 0.55, 0.23) * 12.0
		lights.show_sources([a, b], 0.0)
		check(lights._shadow_lamp != owner and lights._shadow_lamp.global_position.is_equal_approx(b[0]), "a clearly brighter spell takes over the shadow")
		lights.show_sources([a], 0.0)
		check(lights._shadow_lamp == owner, "a vanished caster immediately yields its shadow to a live spell")
	else:
		check(lights._shadow_lamp == null, "Compatibility retains its non-shadowing spell-light fallback")
	lights.show_sources([_source(Vector3.ZERO, 10.0, 1), _source(Vector3(10, 2, 0), 20.0, 2)], 0.0)
	var shadows := 0
	for lamp: OmniLight3D in lights.get_children():
		if lamp.shadow_enabled: shadows += 1
	check(shadows == 0, "standing fires and character glows never inherit a recycled spell's shadow")
	lights.free()

func _mesh(parent: Node3D, geometry: Mesh, at: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = geometry
	node.position = at
	var look := StandardMaterial3D.new()
	look.albedo_color = colour
	look.roughness = 1.0
	look.metallic_specular = 0.0
	node.material_override = look
	parent.add_child(node)
	return node

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "render checks require a windowed graphics driver")
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("111821")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.12
	stage.add_child(world)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(9, 10, 14)
	camera.look_at(Vector3(0, 0.4, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.current = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 12)
	_mesh(stage, plane, Vector3.ZERO, Color("8c8a81"))
	for x in [-1.0, 1.0]:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.35
		pillar.bottom_radius = 0.45
		pillar.height = 2.4
		pillar.radial_segments = 12
		_mesh(stage, pillar, Vector3(x, 1.2, 0), Color("8e9eac"))
	for x in [-4.0, 4.0]:
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		var source := _mesh(stage, sphere, Vector3(x, 3, 0), Color("ffbe72"))
		(source.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lights := ELGlowLights.new()
	stage.add_child(lights)
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	var heading := Label.new()
	heading.position = Vector2(30, 24)
	heading.add_theme_font_size_override("font_size", 24)
	heading.modulate = Color("eddbba")
	overlay.add_child(heading)
	var note := Label.new()
	note.position = Vector2(30, 64)
	note.text = "Actual pooled spell lights on generated geometry. No original assets. " + RenderingServer.get_current_rendering_method()
	note.add_theme_font_size_override("font_size", 15)
	overlay.add_child(note)
	var folder := "user://lighting_presentation"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(folder)
	var brightness := []
	for phase in 3:
		var sources := []
		if phase > 0:
			sources = [_source(Vector3(-4, 3, 0), 4.0), _source(Vector3(4, 3, 0), 3.8 if phase == 1 else 12.0)]
		lights.show_sources(sources, 0.0)
		heading.text = ["SYNTHETIC SPELL LIGHTING — ambient only", "SYNTHETIC SPELL LIGHTING — first spell casts", "SYNTHETIC SPELL LIGHTING — stronger second spell takes over"][phase]
		if not ELGlowLights.shadows_available() and phase > 0:
			heading.text = "SYNTHETIC SPELL LIGHTING — Compatibility lighting without shadows"
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var at := Vector2i(camera.unproject_position(Vector3(-4, 0, 0)))
		var colour := shot.get_pixelv(at)
		brightness.append(Vector3(colour.r, colour.g, colour.b).length())
		var path := folder.path_join("lighting_%s_%d.png" % [RenderingServer.get_current_rendering_method(), phase])
		check(shot.save_png(path) == OK, "saved actual spell-light render: " + path)
	check(brightness[1] > brightness[0] + 0.05, "a generated spell visibly lights nearby ground (%.3f -> %.3f)" % [brightness[0], brightness[1]])
	overlay.free()
	stage.free()
