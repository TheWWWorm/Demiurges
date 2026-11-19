extends SceneTree
## Asset-free atlas/culling regression. Use -- --render --shots=/folder for
## actual combat and map shader A/B captures; no game data or settings needed.

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_atlas_limits()
	_bounds()
	_cache_and_fades()
	if "--render" in OS.get_cmdline_user_args(): await _render()
	print("EFFECTS PRESENTATION: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _image(size := 64, mipmaps := true) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	# Atlas index zero is the lower-left cell; every neighbour is a visibly
	# different colour, so any red/blue in that green frame is contamination.
	for y in size:
		for x in size:
			image.set_pixel(x, y, Color.GREEN if x < size / 2 and y >= size / 2 else Color.RED)
	if mipmaps: image.generate_mipmaps()
	return image

func _atlas_limits() -> void:
	check(ELParticleFile.atlas_lod_limit(Vector2i(256, 128), Vector2i(4, 2)) == 6, "64-pixel cells stop before a mip merges their colours")
	check(ELParticleFile.atlas_lod_limit(Vector2i(96, 64), Vector2i(3, 2)) == 5, "a three-column sheet keeps aligned 32-pixel cells")
	check(ELParticleFile.atlas_lod_limit(Vector2i(30, 30), Vector2i(2, 2)) == 0, "odd cell boundaries do not borrow an already mixed mip")
	check(ELParticleFile.atlas_lod_limit(Vector2i(32, 16), Vector2i.ONE) == 5, "single-cell sheets keep their complete mip chain")
	check(ELParticleFile.atlas_lod_limit(Vector2i(32, 16), Vector2i.ZERO) == 0, "an invalid grid has a safe limit")
	var material := ShaderMaterial.new()
	material.shader = ELCombatEffects._shader(false)
	var image := _image()
	var bytes := image.get_data()
	var atlas := ImageTexture.create_from_image(image)
	ELParticleFile.set_atlas(material, atlas, Vector2(2, 2))
	check(material.get_shader_parameter("atlas_max_lod") == 5.0, "the material receives the last cell-safe source mip")
	check(atlas.get_image().get_data() == bytes and image.get_data() == bytes, "original atlas and mip pixels stay byte-for-byte unchanged")
	var plain := ImageTexture.create_from_image(_image(64, false))
	ELParticleFile.set_atlas(material, plain, Vector2(2, 2))
	check(material.get_shader_parameter("atlas_max_lod") == 0.0, "a sheet without mips never requests missing levels")

func _particle(size := 2.0, point := Vector3.ZERO) -> ELParticleFile:
	var file := ELParticleFile.new()
	file.texture = "atlas_test.bmp"
	file.columns = 2
	file.rows = 2
	file.frames = 1
	file.starts = PackedInt32Array([0, 1])
	file.max_count = 1
	file.positions = PackedFloat32Array([point.x, -point.z, point.y])
	file.sizes = PackedFloat32Array([size])
	file.cells = PackedByteArray([0, 0])
	file.rgb = PackedByteArray([255, 255, 255])
	file.alpha = PackedByteArray([255])
	return file

func _bounds() -> void:
	var file := _particle(-12.0, Vector3(70, 3, 0))
	var box := file.sprite_bounds()
	var half := 12.0 * ELParticleFile.ORTHO_EXTENT
	check(box.has_point(Vector3(70 + half, 3 + half, 0)) and box.has_point(Vector3(70 - half, 3 - half, 0)), "large negative-sized sprites retain both billboard corners outside the old fixed box")
	check(box == ELAdventureEffects._reach(file), "map renderer and manual culling use the same complete bounds")
	check(_particle(0.2).sprite_bounds().size.length() < 1.0, "small effects no longer retain arena-sized bounds")
	check(ELParticleFile.new().sprite_bounds().position.is_finite(), "an empty particle file has finite bounds")
	var map := ELAdventureEffects.new()
	var node := MultiMeshInstance3D.new()
	map.add_child(node)
	var center := box.get_center()
	var effect := {"node": node, "cull": Vector4(center.x, center.y, center.z, box.size.length() * 0.5), "frame": 9}
	var frustum: Array[Plane] = [Plane(Vector3.RIGHT, 65.0)]
	map._cull(effect, frustum)
	check(node.visible, "a halo intersecting the view stays visible even when its centre is outside")
	node.position.x = 40.0
	map._cull(effect, frustum)
	check(not node.visible, "an effect wholly beyond the view is culled")
	node.position.x = -20.0
	map._cull(effect, frustum)
	check(node.visible and effect.frame == -1, "an effect returning to view redraws its current frame")
	map.free()

func _cache_and_fades() -> void:
	var profile := ELProfile.new()
	profile.id = "graphics_effects_fixture"
	profile._textures["effects/atlas_test"] = ImageTexture.create_from_image(_image())
	var a := _particle()
	var b := _particle()
	b.columns = 4
	var first := ELCombatEffects._material(profile, a, false)
	var second := ELCombatEffects._material(profile, b, false)
	check(first != second and first.get_shader_parameter("grid") == Vector2(2, 2) and second.get_shader_parameter("grid") == Vector2(4, 2), "effects sharing a texture but using different grids keep distinct materials")
	check(first == ELCombatEffects._material(profile, a, false), "matching particle materials are still reused")
	var effects := ELCombatEffects.new()
	var emitter := effects._free_emitter(false)
	emitter.node.material_override = first
	var keys := PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0.5])
	effects._track_emitter(emitter, keys)
	check(emitter.own != null and emitter.own.get_shader_parameter("atlas_max_lod") == first.get_shader_parameter("atlas_max_lod"), "fading spells retain the atlas limit when using private materials")
	check(is_equal_approx(emitter.opacity, 0.5), "the authored opacity track stays unchanged")
	effects.free()
	ELCombatEffects._forget_edition(profile.id)

func _sprite(stage: Node3D, file: ELParticleFile, material: ShaderMaterial, combat: bool) -> MultiMeshInstance3D:
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.mesh = quad
	mesh.instance_count = 1
	mesh.buffer = ELCombatEffects._frame_buffer(file, 0).slice(0, 16) if combat else file.instances(0)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.material_override = material
	node.custom_aabb = file.sprite_bounds()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)
	return node

func _measure(image: Image) -> Vector3:
	var red := 0.0
	var green := 0.0
	var pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r + c.g > 0.01:
				red += c.r
				green += c.g
				pixels += 1
	return Vector3(red, green, pixels)

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "render checks require an actual graphics renderer")
		return
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if not folder.is_empty(): DirAccess.make_dir_recursive_absolute(folder)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0, 0, 6)
	stage.add_child(camera)
	camera.current = true
	var atlas := ImageTexture.create_from_image(_image(256))
	for combat: bool in [false, true]:
		for tiny: bool in [false, true]:
			var samples: Array[Vector3] = []
			var kind := ("combat" if combat else "map") + ("_minified" if tiny else "_large")
			for safe: bool in [false, true]:
				var material := ShaderMaterial.new()
				if safe:
					material.shader = ELCombatEffects._shader(false) if combat else ELAdventureEffects._shader(false)
				else:
					var source: String = ELCombatEffects.SHADER if combat else ELAdventureEffects.SHADER
					source = source.replace("BLEND", "blend_mix").replace("SPRITE_ADD", "").replace("sprite_atlas(atlas, UV, atlas_slot, grid)", "texture(atlas, UV)")
					material.shader = ELParticleFile.make_sprite_shader(source)
				ELParticleFile.set_atlas(material, atlas, Vector2(2, 2))
				# The translated large quad exposes magnified bilinear edge
				# bleed. Centre a subpixel quad on an actual pixel to exercise
				# minification past the level that merges the atlas cells.
				var offset := 0.0078125 if tiny else 0.009
				var file := _particle(0.0056 if tiny else 2.43, Vector3(offset, offset, 0))
				var node := _sprite(stage, file, material, combat)
				for frame in 5: await process_frame
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				var measured := _measure(image)
				samples.append(measured)
				if not folder.is_empty(): image.save_png(folder.path_join("effects_%s_%s_%s.png" % [RenderingServer.get_current_rendering_method(), kind, "safe" if safe else "original"]))
				node.free()
			print("INFO: %s red/green/pixels %s -> %s" % [kind, samples[0], samples[1]])
			check(samples[1].y > 0.1 and samples[1].z > 0, kind + ": the intended particle remains visible")
			check(samples[1].x < 0.02, kind + ": cell-safe samples contain no neighbouring red frame")
			check(samples[0].x > samples[1].x + 0.02, kind + ": the same source without cell bounds demonstrates colour bleed")
	# A deliberately far-reaching authored particle proves these bounds are
	# consumed by the real renderer, not only by a GDScript arithmetic check.
	camera.position.x = 70.0
	var bounds_material := ShaderMaterial.new()
	bounds_material.shader = ELAdventureEffects._shader(false)
	ELParticleFile.set_atlas(bounds_material, atlas, Vector2(2, 2))
	var far_file := _particle(1.5, Vector3(70, 0, 0))
	var far_node := _sprite(stage, far_file, bounds_material, false)
	far_node.custom_aabb = AABB(Vector3(-64, -16, -64), Vector3(128, 96, 128))
	var clipped := await _capture(viewport, folder, "bounds_original")
	far_node.custom_aabb = far_file.sprite_bounds()
	var included := await _capture(viewport, folder, "bounds_complete")
	check(_measure(clipped).z == 0 and _measure(included).y > 100, "the GPU retains visible far-reaching particles that the old fixed bounds clipped")
	far_node.free()

	# Draw the actual shadow-only shader onto a plain receiver. This catches
	# shader/API errors that cannot be detected by headless source checks.
	camera.position.x = 0.0
	camera.cull_mask = 1
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.2
	var receiver := MeshInstance3D.new()
	var surface := QuadMesh.new()
	surface.size = Vector2(4, 4)
	receiver.mesh = surface
	receiver.position.z = -1.0
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.7, 0.7, 0.7)
	ground.roughness = 1.0
	receiver.material_override = ground
	stage.add_child(receiver)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 0.7
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 12.0
	sun.shadow_bias = 0.01
	sun.shadow_normal_bias = 0.0
	stage.add_child(sun)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = ELCombatEffects._shader(false)
	ELParticleFile.set_atlas(shadow_material, atlas, Vector2(2, 2))
	var shadow_node := _sprite(stage, _particle(1.5), shadow_material, true)
	shadow_node.layers = 2
	var twin := ELParticleFile.shadow_twin(shadow_node, true)
	var previous := ELParticleFile.shadows
	ELParticleFile.set_shadows(true)
	ELParticleFile.shade_twin(twin, atlas, Vector2(2, 2), 1.0, ELParticleFile.ORTHO_EXTENT)
	twin.visible = false
	var unshadowed := await _capture(viewport, folder, "shadow_off")
	twin.visible = true
	var shadowed := await _capture(viewport, folder, "shadow_on")
	var before := unshadowed.get_pixel(128, 128).r
	var after := shadowed.get_pixel(128, 128).r
	print("INFO: atlas-safe shadow receiver centre %.4f -> %.4f" % [before, after])
	# Compatibility and Forward+ combine ambient light differently; both
	# must darken this receiver visibly when the actual twin is enabled.
	check(before > 0.05 and after < before - 0.04, "the atlas-safe shadow twin compiles and casts onto a real receiver")
	ELParticleFile.set_shadows(previous)
	viewport.free()

func _capture(viewport: SubViewport, folder: String, name: String) -> Image:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if not folder.is_empty(): image.save_png(folder.path_join("effects_%s_%s.png" % [RenderingServer.get_current_rendering_method(), name]))
	return image
