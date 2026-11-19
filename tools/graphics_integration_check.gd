extends SceneTree
## Asset-free integration checks for graphics preferences on active/cached
## autochess boards and cutout mipmaps entering the path-tracing atlas.
## Uses production arena/material/texture code with generated fixtures.
## No game files or ray-tracing device are needed; this does not execute PT.
## No player preferences or game saves are read or written.
##
##   godot --headless --path game --script ../tools/graphics_integration_check.gd
##
## To render the production adventure-map shader with generated tile/mask
## atlases, use a windowed renderer and append -- --render --shots=DIR.
## The optional two pictures are synthetic fixtures, not original maps.

## Exercise the real duel settings handler without loading its asset-driven
## scene or interface. Only its setup/layout/audio/UI refresh hooks are inert.
class DuelSettingsFixture:
	extends "res://src/duel/view.gd"
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
	func _layout_hud() -> void:
		pass
	func _preview_volumes(_values: Dictionary) -> void:
		pass
	func _refresh() -> void:
		pass

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_ground_lookup()
	await _autochess_preferences()
	_trace_shadow_ownership()
	_mask_layers()
	if OS.get_cmdline_user_args().has("--render"):
		if DisplayServer.get_name() == "headless":
			check(false, "map-water render probes require a real renderer, without --headless")
		else:
			await _map_water_render()
	print("GRAPHICS INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _ground_lookup() -> void:
	var arena := ELArena.new()
	# A cached/constructed arena can contain lights before its ground.
	arena.add_child(DirectionalLight3D.new())
	var ground := ELModel.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-20, 1, -20), Vector3(20, 3, -20), Vector3(0, 2, 20)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	ground.figures = {"surface": {"arrays": arrays}}
	arena.add_child(ground)
	arena._ground = ground
	check(is_equal_approx(arena.ground_height(4, 0), 2.2), "ground sampling follows the actual inclined surface regardless of child order")
	check(is_zero_approx(arena.ground_height(100, 100)), "a point outside the surface retains the ordinary zero-height fallback")
	arena._ground = null
	check(is_zero_approx(arena.ground_height(4, 0)), "an arena without a loaded surface has a finite height fallback")
	arena.free()

func _autochess_preferences() -> void:
	var first := _arena_fixture("FixtureA")
	var cached := _arena_fixture("FixtureB")
	var board := ELAutochessBoardView.new()
	board.set_process(false)
	board.profile = first.profile
	board.arena = first.arena
	board.arena_id = "FixtureA"
	board.effects = first.effects
	board._arenas = {"FixtureA": {"arena": first.arena, "effects": first.effects},
		"FixtureB": {"arena": cached.arena, "effects": cached.effects}}
	board.add_child(first.arena)
	board.add_child(first.effects)
	# An empty fire holder avoids loading any authored particles when the
	# already-cached board is restored below.
	board.fire = Node3D.new()
	board.add_child(board.fire)
	root.add_child(board)
	board.apply_settings({})
	for fixture: Dictionary in [first, cached]:
		var arena: ELArena = fixture.arena
		check(fixture.ground.material_override == fixture.original, "%s: omitted terrain detail defaults to the original material" % arena.scene_id)
		check(not arena._sea.visible and fixture.ground.mesh == arena._ship_original_mesh, "%s: omitted enhanced water defaults off" % arena.scene_id)
		check(arena.light.shadow_enabled and is_equal_approx(arena.light.shadow_blur, 1.0), "%s: default shadows are ordinary raster shadows" % arena.scene_id)
	check(not (cached.arena as ELArena).is_inside_tree(), "the cached arena really is detached during preference updates")
	var enhanced := {"terrain_detail": true, "enhanced_water": true, "shadows": true,
		"soft_shadows": true, "bloom": true, "soft_particles": false, "spell_light": true,
		"music": 0.4, "effects": 0.7, "ambience": 0.3}
	board.apply_settings(enhanced)
	for fixture: Dictionary in [first, cached]:
		var arena: ELArena = fixture.arena
		check(fixture.ground.material_override != fixture.original and fixture.ground.material_override == arena._detail_materials.get(fixture.ground), "%s: terrain detail reaches the actual ground material" % arena.scene_id)
		check(arena._sea.visible and fixture.ground.mesh == arena._ship_deck_mesh, "%s: enhanced water replaces the sea portion of the surface" % arena.scene_id)
		check(is_equal_approx(arena.light.shadow_blur, 2.0) and arena.environment_settings.glow_enabled, "%s: soft shadows and bloom reach the scene" % arena.scene_id)
	var first_arena: ELArena = first.arena
	first_arena.light.set_meta("traced_shadow", true)
	first_arena.light.shadow_enabled = false
	first_arena.environment_settings.set_meta(ELEffectLook.TRACED, true)
	var plain := enhanced.duplicate()
	for key: String in ["terrain_detail", "enhanced_water", "shadows", "soft_shadows", "bloom"]: plain[key] = false
	board.apply_settings(plain)
	check(not first_arena.light.shadow_enabled and first_arena.light.get_meta("traced_shadow") == false, "turning shadows off while tracing changes the saved preference without enabling raster shadows")
	check(first_arena.environment_settings.glow_enabled, "the traced scene retains its required bloom despite the ordinary bloom preference")
	check(not (cached.arena as ELArena).environment_settings.glow_enabled, "the detached raster scene follows the ordinary bloom preference")
	for fixture: Dictionary in [first, cached]:
		check(fixture.ground.material_override == fixture.original and not fixture.arena._sea.visible, "%s: disabling detail and water restores the exact source presentation" % fixture.arena.scene_id)
	var traced_on := plain.duplicate()
	traced_on.shadows = true
	board.apply_settings(traced_on)
	check(not first_arena.light.shadow_enabled and first_arena.light.get_meta("traced_shadow") == true, "turning shadows on while tracing records the future raster preference only")
	first_arena.light.remove_meta("traced_shadow")
	first_arena.environment_settings.remove_meta(ELEffectLook.TRACED)
	board.apply_settings(traced_on)
	check(first_arena.light.shadow_enabled and not first_arena.environment_settings.glow_enabled, "the scene returns to ordinary shadows and bloom preference after trace ownership ends")
	var sentinel := ELModel.new()
	sentinel.set_process(false)
	board.add_child(sentinel)
	board.models[12345] = sentinel
	var existing_detail: Material = first_arena._detail_materials.get(first.ground)
	check(board.build(first.profile, "FixtureA", enhanced), "building the same current scene takes the successful fast path")
	check(board.arena == first_arena and board.models.get(12345) == sentinel, "the same-scene path preserves the active arena and deployed models")
	check(first.ground.material_override == existing_detail and first_arena._sea.visible and is_equal_approx(first_arena.light.shadow_blur, 2.0), "the same-scene fast path still reapplies visual preferences")
	var screen := ELAutochessScreen.new()
	screen.board = board
	screen.apply_settings(plain)
	check(board.settings == plain and first.ground.material_override == first.original and cached.ground.material_override == cached.original, "screen-level settings propagate through the board to current and cached materials")
	screen.free()
	board.settings = enhanced
	check(board._build_arena("FixtureB") and board.arena == cached.arena, "a different cached arena can be restored without loading game assets")
	check((cached.arena as ELArena).is_inside_tree() and not first_arena.is_inside_tree(), "cache restoration swaps the actual scene-tree membership")
	check(cached.ground.material_override != cached.original and cached.arena._sea.visible, "restoring a cached arena applies the latest detail and water preferences")
	check(is_instance_valid(board.audio) and is_equal_approx(float(board.audio.settings.music), 0.4), "the restored board's audio uses the same current preferences")
	check((first.profile as ELProfile).asset_reads == 0 and (cached.profile as ELProfile).asset_reads == 0, "all arena integration checks use generated fixtures and read no game archive")
	board.free()
	await process_frame
	ELEffectLook.use({})

func _trace_shadow_ownership() -> void:
	for edition: String in ["el1", "el2"]:
		var scene := ELAdventureScene.new()
		scene.set_process(false)
		scene.map = ELAdventureMap.new()
		scene.map.id = "synthetic-shadow-check"
		scene.map.profile = ELProfile.new()
		scene.map.profile.id = edition
		scene.environment = Environment.new()
		scene.sun = DirectionalLight3D.new()
		scene.blobs = MultiMeshInstance3D.new()
		scene.add_child(scene.sun)
		scene.add_child(scene.blobs)
		var ground := ShaderMaterial.new()
		ground.shader = load("res://src/render/adventure_terrain.gdshader")
		scene.map.profile.adventure_terrain_cache = {"map": scene.map.id, "material": ground}
		root.add_child(scene)
		scene.set_blob_shadows(true)
		check(scene.sun.shadow_enabled and scene.blobs.visible, "%s map setter enables ordinary shadows before tracing" % edition)
		scene.sun.set_meta("traced_shadow", true)
		scene.sun.shadow_enabled = false
		scene.set_blob_shadows(true)
		check(not scene.sun.shadow_enabled and scene.sun.get_meta("traced_shadow") == true, "%s map setter preserves tracing's ownership when options are reapplied" % edition)
		scene.set_blob_shadows(false)
		check(not scene.sun.shadow_enabled and scene.sun.get_meta("traced_shadow") == false and not scene.blobs.visible and is_zero_approx(ground.get_shader_parameter("shadow_strength")), "%s map setter remembers disabled shadows and updates terrain/blob presentation during tracing" % edition)
		scene.set_blob_shadows(true)
		check(not scene.sun.shadow_enabled and scene.sun.get_meta("traced_shadow") == true and is_equal_approx(ground.get_shader_parameter("shadow_strength"), ELAdventureScene.SILHOUETTE_STRENGTH), "%s map setter records re-enabled shadows without starting a raster shadow pass" % edition)
		scene.sun.remove_meta("traced_shadow")
		scene.set_blob_shadows(true)
		check(scene.sun.shadow_enabled, "%s map setter restores raster shadows after tracing releases the light" % edition)
		scene.free()
	var previous_msaa := root.msaa_3d
	var fixture := _arena_fixture("DuelSettingsFixture")
	var arena: ELArena = fixture.arena
	var view := DuelSettingsFixture.new()
	view.arena = arena
	view.effects = fixture.effects
	view.add_child(arena)
	view.add_child(fixture.effects)
	root.add_child(view)
	view.settings.values.shadows = true
	view._apply_settings()
	check(arena.light.shadow_enabled, "the actual duel settings handler enables ordinary shadows before tracing")
	arena.light.set_meta("traced_shadow", true)
	arena.light.shadow_enabled = false
	arena.environment_settings.set_meta(ELEffectLook.TRACED, true)
	view._apply_settings()
	check(not arena.light.shadow_enabled and arena.light.get_meta("traced_shadow") == true, "the actual duel settings handler preserves tracing's light ownership")
	view.settings.values.shadows = false
	view._apply_settings()
	check(not arena.light.shadow_enabled and arena.light.get_meta("traced_shadow") == false, "duel settings remember disabled shadows while tracing remains in control")
	view.settings.values.contact_shading = true
	view._apply_settings()
	check(not arena.light.shadow_enabled and arena.light.get_meta("traced_shadow") == false, "reapplying duel settings for contact shading cannot enable raster shadows during tracing")
	view.settings.values.shadows = true
	view._apply_settings()
	check(not arena.light.shadow_enabled and arena.light.get_meta("traced_shadow") == true, "duel settings record re-enabled shadows for tracing's later handback")
	arena.light.remove_meta("traced_shadow")
	arena.environment_settings.remove_meta(ELEffectLook.TRACED)
	view._apply_settings()
	check(arena.light.shadow_enabled, "duel settings restore ordinary shadow ownership after tracing ends")
	view.free()
	root.msaa_3d = previous_msaa
	ELEffectLook.use({})

func _arena_fixture(id: String) -> Dictionary:
	var profile := ELProfile.new()
	profile.id = "el2"
	var albedo_image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	albedo_image.fill(Color(0.35, 0.30, 0.20))
	var albedo := ImageTexture.create_from_image(albedo_image)
	var grain_image := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	grain_image.fill(Color(0.5, 0.5, 0.5))
	profile._textures[ELArchive.key("CombatScenes/integration-grain")] = ImageTexture.create_from_image(grain_image)
	var arena := ELArena.new()
	arena.set_process(false)
	arena.scene_id = id
	arena._profile = profile
	arena.definition = {"DetailTextureName": "integration-grain", "DetailTextureTileSize": 2.0}
	arena.environment_settings = Environment.new()
	arena.environment_settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	arena.environment_settings.ambient_light_color = Color.WHITE
	arena.environment_settings.ambient_light_energy = 0.3
	arena.light = DirectionalLight3D.new()
	arena.add_child(arena.light)
	var model := ELModel.new()
	model.set_process(false)
	arena._ground = model
	arena.add_child(model)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	var original := ShaderMaterial.new()
	original.shader = ELArena.LIT_SHADER
	original.set_shader_parameter("albedo_texture", albedo)
	original.set_shader_parameter("albedo_tint", Color.WHITE)
	original.set_shader_parameter("alpha_cutoff", 0.5)
	ground.material_override = original
	ground.set_meta("albedo", albedo)
	model.add_child(ground)
	model.parts.surface = ground
	model.figures.surface = {"arrays": plane.get_mesh_arrays()}
	arena._lit_materials.append(original)
	arena._ship_surface = ground
	arena._ship_original_mesh = plane
	arena._ship_deck_mesh = ArrayMesh.new()
	arena._ship_deck_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane.get_mesh_arrays())
	var sea := MeshInstance3D.new()
	sea.mesh = PlaneMesh.new()
	sea.material_override = ShaderMaterial.new()
	sea.material_override.shader = ELArena.SEA_SHADER
	sea.material_override.set_shader_parameter("ship_atlas", albedo)
	sea.visible = false
	arena._sea = sea
	arena.add_child(sea)
	var effects := ELCombatEffects.new()
	effects.set_process(false)
	return {"arena": arena, "profile": profile, "ground": ground, "original": original, "effects": effects}

func _mask_layers() -> void:
	var base := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
	base.fill(Color(0.1, 0.2, 0.05, 0.0))
	for y in 512:
		for x in 512:
			if (x % 8 == 0 and y % 3 < 2) or absi(x - y) % 31 == 0:
				base.set_pixel(x, y, Color(0.25, 0.65, 0.12, 1.0))
	var original_bytes := base.get_data()
	var prepared := ELTexture.cutout_mipmaps(base)
	var source_bytes := prepared.get_data()
	var texture := ImageTexture.create_from_image(prepared)
	texture.set_meta(ELTexture.COVERAGE_MASK_MIPS, prepared.get_mipmap_count() + 1)
	var layer := ELPathTracing._authored_layer(texture, prepared)
	check(layer != null and layer.get_size() == Vector2i(256, 256) and layer.get_mipmap_count() == 8, "a generated cutout chain supplies a complete 256px ray-atlas layer")
	var expected := source_bytes.slice(prepared.get_mipmap_offset(1))
	check(layer != null and layer.get_data() == expected, "the ray layer preserves every byte of the prepared 256px mip and its tail")
	var ordinary := base.duplicate() as Image
	ordinary.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	check(layer != null and _covered(layer) > _covered(ordinary), "the fixture exercises thin silhouettes that ordinary 256px resizing would erase")
	check(base.get_data() == original_bytes and prepared.get_data() == source_bytes, "ray-atlas preparation never mutates either original or prepared image")
	var tracing := ELPathTracing.new()
	var uploaded := tracing._layer_image(texture, false)
	check(uploaded != null and uploaded.get_data() == expected, "the actual atlas upload path consumes the preserved chain")
	check(texture.get_image().get_data() == source_bytes, "the source texture stays intact after atlas preparation")
	texture.set_meta(ELTexture.AUTHORED_MASK_MIPS, 1)
	check(ELPathTracing._authored_layer(texture, prepared) == null, "authored mip coverage takes priority over generated metadata when it stops before 256px")
	texture.set_meta(ELTexture.AUTHORED_MASK_MIPS, 2)
	var authored := ELPathTracing._authored_layer(texture, prepared)
	check(authored != null and authored.get_data() == expected, "an authored 256px level retains its exact bytes and generated tail")
	texture.remove_meta(ELTexture.AUTHORED_MASK_MIPS)
	texture.set_meta(ELTexture.COVERAGE_MASK_MIPS, 999)
	check(ELPathTracing._authored_layer(texture, prepared) != null, "oversized mip metadata is limited to the levels actually present")
	texture.remove_meta(ELTexture.COVERAGE_MASK_MIPS)
	check(ELPathTracing._authored_layer(texture, prepared) == null, "ordinary textures without prepared-mask metadata keep their existing fallback")
	var incomplete := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	incomplete.fill(Color.WHITE)
	var incomplete_texture := ImageTexture.create_from_image(incomplete)
	incomplete_texture.set_meta(ELTexture.COVERAGE_MASK_MIPS, 99)
	check(ELPathTracing._authored_layer(incomplete_texture, incomplete) == null, "mask metadata without a real mip chain safely declines the prepared-layer path")
	var rectangular := Image.create_empty(256, 128, true, Image.FORMAT_RGBA8)
	rectangular.fill(Color.WHITE)
	var rectangular_texture := ImageTexture.create_from_image(rectangular)
	rectangular_texture.set_meta(ELTexture.COVERAGE_MASK_MIPS, rectangular.get_mipmap_count() + 1)
	check(ELPathTracing._authored_layer(rectangular_texture, rectangular) == null, "non-square masks keep the ordinary resize path")
	var rgb := Image.create_empty(256, 256, true, Image.FORMAT_RGB8)
	rgb.fill(Color.WHITE)
	var rgb_texture := ImageTexture.create_from_image(rgb)
	rgb_texture.set_meta(ELTexture.COVERAGE_MASK_MIPS, rgb.get_mipmap_count() + 1)
	check(ELPathTracing._authored_layer(rgb_texture, rgb) == null, "an incompatible pixel format is not reinterpreted as RGBA mask bytes")
	_grey_variants(prepared)
	tracing.free()

func _grey_variants(prepared: Image) -> void:
	var source_bytes := prepared.get_data()
	var base_grey := ELColorless.grey_image(prepared)
	check(not base_grey.has_mipmaps() and base_grey.get_data_size() == prepared.get_width() * prepared.get_height() * 4, "grey_image's default still returns only the original base level")
	var kept := ELColorless.grey_image(prepared, true)
	check(kept.get_size() == prepared.get_size() and kept.get_mipmap_count() == prepared.get_mipmap_count(), "optional greyscale conversion retains the existing mip structure")
	check(_grey_channels(prepared, kept).alpha, "optional greyscale conversion preserves every alpha byte across all mip levels")
	check(_grey_channels(prepared, kept).rgb, "optional greyscale conversion applies the original integer RGB mean at every level")
	check(prepared.get_data() == source_bytes, "both greyscale conversion modes leave their shared source image unchanged")
	var authored_bytes := source_bytes.duplicate()
	# Hand-authored lower masks deliberately differ from any chain generated
	# from level zero, so an accidental regeneration cannot pass this test.
	for level in range(1, prepared.get_mipmap_count() + 1):
		var start := prepared.get_mipmap_offset(level)
		var count := maxi(1, prepared.get_width() >> level) * maxi(1, prepared.get_height() >> level)
		for pixel in count: authored_bytes[start + pixel * 4 + 3] = 255 if (pixel + level) % 3 == 0 else 0
	var authored := Image.create_from_data(prepared.get_width(), prepared.get_height(), true, Image.FORMAT_RGBA8, authored_bytes)
	var scene := ELAdventureScene.new()
	for kind: StringName in [ELTexture.COVERAGE_MASK_MIPS, ELTexture.AUTHORED_MASK_MIPS]:
		var source := authored if kind == ELTexture.AUTHORED_MASK_MIPS else prepared
		var texture := ImageTexture.create_from_image(source)
		texture.set_meta(ELTexture.ONE_BIT_ALPHA, true)
		texture.set_meta(kind, source.get_mipmap_count() + 1)
		var grey_texture := scene._grey_texture(texture)
		var grey := grey_texture.get_image()
		var channels := _grey_channels(source, grey)
		check(channels.alpha and grey.get_mipmap_count() == source.get_mipmap_count(), "%s: a map's grey variant preserves each level's exact mask" % kind)
		check(channels.rgb, "%s: a map's grey variant has the correct grey RGB at every level" % kind)
		check(grey_texture.get_meta(ELTexture.ONE_BIT_ALPHA, false) == true and grey_texture.get_meta(kind, 0) == texture.get_meta(kind), "%s: the grey texture retains its cutout and prepared-chain metadata" % kind)
		check(scene._grey_texture(texture) == grey_texture, "%s: repeated colourless presentation reuses its cached grey texture" % kind)
		check(texture.get_image().get_data() == source.get_data() and prepared.get_data() == source_bytes, "%s: creating the cached variant does not modify the source texture or image" % kind)
		var layer := ELPathTracing._authored_layer(grey_texture, grey)
		check(layer != null and layer.get_data() == grey.get_data().slice(grey.get_mipmap_offset(1)), "%s: the grey variant's preserved 256px mip and tail reach the PT atlas unchanged" % kind)
	var ordinary := ImageTexture.create_from_image(prepared)
	ordinary.set_meta(ELTexture.ONE_BIT_ALPHA, true)
	var expected := ELColorless.grey_image(prepared)
	expected.generate_mipmaps()
	var ordinary_grey := scene._grey_texture(ordinary)
	check(ordinary_grey.get_image().get_data() == expected.get_data(), "ordinary map textures keep the previous grey-then-generate filtering path")
	check(ordinary_grey.get_meta(ELTexture.ONE_BIT_ALPHA, false) == true and not ordinary_grey.has_meta(ELTexture.COVERAGE_MASK_MIPS) and not ordinary_grey.has_meta(ELTexture.AUTHORED_MASK_MIPS), "ordinary grey textures retain cutout identity without inventing prepared mip metadata")
	scene.free()

func _grey_channels(source: Image, grey: Image) -> Dictionary:
	var original := source.get_data()
	var changed := grey.get_data()
	if original.size() != changed.size(): return {"alpha": false, "rgb": false}
	var same_alpha := true
	var correct_rgb := true
	for at in range(0, original.size(), 4):
		same_alpha = same_alpha and original[at + 3] == changed[at + 3]
		var mean := (int(original[at]) + int(original[at + 1]) + int(original[at + 2])) / 3
		correct_rgb = correct_rgb and changed[at] == mean and changed[at + 1] == mean and changed[at + 2] == mean
	return {"alpha": same_alpha, "rgb": correct_rgb}

func _covered(image: Image) -> int:
	var bytes := image.get_data()
	var covered := 0
	for at in range(3, image.get_width() * image.get_height() * 4, 4):
		if bytes[at] >= 128: covered += 1
	return covered

## Four generated tile types, repeated under complete fog: dry ground,
## open water, a smoothly blended shoreline and a bog. UV2 carries the
## production tile-index/frame-count convention; all textures are made here.
func _map_water_render() -> void:
	root.size = Vector2i(960, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.025, 0.03, 0.04)
	world.environment.ambient_light_energy = 0.0
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	stage.add_child(camera)
	camera.position = Vector3(4.0, 8.0, -2.0)
	camera.look_at(Vector3(4.0, 0.0, -2.0), Vector3.FORWARD)
	camera.current = true
	var material := ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_terrain.gdshader")
	var tile_pitch := 40
	var palette := [Color(0.40, 0.32, 0.18), Color(0.16, 0.23, 0.10), Color(0.36, 0.31, 0.19), Color(0.22, 0.34, 0.10)]
	var atlas := Image.create_empty(tile_pitch * 4, tile_pitch, false, Image.FORMAT_RGBA8)
	for y in tile_pitch:
		for x in tile_pitch * 4:
			var tile := x / tile_pitch
			var grain := 1.0 + 0.035 * sin(float(x % tile_pitch) * 0.8) * cos(float(y) * 0.6)
			var colour: Color = palette[tile] * grain
			colour.a = 1.0
			atlas.set_pixel(x, y, colour)
	atlas.generate_mipmaps()
	material.set_shader_parameter("tiles", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter("columns", 4)
	material.set_shader_parameter("tile_side", 32.0)
	material.set_shader_parameter("pitch", float(tile_pitch))
	material.set_shader_parameter("tile_margin", 4.0)
	material.set_shader_parameter("atlas_size", Vector2(atlas.get_size()))
	material.set_shader_parameter("detail_enabled", false)
	material.set_shader_parameter("shadow_strength", 0.0)
	var weights := Image.create_empty(34 * 4, 34, false, Image.FORMAT_RGBA8)
	for y in 34:
		for x in 34 * 4:
			var tile := x / 34
			var coverage := 0.0
			if tile == 1 or tile == 3: coverage = 1.0
			elif tile == 2:
				var u := clampf(float(x % 34 - 1) / 32.0, 0.0, 1.0)
				coverage = smoothstep(0.25, 0.75, u + 0.06 * sin(float(y) * TAU / 32.0))
			weights.set_pixel(x, y, Color(coverage, coverage if tile == 3 else 0.0, 0.0, 1.0))
	material.set_shader_parameter("water_weights", ImageTexture.create_from_image(weights))
	material.set_shader_parameter("water_atlas_size", Vector2(weights.get_size()))
	material.set_shader_parameter("water_reflection_enabled", false)
	var rain := PackedVector4Array()
	rain.resize(64)
	rain[0] = Vector4(4.0, 2.0, 12.0, 8.0)
	material.set_shader_parameter("water_rain_areas", rain)
	material.set_shader_parameter("water_rain_count", 1)
	material.set_shader_parameter("detail_sun", Vector3(0.18, 0.96, -0.22).normalized())
	var fog := Image.create_empty(64, 64, false, Image.FORMAT_R8)
	for y in 64:
		for x in 64: fog.set_pixel(x, y, Color.WHITE if y >= 32 else Color.BLACK)
	var fog_texture := ImageTexture.create_from_image(fog)
	var mist_colour := Color(0.18, 0.22, 0.29)
	var mist := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	mist.fill(mist_colour)
	material.set_shader_parameter("fog_enabled", true)
	material.set_shader_parameter("fog_from", fog_texture)
	material.set_shader_parameter("fog_to", fog_texture)
	material.set_shader_parameter("fog_size", Vector2i(4, 2))
	material.set_shader_parameter("fog_mist", ImageTexture.create_from_image(mist))
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in 2:
		for tile in 4:
			var offset := vertices.size()
			var x := float(tile * 2)
			var z := float(-row * 2)
			vertices.append_array([Vector3(x, 0, z), Vector3(x + 2, 0, z), Vector3(x + 2, 0, z - 2), Vector3(x, 0, z - 2)])
			uv.append_array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
			for i in 4: uv2.append(Vector2(tile, 1))
			indices.append_array([offset, offset + 1, offset + 2, offset, offset + 2, offset + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	terrain.material_override = material
	stage.add_child(terrain)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	var title := Label.new()
	title.position = Vector2(24, 18)
	title.text = "Synthetic map material probe"
	title.add_theme_font_size_override("font_size", 23)
	overlay.add_child(title)
	var description := Label.new()
	description.position = Vector2(24, 50)
	description.text = "Generated dry ground / clear water / shoreline / bog · rain enabled · second row hidden by fog"
	description.add_theme_font_size_override("font_size", 14)
	overlay.add_child(description)
	material.set_shader_parameter("water_enabled", false)
	var plain := await _map_frame("synthetic_map_water_off")
	material.set_shader_parameter("water_enabled", true)
	var enhanced := await _map_frame("synthetic_map_water_on")
	check(_finite_picture(plain) and _finite_picture(enhanced), "map shader renders nonempty images with finite readable colour samples")
	check(_patch_delta(plain, enhanced, camera, Rect2(2.4, 0.4, 1.2, 1.2)) > 0.02, "enhanced clear water visibly changes the generated water tile")
	check(_patch_delta(plain, enhanced, camera, Rect2(0.4, 0.4, 1.2, 1.2)) < 0.004, "the water preference leaves the fully dry tile unchanged")
	check(_patch_delta(plain, enhanced, camera, Rect2(4.08, 0.4, 0.18, 1.2)) < 0.004, "zero-coverage shoreline pixels remain unchanged")
	check(_patch_delta(plain, enhanced, camera, Rect2(5.68, 0.4, 0.2, 1.2)) > 0.02, "the wet side of the blended shoreline receives water shading")
	var bog := _patch_colour(enhanced, camera, Rect2(6.4, 0.4, 1.2, 1.2))
	check(bog.g > bog.r and bog.g > bog.b, "the bog and rain branches retain the green painted bog palette")
	check(_patch_delta(plain, enhanced, camera, Rect2(2.4, 2.4, 1.2, 1.2)) < 0.004, "complete fog cover still hides enhanced water and its rain ripples")
	var covered := _patch_colour(enhanced, camera, Rect2(2.4, 2.4, 1.2, 1.2))
	check(_colour_delta(covered, mist_colour) < 0.025, "fully fogged water renders the mist colour without leaking surface highlights")
	stage.free()
	await process_frame

func _map_frame(label: String) -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var directory := arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(directory)
			image.save_png(directory.path_join("%s_%s.png" % [RenderingServer.get_current_rendering_method(), label]))
	return image

func _finite_picture(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_width() < 400 or image.get_height() < 300: return false
	var bright := 0
	for y in range(90, image.get_height() - 50, 8):
		for x in range(50, image.get_width() - 50, 8):
			var colour := image.get_pixel(x, y)
			if not is_finite(colour.r) or not is_finite(colour.g) or not is_finite(colour.b): return false
			if maxf(colour.r, maxf(colour.g, colour.b)) > 0.12: bright += 1
	return bright > 300

func _patch_colour(image: Image, camera: Camera3D, area: Rect2) -> Color:
	var result := Color(0.0, 0.0, 0.0, 0.0)
	for y in 4:
		for x in 4:
			var point := area.position + area.size * Vector2((x + 0.5) / 4.0, (y + 0.5) / 4.0)
			var pixel := _map_pixel(image, camera, point)
			result += image.get_pixelv(pixel) / 16.0
	return result

func _patch_delta(a: Image, b: Image, camera: Camera3D, area: Rect2) -> float:
	var difference := 0.0
	for y in 4:
		for x in 4:
			var point := area.position + area.size * Vector2((x + 0.5) / 4.0, (y + 0.5) / 4.0)
			var pixel := _map_pixel(a, camera, point)
			difference += _colour_delta(a.get_pixelv(pixel), b.get_pixelv(pixel)) / 16.0
	return difference

func _map_pixel(image: Image, camera: Camera3D, point: Vector2) -> Vector2i:
	# The game's canvas_items stretch keeps a logical viewport larger than
	# a small test window. Camera projection uses those logical coordinates;
	# the readback image uses the physical render size.
	var projected := camera.unproject_position(Vector3(point.x, 0.0, -point.y))
	var logical_size := camera.get_viewport().get_visible_rect().size
	var pixel := Vector2i(projected * Vector2(image.get_size()) / logical_size)
	return pixel.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)

func _colour_delta(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
