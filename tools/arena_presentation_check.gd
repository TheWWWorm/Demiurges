extends SceneTree
## Asset-free checks of arena ground detail, water and mist presentation.
## No profiles are mounted and no preferences are read or written.
##
##   godot --headless --path game --script ../tools/arena_presentation_check.gd
##
## To exercise the actual shaders, use a windowed renderer and append
## -- --render --shots=/absolute/output/folder. The pictures are synthetic
## material fixtures, not screenshots of either original game's arenas.

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := _fixture()
	var arena: ELArena = fixture.arena
	var ground: MeshInstance3D = fixture.ground
	var original: Material = ground.material_override
	var grain: Texture2D = fixture.grain
	var original_bytes := grain.get_image().get_data()
	arena.set_detail(true)
	var detail := ground.material_override as ShaderMaterial
	check(detail != null and detail != original, "terrain detail installs its own material")
	check(detail.get_shader_parameter("base_texture") == fixture.albedo, "ground detail keeps the authored base texture")
	check(detail.get_shader_parameter("detail_texture") == grain, "ground detail uses the provided grain texture")
	check(grain.get_image().get_data() == original_bytes and grain.get_width() == 64, "finding the neutral grain leaves its pixels and size intact")
	arena.set_detail(false)
	check(ground.material_override == original, "turning detail off restores the exact original material")
	arena.set_detail(true)
	check(ground.material_override == detail and arena._detail_materials.size() == 1, "repeated toggles reuse one detail material")
	check(arena._lit_materials.count(detail) == 1, "repeated toggles register detail lighting once")

	var fog := ELArena.GroundFog.new()
	fog.build(Color(0.67, 0.70, 0.69, 0.39), 0.0)
	arena.add_child(fog)
	arena._ground_fog = fog
	var sea := MeshInstance3D.new()
	sea.mesh = PlaneMesh.new()
	sea.material_override = ShaderMaterial.new()
	sea.material_override.shader = ELArena.SEA_SHADER
	arena.add_child(sea)
	arena._sea = sea
	arena._atmosphere_reference = arena._surface_light()
	arena._sync_light()
	var sea_material := sea.material_override as ShaderMaterial
	var fog_material := fog.material_override as ShaderMaterial
	check((sea_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE), "water preserves its palette at the authored light level")
	check((fog_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE), "mist preserves its palette at the authored light level")
	var mist_colour: Color = fog_material.get_shader_parameter("fog_colour")
	var mist_wake: Texture2D = fog_material.get_shader_parameter("wake_mask")
	var ambient := arena.environment_settings.ambient_light_energy
	var sunlight := arena.light.light_energy
	arena.environment_settings.ambient_light_energy = ambient * 0.25
	arena.light.light_energy = sunlight * 0.25
	arena._sync_light()
	check((sea_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE * 0.25), "water follows a quarter-strength light in linear space")
	check((fog_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE * 0.25), "mist follows the same live light change")
	check(fog_material.get_shader_parameter("fog_colour") == mist_colour and fog_material.get_shader_parameter("wake_mask") == mist_wake, "lighting leaves mist density, palette and creature wake texture intact")
	arena.environment_settings.ambient_light_energy = 0.0
	arena.light.light_energy = 0.0
	arena._sync_light()
	check((sea_material.get_shader_parameter("scene_light_gain") as Vector3).is_zero_approx(), "fully extinguished scene light does not leave bright sea behind")
	check((fog_material.get_shader_parameter("scene_light_gain") as Vector3).is_zero_approx(), "fully extinguished scene light does not leave luminous mist behind")
	arena.environment_settings.ambient_light_energy = ambient
	arena.light.light_energy = sunlight
	arena._sync_light()
	check((sea_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE), "the water palette recovers after scene light returns")
	var sun_colour := arena.light.light_color
	arena.light.light_color = Color(1.0, 0.4, 0.2)
	arena._sync_light()
	var tinted: Vector3 = sea_material.get_shader_parameter("scene_light_gain")
	check(tinted.y < tinted.x and tinted.z < tinted.x, "a sun-only colour change tints water even with unchanged ambient light")
	arena.light.light_color = sun_colour
	arena.environment_settings.set_meta(ELEffectLook.TRACED, true)
	arena.set_secondary_traced(true)
	arena.light.shadow_enabled = false
	arena._sync_light()
	check((sea_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE), "switching to traced shadows does not recolour the atmosphere")
	arena.environment_settings.remove_meta(ELEffectLook.TRACED)
	arena.set_secondary_traced(false)
	arena.light.shadow_enabled = true
	arena._sync_light()
	check((fog_material.get_shader_parameter("scene_light_gain") as Vector3).is_equal_approx(Vector3.ONE), "restoring raster shadows preserves the mist palette")
	var before_sun: Vector3 = sea_material.get_shader_parameter("sun_direction")
	arena.light.rotation.x += 0.15
	arena._sync_light()
	check(not (sea_material.get_shader_parameter("sun_direction") as Vector3).is_equal_approx(before_sun), "water highlights follow a changed sun direction even if ambient colour stays fixed")
	check(ELArena.atmosphere_gain(Vector3(8, 0, 0.3), Vector3(0, 0.2, 0.3)).is_finite(), "a black authored light channel produces finite atmosphere colour")
	check(ELArena.atmosphere_gain(Vector3(8, 8, 8), Vector3.ONE).is_equal_approx(Vector3.ONE * 2.0), "an extreme light flash is bounded")
	check(ELArena.atmosphere_gain(Vector3.ZERO, Vector3.ZERO).is_equal_approx(Vector3.ONE), "an all-black reference has a stable neutral ratio")
	var deck := MeshInstance3D.new()
	var authored := PlaneMesh.new()
	var split := ArrayMesh.new()
	arena._ship_surface = deck
	arena._ship_original_mesh = authored
	arena._ship_deck_mesh = split
	arena.set_water(true)
	check(deck.mesh == split and sea.visible, "enhanced water selects the deck-only surface and shows the sea")
	arena.set_water(false)
	check(deck.mesh == authored and not sea.visible, "water off restores the complete original surface")
	deck.free()
	arena.free()
	_hanging_scenery_checks()
	if OS.get_cmdline_user_args().has("--render"):
		if DisplayServer.get_name() == "headless":
			check(false, "shader probes require a real renderer; do not use --headless with --render")
		else:
			await _render_probes()
	print("ARENA PRESENTATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## A tall piece of scenery: one box part spanning `low` to `high` (arena space).
func _scenery(arena: ELArena, low: Vector3, high: Vector3) -> ELModel:
	var model := ELModel.new()
	arena.add_child(model)
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = high - low
	part.mesh = box
	part.position = (low + high) * 0.5
	model.add_child(part)
	model.parts.body = part
	arena._camera_obstacles.append(model)
	return model

## Banners hanging over the fight (the White Lord's hall) give way to the
## battle camera wherever they cover a hero's or a creature's place (player
## report: a banner across the enemy's creatures); a tree crown or a pillar
## standing on the ground keeps the older corridor test.
func _hanging_scenery_checks() -> void:
	var arena := ELArena.new()
	root.add_child(arena)
	var hero: Vector3 = ELMeleePlayback.hero_position(1)
	var camera := Vector3(-20, 12, 0)
	# On the line from the camera to the far hero's chest, short of the target line.
	var across := camera.lerp(hero + Vector3(0, 1.5, 0), 0.75)
	var covering := _scenery(arena, across - Vector3(0.3, 1.0, 0.6), across + Vector3(0.3, 5.0, 0.6))
	var aside := _scenery(arena, Vector3(0, 3, 20), Vector3(0.6, 10, 21.2))
	var crown := _scenery(arena, across - Vector3(4, 0, 4) + Vector3(0, 0.2, 0), across + Vector3(4, 6, 4))
	var pillar := _scenery(arena, Vector3(-8, 0, 6), Vector3(-7.4, 10, 6.6))
	var hanging := arena._hanging_models()
	check(hanging.has(covering) and hanging.has(aside), "slender scenery hung clear of the ground counts as hanging over the fight")
	check(not hanging.has(crown) and not hanging.has(pillar), "wide crowns and pillars standing on the ground do not")
	arena.clear_camera_view(camera, Vector3(0, 0, 8))
	check(not covering.visible, "a hanging banner between the camera and a hero's place is hidden")
	check(aside.visible and pillar.visible, "hanging scenery clear of every place stays in view")
	arena.clear_camera_view(Vector3(20, 12, 0), Vector3(0, 0, 8))
	check(covering.visible, "the banner returns once the camera no longer looks through it")
	arena.free()

func _texture(colour: Color, grain := false) -> ImageTexture:
	var image := Image.create_empty(64, 64, true, Image.FORMAT_RGBA8)
	image.fill(colour)
	if grain:
		for y in 64:
			for x in 64:
				var grain_value := 0.5 + 0.22 * sin(x * TAU / 16.0) * cos(y * TAU / 12.8) + 0.08 * sin((x + y) * TAU / 8.0)
				image.set_pixel(x, y, Color(grain_value, grain_value, grain_value))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _fixture() -> Dictionary:
	var arena := ELArena.new()
	var profile := ELProfile.new()
	var grain := _texture(Color.WHITE, true)
	profile._textures[ELArchive.key("CombatScenes/probe-grain")] = grain
	arena._profile = profile
	arena.definition = {"DetailTextureName": "probe-grain", "DetailTextureTileSize": 2.0}
	var ground := ELModel.new()
	arena._ground = ground
	arena.add_child(ground)
	var part := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	part.mesh = plane
	var albedo := _texture(Color(0.38, 0.33, 0.24))
	var base := ShaderMaterial.new()
	base.shader = ELArena.LIT_SHADER
	base.set_shader_parameter("albedo_texture", albedo)
	base.set_shader_parameter("albedo_tint", Color.WHITE)
	base.set_shader_parameter("alpha_cutoff", 0.5)
	part.material_override = base
	part.set_meta("albedo", albedo)
	ground.add_child(part)
	ground.parts.surface = part
	arena._lit_materials.append(base)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.025, 0.03, 0.04)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	world.environment.ambient_light_energy = 0.25
	arena.environment_settings = world.environment
	arena.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 0.75
	arena.light = light
	arena.add_child(light)
	root.add_child(arena)
	return {"arena": arena, "ground": part, "albedo": albedo, "grain": grain}

func _render_probes() -> void:
	root.size = Vector2i(960, 640)
	var fixture := _fixture()
	var arena: ELArena = fixture.arena
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.position = Vector3(0.0, 5.0, 6.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	arena.set_detail(true)
	arena._sync_light()
	var material := fixture.ground.material_override as ShaderMaterial
	material.set_shader_parameter("detail_height", 0.0)
	var flat := await _frame("terrain_grain")
	material.set_shader_parameter("detail_height", 0.028)
	var relief := await _frame("terrain_relief")
	check(_difference(flat, relief) > 0.0001, "rendered surface relief changes the floor's directional shading")
	check(absf(_brightness(flat) - _brightness(relief)) < 0.04, "rendered relief preserves the overall ground brightness")
	var water_material := ShaderMaterial.new()
	water_material.shader = ELArena.SEA_SHADER
	water_material.set_shader_parameter("ship_atlas", fixture.albedo)
	water_material.set_shader_parameter("sun_direction", Vector3(0.25, 0.8, 0.45).normalized())
	fixture.ground.material_override = water_material
	fixture.ground.position.z = 17.0
	camera.position = Vector3(0.0, 6.0, 23.0)
	camera.look_at(Vector3(0.0, 0.0, 17.0))
	var water := await _frame("water_lit")
	water_material.set_shader_parameter("scene_light_gain", Vector3.ONE * 0.25)
	var dim := await _frame("water_dimmed")
	check(_brightness(dim) < _brightness(water) * 0.8, "rendered water visibly follows dimmed scene light")
	fixture.ground.position.z = 0.0
	fixture.ground.material_override = material
	camera.position = Vector3(0.0, 5.0, 6.0)
	camera.look_at(Vector3.ZERO)
	var fog := ELArena.GroundFog.new()
	fog.build(Color(0.67, 0.70, 0.69, 0.39), 0.0)
	arena.add_child(fog)
	fog.stir(Vector2(-3, 0), Vector2(3, 0), 1.0)
	await _frame("mist_wake")
	arena.free()

func _frame(label: String) -> Image:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var directory := arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(directory)
			image.save_png(directory.path_join("%s_%s.png" % [RenderingServer.get_current_rendering_method(), label]))
	return image

func _brightness(image: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(80, mini(image.get_height(), 560), 4):
		for x in range(120, mini(image.get_width(), 840), 4):
			var colour := image.get_pixel(x, y)
			sum += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
			count += 1
	return sum / maxf(1.0, count)

func _difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(80, mini(a.get_height(), 560), 4):
		for x in range(120, mini(a.get_width(), 840), 4):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			sum += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
			count += 3
	return sum / maxf(1.0, count)
