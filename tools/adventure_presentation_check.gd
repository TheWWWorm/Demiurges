extends SceneTree
## Asset-free strategic-map presentation checks. Uses generated atlas/ground
## pixels and production selection, fog-shadow and reflection code.
##   godot --headless --path game --script ../tools/adventure_presentation_check.gd
## For real shader compilation and screenshots, run without --headless with:
##   ... -- --render --shots=/absolute/output/folder

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_selection()
	_map_materials()
	_fog_and_pickups()
	if OS.get_cmdline_user_args().has("--render"):
		if DisplayServer.get_name() == "headless": check(false, "render probes require a real renderer")
		else:
			await _selection_render()
			await _fog_render()
			await _reflection_render()
	print("Adventure presentation: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _solid(colour: Color, side := 8) -> ImageTexture:
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

func _rings(atlas: Texture2D) -> ELSelectionRing:
	var rings := ELSelectionRing.new()
	var prepared := ELSelectionRing._edge_texture(atlas)
	rings.textures.assign([prepared, prepared])
	rings._hover = rings._quad()
	rings._selected = rings._quad()
	return rings

func _selection() -> void:
	var poisoned := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	poisoned.fill(Color(1, 0, 1, 0))
	poisoned.set_pixel(10, 10, Color(0.8, 0.6, 0.2, 1.0))
	poisoned.set_pixel(11, 10, Color(0.8, 0.6, 0.2, 0.5))
	var source := ImageTexture.create_from_image(poisoned)
	var prepared := ELSelectionRing._edge_texture(source)
	var repaired := prepared.get_image()
	var intact := true
	for y in 64:
		for x in 64:
			var old := poisoned.get_pixel(x, y)
			var fresh := repaired.get_pixel(x, y)
			intact = intact and is_equal_approx(old.a, fresh.a) and (old.a == 0.0 or old.is_equal_approx(fresh))
	check(intact and source.get_image().get_data() == poisoned.get_data(), "selection edge repair preserves all alpha, visible RGB and the original atlas")
	check(prepared == ELSelectionRing._edge_texture(source) and repaired.get_pixel(10, 9).g > repaired.get_pixel(10, 9).b, "invisible fringe RGB is repaired once and its texture is reused")
	var boundary := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	boundary.fill(Color(0, 1, 0, 0))
	boundary.set_pixel(63, 32, Color.BLUE)
	boundary.set_pixel(65, 32, Color.RED)
	# Also poison the row boundary between the two race-colour halves.
	boundary.set_pixel(32, 255, Color.BLUE)
	boundary.set_pixel(32, 257, Color.RED)
	var boundary_source := ImageTexture.create_from_image(boundary)
	var fixed_boundary := ELSelectionRing._edge_texture(boundary_source).get_image()
	var red_edge := fixed_boundary.get_pixel(64, 32)
	var race_edge := fixed_boundary.get_pixel(32, 256)
	check(red_edge.r > 0.99 and red_edge.b < 0.01 and is_zero_approx(red_edge.a) and fixed_boundary.get_pixel(62, 32).b > 0.99,
		"RGB repair cannot copy the adjacent blue frame into a red frame's transparent edge")
	check(race_edge.r > 0.99 and race_edge.b < 0.01 and is_zero_approx(race_edge.a), "RGB repair also stays inside the selected race-colour half")
	check(boundary_source.get_image().get_data() == boundary.get_data() and fixed_boundary.get_pixel(63, 32) == Color.BLUE and fixed_boundary.get_pixel(65, 32) == Color.RED,
		"frame-isolated repair leaves the boundary source and opaque artwork unchanged")
	var irregular := _solid(Color.WHITE, 17)
	check(ELSelectionRing._edge_texture(irregular) == irregular, "an irregular atlas is retained without speculative frame repair")
	var rings := _rings(_solid(Color.WHITE, 64))
	root.add_child(rings)
	rings.colour = 2 # Top half of Selection01, the blue-race atlas slot.
	rings._clock = 31.5 * rings.TICK
	rings._place(rings._selected, true, Vector3(3, 0, -2), Vector2i.ZERO, 1.0, 1.0, 31)
	var material := rings._selected.material_override as ShaderMaterial
	check(material.get_shader_parameter("frame_from") == Vector2(0.875, 0.375) and material.get_shader_parameter("frame_to") == Vector2.ZERO,
		"last selection frame wraps within its own race-colour half")
	check(is_equal_approx(material.get_shader_parameter("frame_mix"), 0.5), "selection supplies a fractional blend between authored map ticks")
	check(rings._selected.position.is_equal_approx(Vector3(3, 0.03, -2)) and is_equal_approx(rings._selected.scale.x, rings.SPREAD), "ring placement and original footprint remain unchanged")
	check(rings._selected.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and rings._selected.gi_mode == GeometryInstance3D.GI_MODE_DISABLED and rings._selected.get_meta("raster_only"), "map rings cast no shadows, GI or traced geometry")
	check(is_equal_approx(rings.pulse_phase(rings.TICK * 0.5), 1.0 / 32.0) and is_equal_approx(rings.pulse_phase(rings.TICK * 16.0), 1.0), "danger pulse interpolates within ticks without changing its period or peak")
	rings.show_rings(0.01, 7, Vector3.ZERO, Vector2i.ONE, 7, Vector3.ZERO, Vector2i.ZERO)
	check(not rings._hover.visible and rings._selected.visible, "hover and selection never double-draw the same object")
	rings.hide_rings()
	check(not rings._selected.visible and not rings._hover.visible, "a modal or hidden map can hide both rings immediately")
	rings.free()

func _map_fixture(wet := false) -> ELAdventureMap:
	var map := ELAdventureMap.new()
	map.id = "generated-presentation-map"
	map.width = 4
	map.height = 4
	map.profile = ELProfile.new()
	map.profile.id = "el2"
	map.profile.terrain_tiles = ELTileSet.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_terrain.gdshader")
	var atlas := _solid(Color(0.42, 0.43, 0.34), 40)
	material.set_shader_parameter("tiles", atlas)
	material.set_shader_parameter("columns", 1)
	# The production atlas computes these dimensions as integers.
	material.set_shader_parameter("tile_side", 32)
	material.set_shader_parameter("pitch", 40)
	material.set_shader_parameter("tile_margin", 4)
	material.set_shader_parameter("atlas_size", Vector2(40, 40))
	var cells := PackedInt32Array()
	cells.resize(map.width * map.height)
	var plans: Array[Dictionary] = [{"offset": 0, "frames": 1, "water": wet, "layers": []}]
	map.profile.adventure_terrain_cache = {"map": map.id, "material": material, "atlas": atlas, "frames": 1, "combinations": 1,
		"cells": cells, "plans": plans, "water_format": Image.FORMAT_R8 if wet else Image.FORMAT_MAX}
	if wet: map.profile.adventure_terrain_cache.water_weights = _solid(Color(1, 0, 0, 1), 34)
	return map

func _map_materials() -> void:
	var map := _map_fixture()
	var template: ShaderMaterial = map.profile.adventure_terrain_cache.material
	template.set_shader_parameter("water_reflection_enabled", true)
	template.set_shader_parameter("water_reflection", _solid(Color.RED))
	template.set_shader_parameter("fog_enabled", true)
	var first := ELAdventureTerrain.new()
	var second := ELAdventureTerrain.new()
	root.add_child(first)
	root.add_child(second)
	check(first.build(map) and second.build(map), "two generated map views build from the same cached atlas")
	check(first.atlas == second.atlas and first.material != second.material and first.material != template, "cached atlas pixels are shared while each view owns its material")
	check(first.material.get_shader_parameter("tiles") == first.atlas
		and first.material.get_shader_parameter("columns") == 1
		and first.material.get_shader_parameter("atlas_size") == Vector2(40, 40),
		"a new scene keeps its atlas texture and layout")
	for uniform in ["tile_side", "pitch", "tile_margin"]:
		var value: Variant = first.material.get_shader_parameter(uniform)
		check(value is float and value == float(template.get_shader_parameter(uniform)),
			"%s keeps the original atlas dimension with the shader's float type" % uniform)
	check(first.material.get_shader_parameter("water_reflection") == null and not first.material.get_shader_parameter("water_reflection_enabled") and not first.material.get_shader_parameter("fog_enabled"), "a reopened map starts without stale reflection or fog bindings")
	first.material.set_shader_parameter("fog_enabled", true)
	first.set_detail(true)
	check(not second.material.get_shader_parameter("fog_enabled") and not second.material.get_shader_parameter("detail_enabled"), "fog/detail changes to one map do not alter another live view")
	var scene := ELAdventureScene.new()
	scene.map = map
	scene.terrain = first
	scene.sun = DirectionalLight3D.new()
	scene.add_child(scene.sun)
	scene.sun.rotation_degrees = ELAdventureScene.SUN_ROTATION + Vector3(0, 90, 0)
	scene.set_blob_shadows(true)
	check((first.material.get_shader_parameter("detail_sun") as Vector3).is_equal_approx(scene.sun.basis.z.normalized()), "map relief and water highlights follow the actual first-game sun rotation")
	check(not (first.material.get_shader_parameter("detail_sun") as Vector3).is_equal_approx(Vector3(0.6634, 0.6428, -0.3830)), "rotated first-game lighting no longer uses the second-game default direction")
	first.free()
	check(second.material.get_shader_parameter("water_reflection") == null and not second.material.get_shader_parameter("water_reflection_enabled"), "closing one view leaves the other map's reflection state intact")
	scene.terrain = null
	scene.free()
	second.free()

func _blob_layer(scene: ELAdventureScene) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_blob_shadow.gdshader")
	material.set_shader_parameter("mask_texture", _solid(Color.WHITE))
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = PlaneMesh.new()
	instances.instance_count = 1
	instances.set_instance_transform(0, Transform3D.IDENTITY)
	instances.set_instance_custom_data(0, Color(0.5, 0, 0, 0))
	scene.blobs = MultiMeshInstance3D.new()
	scene.blobs.multimesh = instances
	scene.blobs.material_override = material
	scene.blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(scene.blobs)
	return material

func _fog_and_pickups() -> void:
	var scene := ELAdventureScene.new()
	scene.map = _map_fixture()
	scene.terrain = ELAdventureTerrain.new()
	scene.add_child(scene.terrain)
	root.add_child(scene)
	scene.set_process(false)
	scene.terrain.build(scene.map)
	var shadow := _blob_layer(scene)
	var session := ELAdventureSession.new()
	session.map = scene.map
	session.explored.resize(16)
	session.explored.fill(2)
	var seen := session.explored.duplicate()
	session.fog = {"visible": seen, "revision": 1}
	scene.enable_fog(session)
	check(shadow.get_shader_parameter("fog_enabled") == true and shadow.get_shader_parameter("fog_from") == scene.terrain.material.get_shader_parameter("fog_from") and shadow.get_shader_parameter("fog_to") == scene.terrain.material.get_shader_parameter("fog_to"), "blob shadows share the terrain's exact fog masks")
	scene.fog_since = 0.6
	scene._sync_mist()
	check(is_equal_approx(shadow.get_shader_parameter("fog_fade"), scene.terrain.material.get_shader_parameter("fog_fade")), "blob and terrain fog use the same in-progress reveal fade")
	scene.enable_fog(null)
	check(not shadow.get_shader_parameter("fog_enabled") and not scene.terrain.material.get_shader_parameter("fog_enabled"), "turning fog off restores both ordinary terrain and blob shadows")
	var model := ELModel.new()
	scene.add_child(model)
	model.position = Vector3(2, 0, -2)
	model.scale = Vector3.ONE * 2.0
	scene.object_models[9] = model
	scene._blob_slots[9] = {"index": 0, "local": Transform3D(Basis.from_scale(Vector3(2, 1, 1)), Vector3(0.5, 0, 0)), "base": model.transform}
	check(scene.retire_pickup(9), "a visible generated pickup starts its existing retirement animation")
	scene._fade_pickups(scene.PICKUP_FADE * 0.5)
	var half: Transform3D = scene._blob_slots[9].placed
	check(is_equal_approx(half.basis.x.length(), 2.0) and is_equal_approx(half.origin.x, 2.5), "a modelled pickup's shadow shrinks and recentres with its figure")
	scene._fade_pickups(scene.PICKUP_FADE)
	check(not scene._blob_slots[9].present and scene._retiring_pickups.is_empty(), "the pickup's final frame removes its blob with the figure")
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = MultiMesh.new()
	instances.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instances.multimesh.mesh = BoxMesh.new()
	instances.multimesh.instance_count = 1
	instances.set_meta(scene.PLACEMENT_REVISION, 0)
	scene.add_child(instances)
	var base := Transform3D(Basis.from_scale(Vector3.ONE * 2), Vector3(4, 0, -2))
	scene._instances[10] = [{"node": instances, "index": 0, "transform": base}]
	scene._blob_slots[10] = {"index": 0, "local": Transform3D(Basis.from_scale(Vector3(2, 1, 1)), Vector3(0.5, 0, 0)), "base": base}
	# Directly seed retirement to avoid dummy-renderer GPU instance readback.
	scene._retiring_pickups[10] = {"elapsed": 0.0, "basis": Basis.IDENTITY}
	scene._fade_pickups(scene.PICKUP_FADE * 0.5)
	var instanced_half: Transform3D = scene._blob_slots[10].placed
	check(is_equal_approx(instanced_half.basis.x.length(), 2.0) and is_equal_approx(instanced_half.origin.x, 4.5), "an instanced pickup's independently batched shadow follows the same shrink")
	scene.free()

func _stage(title: String) -> Dictionary:
	root.size = Vector2i(960, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.16, 0.18, 0.21)
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	stage.add_child(camera)
	camera.position = Vector3(0, 8, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.76, 0.77, 0.73)
	ground.material_override = material
	stage.add_child(ground)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	var label := Label.new()
	label.text = "Generated map fixture: " + title + "\nSynthetic art only; original game assets are not loaded."
	label.position = Vector2(22, 18)
	label.add_theme_color_override("font_color", Color(0.12, 0.16, 0.20))
	label.add_theme_font_size_override("font_size", 18)
	overlay.add_child(label)
	return {"stage": stage, "camera": camera, "ground": ground, "label": label}

func _ring_atlas() -> ImageTexture:
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	# Deliberately wrong RGB under zero alpha catches fringe contamination.
	image.fill(Color(1, 0, 1, 0))
	for frame in 32:
		for y in 64:
			for x in 64:
				var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / 64.0 - Vector2.ONE * 0.5
				var radius := uv.length()
				var angle := atan2(uv.y, uv.x) - TAU * frame / 32.0
				var band := 1.0 - smoothstep(0.018, 0.036, absf(radius - 0.33))
				var teeth := (1.0 - smoothstep(0.016, 0.032, absf(radius - 0.395))) * pow(maxf(cos(angle * 7.0), 0.0), 3.0)
				var opacity := maxf(band, teeth)
				if opacity > 0.0: image.set_pixel(frame % 8 * 64 + x, frame / 8 * 64 + y, Color(1.0, 0.70, 0.18, opacity))
	# Solid green in the other race half makes incorrect wrap/edge taps obvious.
	image.fill_rect(Rect2i(0, 256, 512, 256), Color(0, 1, 0, 1))
	return ImageTexture.create_from_image(image)

func _selection_render() -> void:
	var fixture := _stage("selection interpolation and contour")
	var rings := _rings(_ring_atlas())
	fixture.stage.add_child(rings)
	rings.colour = 2
	var material := rings._selected.material_override as ShaderMaterial
	rings._clock = 31.0 * rings.TICK
	rings._place(rings._selected, true, Vector3.ZERO, Vector2i.ZERO, 1.0, 1.0, 31)
	material.set_shader_parameter("outline_strength", 0.0)
	var first := await _frame("map_selection_frame31")
	rings._clock = 31.5 * rings.TICK
	rings._place(rings._selected, true, Vector3.ZERO, Vector2i.ZERO, 1.0, 1.0, 31)
	material.set_shader_parameter("outline_strength", 0.0)
	var middle := await _frame("map_selection_interpolated")
	rings._clock = 0.0
	rings._place(rings._selected, true, Vector3.ZERO, Vector2i.ZERO, 1.0, 1.0, 0)
	material.set_shader_parameter("outline_strength", 0.0)
	var last := await _frame("map_selection_frame0")
	var whole := _difference(first, last)
	check(whole > 0.001 and _difference(first, middle) > whole * 0.15 and _difference(middle, last) > whole * 0.15,
		"rendered selection has an intermediate pose between the last and first authored frames")
	var wrong_colour := 0
	for y in range(100, 600, 2):
		for x in range(120, 840, 2):
			var colour := middle.get_pixel(x, y)
			if colour.g > colour.r + 0.08 or colour.b > colour.g + 0.02: wrong_colour += 1
	check(wrong_colour == 0, "interpolation leaks neither the next race colour nor transparent magenta RGB")
	material.set_shader_parameter("outline_strength", 0.44)
	var outlined := await _frame("map_selection_contour")
	check(_difference(last, outlined) > 0.0001, "a rendered contour improves the original artwork's edge separation")
	check(_colour_delta(last.get_pixel(480, 320), outlined.get_pixel(480, 320)) < 0.005, "the contour leaves the ring's empty centre transparent")
	fixture.stage.free()
	await process_frame

func _fog_render() -> void:
	var fixture := _stage("a ground shadow fading through fog")
	var scene := ELAdventureScene.new()
	scene.set_process(false)
	fixture.stage.add_child(scene)
	var material := _blob_layer(scene)
	var radial := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / 64.0 - Vector2.ONE * 0.5
			radial.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.12, 0.49, uv.length())))
	radial.generate_mipmaps()
	material.set_shader_parameter("mask_texture", ImageTexture.create_from_image(radial))
	scene.blobs.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(1.8, 1, 1.8)), Vector3(0, 0.02, 0)))
	material.set_shader_parameter("fog_enabled", true)
	material.set_shader_parameter("fog_size", Vector2i.ONE)
	material.set_shader_parameter("fog_from", _solid(Color.WHITE, 2))
	material.set_shader_parameter("fog_to", _solid(Color.BLACK, 2))
	material.set_shader_parameter("fog_fade", 0.0)
	var hidden := await _frame("map_shadow_fog_hidden")
	material.set_shader_parameter("fog_fade", 0.5)
	var revealing := await _frame("map_shadow_fog_revealing")
	material.set_shader_parameter("fog_fade", 1.0)
	var clear := await _frame("map_shadow_fog_clear")
	var light_hidden := hidden.get_pixel(480, 320).r
	var light_revealing := revealing.get_pixel(480, 320).r
	var light_clear := clear.get_pixel(480, 320).r
	check(light_clear + 0.08 < light_revealing and light_revealing + 0.08 < light_hidden, "rendered blob fades gradually with fog instead of appearing at full darkness")
	scene.blobs.hide()
	var none := await _frame("map_shadow_disabled")
	check(_difference(hidden, none) < 0.001, "complete fog cover hides the entire blob exactly")
	fixture.stage.free()
	await process_frame

func _reflection_render() -> void:
	var fixture := _stage("bounded, antialiased water reflections")
	fixture.ground.hide()
	var map := _map_fixture(true)
	var terrain := ELAdventureTerrain.new()
	fixture.stage.add_child(terrain)
	terrain.build(map)
	var camera: Camera3D = fixture.camera
	camera.position = Vector3(4, 5, 2)
	camera.look_at(Vector3(4, 0, -4))
	camera.frustum_offset = Vector2(0.12, -0.08)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(4, 0.9, -4)
	box.scale = Vector3(1.1, 1.8, 1.1)
	box.layers = 1 | terrain.REFLECTION_LAYER
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(0.86, 0.24, 0.12)
	box.material_override = look
	fixture.stage.add_child(box)
	var previous := root.msaa_3d
	root.msaa_3d = Viewport.MSAA_4X
	terrain.set_water(true)
	await _frame("map_water_reflection")
	check(terrain._reflection != null and terrain._mirror_active, "visible generated water starts its own reflected viewport")
	if terrain._reflection != null:
		check(terrain._reflection.msaa_3d == Viewport.MSAA_2X and terrain._reflection.size.x <= 1024 and terrain._reflection.size.y <= 1024, "reflection AA is capped at 2x and resolution stays bounded")
		check(terrain._mirror_camera.frustum_offset == Vector2(-0.12, -0.08), "asymmetric camera projection mirrors its horizontal frustum offset")
		var reflected := terrain._reflection.get_texture().get_image()
		var visible_pixels := 0
		for y in range(0, reflected.get_height(), 2):
			for x in range(0, reflected.get_width(), 2):
				var colour := reflected.get_pixel(x, y)
				if colour.a > 0.3 and colour.r > colour.g + 0.1: visible_pixels += 1
		check(visible_pixels > 30, "the actual reflected framebuffer contains the generated figure")
		var reflected_viewport := terrain._reflection
		fixture.stage.remove_child(terrain)
		check(not terrain._mirror_active and terrain.material.get_shader_parameter("water_reflection") == null, "removing a map releases its live reflection sampler")
		fixture.stage.add_child(terrain)
		terrain._update_water_reflection()
		check(terrain._mirror_active and terrain._reflection == reflected_viewport and terrain.material.get_shader_parameter("water_reflection") == reflected_viewport.get_texture(), "a re-entered map rebinds its existing reflection viewport")
		check(terrain._reflection.world_3d == camera.get_world_3d(), "resumed reflection uses the source camera's current world")
		var isolated := SubViewport.new()
		isolated.size = Vector2i(320, 240)
		isolated.own_world_3d = true
		fixture.stage.add_child(isolated)
		var other_camera := Camera3D.new()
		isolated.add_child(other_camera)
		other_camera.transform = camera.transform
		other_camera.current = true
		terrain.reparent(isolated)
		terrain._update_water_reflection()
		check(terrain._mirror_active and terrain._reflection.world_3d == other_camera.get_world_3d() and terrain._reflection.world_3d != camera.get_world_3d(), "moving a map to another World3D updates its reused reflection scene")
		terrain.reparent(fixture.stage)
		terrain._update_water_reflection()
		isolated.free()
		root.msaa_3d = Viewport.MSAA_DISABLED
		terrain._update_water_reflection()
		check(terrain._reflection.msaa_3d == Viewport.MSAA_DISABLED, "AA off also disables reflection multisampling")
		terrain.hide()
		check(not terrain._mirror_active and terrain._reflection.render_target_update_mode == SubViewport.UPDATE_DISABLED and not terrain.material.get_shader_parameter("water_reflection_enabled"), "a hidden map stops its reflection viewport and clears sampling")
		terrain.show()
		terrain.set_water(true)
		terrain.set_water(false)
		check(not terrain._mirror_active and not terrain.is_processing(), "water off stops reflected rendering and update work")
	root.msaa_3d = previous
	fixture.stage.free()
	await process_frame

func _frame(label: String) -> Image:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var directory := arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(directory)
			image.save_png(directory.path_join("%s_%s.png" % [RenderingServer.get_current_rendering_method(), label]))
	return image

func _difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(100, 600, 2):
		for x in range(120, 840, 2):
			total += _colour_delta(a.get_pixel(x, y), b.get_pixel(x, y))
			count += 1
	return total / maxf(1, count)

func _colour_delta(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
