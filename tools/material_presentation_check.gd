extends SceneTree
## Asset-free regression checks for generated cutout mipmaps and the model's
## hit-tint lifecycle. Uses procedural masks and one mesh card, never a game
## installation or saved settings.
##
## godot --headless --path game --script ../tools/material_presentation_check.gd

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_mipmaps()
	_decode_scope()
	_morph_normals()
	_flashes()
	if "--render" in OS.get_cmdline_user_args():
		await _render_flash()
		await _render_morph()
	print("MATERIAL PRESENTATION: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _mask(width := 64, height := 64) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var filled := (x + (y / 8) * 3) % 16 < 1 + (y / 16) % 4
			image.set_pixel(x, y, Color(0.25, 0.8, 0.15, 1.0) if filled else Color(0, 0, 0, 0))
	return image

func _coverage(image: Image, level: int, cutoff := 128) -> float:
	var width := maxi(1, image.get_width() >> level)
	var height := maxi(1, image.get_height() >> level)
	var pixels := image.get_data()
	var start := image.get_mipmap_offset(level) if level > 0 else 0
	var covered := 0
	for at in range(start + 3, start + width * height * 4, 4):
		if pixels[at] >= cutoff: covered += 1
	return float(covered) / float(width * height)

func _mipmaps() -> void:
	check(ELTexture.cutout_mipmaps(null) == null, "a missing image stays missing")
	for filled in [false, true]:
		var image := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.5, 0.8, 1.0 if filled else 0.0))
		var before := image.get_data()
		var made := ELTexture.cutout_mipmaps(image)
		check(image.get_data() == before and not image.has_mipmaps(), "the input of an %s texture is untouched" % ("opaque" if filled else "empty"))
		for level in range(made.get_mipmap_count() + 1):
			check(is_equal_approx(_coverage(made, level), 1.0 if filled else 0.0), "an %s mask stays so at mip %d" % ["opaque" if filled else "empty", level])
	var source := _mask()
	var original := source.get_data()
	var ordinary := source.duplicate() as Image
	ordinary.generate_mipmaps()
	var made := ELTexture.cutout_mipmaps(source)
	check(source.get_data() == original and not source.has_mipmaps(), "a shared cutout image is never edited")
	check(made.get_size() == source.get_size() and made.get_data_size() == ordinary.get_data_size(), "corrected mipmaps use the ordinary chain's memory size")
	var better := false
	for level in range(1, made.get_mipmap_count() + 1):
		var target := _coverage(source, 0)
		var before := absf(_coverage(ordinary, level) - target)
		var after := absf(_coverage(made, level) - target)
		check(after <= before + 0.00001, "thin silhouettes are no farther from the source coverage at mip %d (%.3f -> %.3f)" % [level, before, after])
		better = better or after + 0.00001 < before
	check(better, "thin silhouettes retain more of their source coverage than ordinary mipmaps")
	var pixels := made.get_data()
	var first := made.get_mipmap_offset(1)
	var coloured_edges := false
	for at in range(first, first + 32 * 32 * 4, 4):
		if pixels[at + 3] > 0 and pixels[at + 3] < 255 and pixels[at + 1] > 175: coloured_edges = true
	check(coloured_edges, "transparent black texels no longer darken the cutout's filtered edge")
	var arena := ELTexture.cutout_mipmaps(source, 201.0 / 255.0)
	for level in range(1, arena.get_mipmap_count() + 1):
		check(absf(_coverage(arena, level, 201) - _coverage(source, 0, 201)) <= absf(_coverage(ordinary, level, 201) - _coverage(source, 0, 201)) + 0.00001, "the original arena cutoff is respected at mip %d" % level)
	for size in [Vector2i(1, 1), Vector2i(7, 5), Vector2i(1, 9)]:
		var odd := ELTexture.cutout_mipmaps(_mask(size.x, size.y))
		check(odd != null and odd.get_size() == size, "a %dx%d mask has a valid chain" % [size.x, size.y])
	var benchmark := _mask(256, 256)
	var started := Time.get_ticks_usec()
	ELTexture.cutout_mipmaps(benchmark)
	print("INFO: 256x256 cutout mip generation %.2f ms (loading-time work)" % ((Time.get_ticks_usec() - started) / 1000.0))

## A synthetic one-bit 1555 MMP, with a complete hand-authored 8/4/2/1 chain.
func _mmp() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(ELTexture.DATA_OFFSET + (64 + 16 + 4 + 1) * 2)
	data.encode_u32(0, ELTexture.MAGIC)
	data.encode_u32(4, 8)
	data.encode_u32(8, 8)
	data.encode_u32(12, 4)
	data.encode_u32(16, 0x5551)
	data.encode_u32(20, 16)
	var channels := [[0x8000, 15, 1], [0x7c00, 10, 5], [0x3e0, 5, 5], [0x1f, 0, 5]]
	for channel in 4:
		for field in 3: data.encode_u32(24 + channel * 12 + field * 4, channels[channel][field])
	for index in 85: data.encode_u16(ELTexture.DATA_OFFSET + index * 2, 0x83e0 if index % 3 == 0 else 0)
	return data

func _decode_scope() -> void:
	var bytes := _mmp()
	for folder in ["heroes", "creatures", "terrainobjects"]:
		var decoded := ELProfile._texture_decode({"bytes": bytes, "file": folder + "/test.mmp", "soft": false})
		check(not decoded.is_empty() and decoded.coverage and not decoded.authored, "generated %s cutouts get coverage mipmaps" % folder)
		var profile := ELProfile.new()
		var texture := profile._texture_store("test", decoded)
		check(texture.has_meta(ELTexture.COVERAGE_MASK_MIPS) and not texture.has_meta(ELTexture.AUTHORED_MASK_MIPS), "generated chains are identified separately from original authored masks")
	for folder in ["interface", "effects", "terrain", "heroes/alpha32"]:
		var decoded := ELProfile._texture_decode({"bytes": bytes, "file": folder + "/test.mmp", "soft": false})
		check(not decoded.coverage, "%s keeps ordinary alpha-blended mipmaps" % folder)
	var soft := ELProfile._texture_decode({"bytes": bytes, "file": "heroes/test.mmp", "soft": true})
	check(not soft.coverage, "a skin resolved from Alpha32 keeps its soft alpha")
	var authored := ELProfile._texture_decode({"bytes": bytes, "file": "combatscenes/test.mmp", "soft": false})
	var expected := ELTexture.authored_mask_mipmaps(bytes, ELTexture.decode(bytes))
	check(authored.authored and not authored.coverage and authored.image.get_data() == expected.get_data(), "hand-authored arena mipmaps remain byte-for-byte unchanged")
	var plain_bytes := bytes.duplicate()
	plain_bytes.encode_u32(12, 1)
	plain_bytes.resize(ELTexture.DATA_OFFSET + 8 * 8 * 2)
	var ordinary := ELTexture.decode(plain_bytes)
	ordinary.generate_mipmaps()
	for file in ["combatscenes/alpha/arena_fire.mmp", "combatscenes/arena_fire.mmp"]:
		var blended := ELProfile._texture_decode({"bytes": plain_bytes, "file": file, "entry": "combatscenes/alpha/arena_fire.mmp", "soft": false})
		check(not blended.coverage and blended.image.get_data() == ordinary.get_data(), "arena Alpha particles retain ordinary mipmaps when requested as %s" % file)
	var generated := ELProfile._texture_decode({"bytes": plain_bytes, "file": "combatscenes/scenery.mmp", "soft": false})
	check(generated.coverage and not generated.authored, "ordinary arena scenery still gets generated coverage mipmaps")
	var authored_blend := ELProfile._texture_decode({"bytes": bytes, "file": "combatscenes/alpha/arena_fire.mmp", "soft": false})
	check(authored_blend.authored and not authored_blend.coverage and authored_blend.image.get_data() == expected.get_data(), "existing authored arena Alpha mipmaps retain their original priority")

func _normal_arrays(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func _morph_normals() -> void:
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	var authored := Vector3(0.15, 0.25, 1).normalized()
	var normals := PackedVector3Array([authored, authored, authored, authored, authored, authored])
	var indices := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var sources := PackedInt32Array([0, 1, 2, 1, 3, 2])
	var arrays := _normal_arrays(vertices, normals, indices)
	var rest := ELFigure.MorphNormals.prepare(arrays, sources)
	check(ELFigure.MorphNormals.for_pose(rest, vertices) == normals, "an unchanged morph keeps the artist's exact normals")
	var rotation := Basis(Quaternion(Vector3(0.3, 0.4, 0.5).normalized(), 0.7))
	for scale in [1.0, 2.3]:
		var moved := vertices.duplicate()
		for index in moved.size(): moved[index] = rotation * moved[index] * scale + Vector3(4, -2, 1)
		var transported := ELFigure.MorphNormals.for_pose(rest, moved)
		var good := true
		for normal in transported: good = good and normal.distance_to(rotation * authored) < 0.00002
		check(good, "rigid movement and %.1fx uniform scale preserve authored smooth shading" % scale)
	var bent := vertices.duplicate()
	bent[4].z = 0.75
	var transported := ELFigure.MorphNormals.for_pose(rest, bent)
	check(transported[1].is_equal_approx(transported[3]) and transported[2].is_equal_approx(transported[5]), "a bending surface remains smooth across duplicated UV-seam vertices")
	check(transported[4].distance_to(normals[4]) > 0.2 and transported[4].is_normalized(), "a bent corner's lighting follows its new orientation")
	var hard := normals.duplicate()
	for index in range(3, 6): hard[index] = Vector3(0.0, 0.6, 0.8)
	var split := ELFigure.MorphNormals.prepare(_normal_arrays(vertices, hard, indices), sources)
	var hard_pose := ELFigure.MorphNormals.for_pose(split, bent)
	check(hard_pose[1].distance_to(hard_pose[3]) > 0.1, "deliberately split authored normals retain their hard edge")
	var collapsed := vertices.duplicate()
	collapsed.fill(Vector3.ZERO)
	check(ELFigure.MorphNormals.for_pose(rest, collapsed) == normals, "a collapsed frame keeps finite authored normals")
	var invalid := ELFigure.MorphNormals.prepare(_normal_arrays(collapsed, normals, indices), sources)
	check((invalid.faces as PackedInt32Array).is_empty(), "degenerate rest triangles never enter the transport calculation")
	check(vertices == arrays[Mesh.ARRAY_VERTEX] and normals == arrays[Mesh.ARRAY_NORMAL], "normal preprocessing leaves shared source geometry untouched")
	# Exercise ELFigure.mesh's actual morph upload, not just the helper.
	var track_bytes := PackedByteArray()
	track_bytes.resize(4 * 12)
	# File axes are x, -z, y: only the fourth original vertex bends upward.
	track_bytes.encode_float(3 * 12 + 4, -0.75)
	var figure := {"arrays": arrays, "source_indices": sources}
	var mesh := ELFigure.mesh(figure, {"morph_frames": 1, "morph_vertices": 4, "morph_offset": 0, "data": track_bytes})
	var shapes := mesh.surface_get_blend_shape_arrays(0)
	check(shapes.size() == 1 and (shapes[0][Mesh.ARRAY_NORMAL] as PackedVector3Array)[4].distance_to(normals[4]) > 0.2, "cached animation meshes upload deformed normals with their vertex poses")
	var grid := PackedVector3Array()
	var grid_normals := PackedVector3Array()
	var grid_indices := PackedInt32Array()
	var grid_sources := PackedInt32Array()
	for y in 24:
		for x in 24:
			grid_sources.append(grid.size())
			grid.append(Vector3(float(x) / 24.0, float(y) / 24.0, 0))
			grid_normals.append(Vector3(0, 0, 1))
	for y in 23:
		for x in 23:
			var first := y * 24 + x
			grid_indices.append_array([first, first + 1, first + 24, first + 1, first + 25, first + 24])
	var grid_rest := ELFigure.MorphNormals.prepare(_normal_arrays(grid, grid_normals, grid_indices), grid_sources)
	var pose := grid.duplicate()
	for index in pose.size(): pose[index].z = sin(pose[index].x * PI) * 0.2
	var started := Time.get_ticks_usec()
	for frame in 30: ELFigure.MorphNormals.for_pose(grid_rest, pose)
	print("INFO: morph normals for 576 vertices / 1058 triangles / 30 poses: %.2f ms total (cached preprocessing)" % ((Time.get_ticks_usec() - started) / 1000.0))

func _flashes() -> void:
	var model := ELModel.new()
	var part := MeshInstance3D.new()
	part.mesh = QuadMesh.new()
	var skin := ImageTexture.create_from_image(_mask(16, 16))
	var base := ELFigure.material(skin)
	base.uv1_scale = Vector3(0.5, 0.75, 1.0)
	base.uv1_offset = Vector3(0.1, 0.2, 0.0)
	base.alpha_scissor_threshold = 0.6
	part.material_override = base
	model.add_child(part)
	model.parts["feathers"] = part
	var previous := StandardMaterial3D.new()
	part.material_overlay = previous
	model.flash(Color.RED, 0.1)
	check(part.material_overlay == previous, "a detached model cannot be left with a permanent flash")
	root.add_child(model)
	model.flash(Color.RED, 0.1)
	var flash := part.material_overlay as ShaderMaterial
	check(flash != null and flash.shader == ELModel.HIT_FLASH and part.material_override == base, "a hit adds a tint without replacing the figure's skin")
	check(flash.get_shader_parameter("skin") == skin and flash.get_shader_parameter("cutout") == true and is_equal_approx(flash.get_shader_parameter("alpha_cutoff"), 0.6), "a hit keeps the skin's alpha silhouette and cutoff")
	check(flash.get_shader_parameter("skin_uv") == Vector4(0.5, 0.75, 0.1, 0.2), "a hit uses the figure's exact texture transform")
	base.uv1_offset = Vector3(0.2, 0.3, 0.0)
	model._set_flash_strength(1.0)
	check(flash.get_shader_parameter("skin_uv") == Vector4(0.5, 0.75, 0.2, 0.3), "a hit follows an animated skin's moving atlas window")
	model.set_opacity(0.25)
	model._set_flash_strength(0.5)
	check(is_equal_approx(flash.get_shader_parameter("figure_opacity"), 0.25) and flash.get_shader_parameter("cutout") == false, "a fading figure remains faded during a hit")
	var pulse := model._flash_tween
	pulse.pause()
	pulse.custom_step(0.05)
	check(float(flash.get_shader_parameter("strength")) > 0.0 and float(flash.get_shader_parameter("strength")) < 1.0, "the hit tint fades continuously instead of switching off abruptly")
	pulse.custom_step(0.10)
	check(part.material_overlay == previous and model._flash_overlays.is_empty(), "the previous overlay returns after the fading pulse")
	model.set_opacity(1.0)
	model.flash(Color.RED, 0.12)
	pulse = model._flash_tween
	pulse.pause()
	pulse.custom_step(0.03)
	model.flash(Color.YELLOW, 0.18)
	var second := part.material_overlay
	check(not pulse.is_valid(), "a repeated hit cancels its previous fade controller")
	pulse = model._flash_tween
	pulse.pause()
	pulse.custom_step(0.12)
	check(part.material_overlay == second, "a repeated hit survives the first pulse's old deadline")
	pulse.custom_step(0.10)
	check(part.material_overlay == previous, "a repeated hit still restores the original overlay")
	model.flash(Color.RED, 0.05)
	pulse = model._flash_tween
	pulse.pause()
	var replacement := StandardMaterial3D.new()
	part.material_overlay = replacement
	pulse.custom_step(0.10)
	check(part.material_overlay == replacement, "a pulse never erases an overlay installed by a later effect")
	model.flash(Color.RED, 0.05)
	pulse = model._flash_tween
	pulse.pause()
	part.free()
	pulse.custom_step(0.10)
	check(model._flash_overlays.is_empty(), "a removed mesh is harmless while a hit pulse finishes")
	model.free()

## Real-renderer check: both cards have the same procedural cutouts, the
## right card has the hit tint. Their empty corners must stay transparent.
func _render_flash() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--render requires a real renderer (run without --headless)")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.035, 0.05, 0.075)
	environment.environment = sky
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.position = Vector3(0, 0, 4)
	viewport.add_child(camera)
	camera.current = true
	var source := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var p := Vector2(x - 64, y - 64) / 64.0
			var filled := p.length() < 0.80 and (absi(x - 64) < 9 or ((x + y / 3) % 24 < 13 and absf(p.y) < 0.65))
			if filled: source.set_pixel(x, y, Color(0.22 + float(x) / 500.0, 0.65, 0.30, 1.0))
	var skin := ImageTexture.create_from_image(ELTexture.cutout_mipmaps(source))
	var cards: Array[ELModel] = []
	for index in 2:
		var model := ELModel.new()
		model.position.x = -1.15 if index == 0 else 1.15
		var part := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(1.9, 2.3)
		part.mesh = mesh
		part.material_override = ELFigure.material(skin, true)
		model.add_child(part)
		model.parts["cutout"] = part
		viewport.add_child(model)
		cards.append(model)
	cards[1].flash(Color(1.0, 0.25, 0.2), 5.0)
	cards[1]._flash_tween.pause()
	var captions := CanvasLayer.new()
	viewport.add_child(captions)
	for index in 2:
		var label := Label.new()
		label.text = "SOURCE CUTOUT" if index == 0 else "HIT TINT / SAME SILHOUETTE"
		label.position = Vector2(95 if index == 0 else 530, 40)
		label.add_theme_font_size_override("font_size", 21)
		captions.add_child(label)
	var note := Label.new()
	note.text = "Procedural rendering check - no original game assets"
	note.position = Vector2(190, 490)
	note.add_theme_font_size_override("font_size", 18)
	captions.add_child(note)
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var holes: Array[Color] = []
	var solids: Array[Color] = []
	for model in cards:
		var hole := camera.unproject_position(model.position + Vector3(-0.84, 0.95, 0))
		var solid := camera.unproject_position(model.position)
		var to_image := Vector2(image.get_size()) / viewport.get_visible_rect().size
		holes.append(image.get_pixelv(Vector2i(hole * to_image)))
		solids.append(image.get_pixelv(Vector2i(solid * to_image)))
	check(Vector3(holes[0].r, holes[0].g, holes[0].b).distance_to(Vector3(holes[1].r, holes[1].g, holes[1].b)) < 0.02, "rendered hit tint leaves transparent card corners unchanged")
	check(solids[1].r > solids[0].r + 0.12 and solids[1].g < solids[0].g, "rendered hit tint changes the visible skin")
	var folder := "user://material_presentation"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("material-hit-flash.png")
	check(image.save_png(path) == OK, "rendered cutout comparison saved to %s" % path)
	viewport.free()

## A real morph upload: the left strip bends with stale rest normals, the
## right with transported authored normals. Both have identical geometry,
## material and lighting. The right one's shading must follow the bend.
func _render_morph() -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.035, 0.05, 0.075)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color.WHITE
	sky.ambient_light_energy = 0.15
	sky.ambient_light_sky_contribution = 0.0
	environment.environment = sky
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.3
	camera.position = Vector3(0, 0, 5)
	viewport.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.8
	viewport.add_child(sun)
	sun.look_at_from_position(Vector3(-3, 2, 4), Vector3.ZERO)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var sources := PackedInt32Array()
	var pose := PackedVector3Array()
	for y in 9:
		for x in 33:
			var point := Vector3(lerpf(-1.2, 1.2, float(x) / 32.0), lerpf(-0.8, 0.8, float(y) / 8.0), 0)
			sources.append(vertices.size())
			vertices.append(point)
			normals.append(Vector3(0, 0, 1))
			pose.append(Vector3(sin(point.x * 0.95) / 0.95, point.y, (1.0 - cos(point.x * 0.95)) / 0.95))
	for y in 8:
		for x in 32:
			var first := y * 33 + x
			# Godot's front faces wind clockwise. The source FIG reader already
			# reverses its source indices; this procedural mesh must do so too.
			indices.append_array([first, first + 33, first + 1, first + 1, first + 33, first + 34])
	var arrays := _normal_arrays(vertices, normals, indices)
	var old_arrays := _normal_arrays(pose, normals, indices)
	var uvs := PackedVector2Array()
	uvs.resize(vertices.size())
	# Use a proper skin parameterization. The all-zero UV placeholder rendered
	# black with the standard material in the real-renderer fixture.
	for index in vertices.size():
		uvs[index] = Vector2((vertices[index].x + 1.2) / 2.4, (vertices[index].y + 0.8) / 1.6)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	old_arrays[Mesh.ARRAY_TEX_UV] = uvs
	var old_mesh := ArrayMesh.new()
	old_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_arrays)
	var data := PackedByteArray()
	data.resize(pose.size() * 12)
	for index in pose.size():
		var delta := pose[index] - vertices[index]
		data.encode_float(index * 12, delta.x)
		data.encode_float(index * 12 + 4, -delta.z)
		data.encode_float(index * 12 + 8, delta.y)
	var new_mesh := ELFigure.mesh({"arrays": arrays, "source_indices": sources}, {"morph_frames": 1, "morph_vertices": pose.size(), "morph_offset": 0, "data": data})
	var white := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var material := ELFigure.material(ImageTexture.create_from_image(white))
	material.albedo_color = Color(0.35, 0.58, 0.8)
	for index in 2:
		var part := MeshInstance3D.new()
		part.position.x = -1.4 if index == 0 else 1.4
		part.mesh = old_mesh if index == 0 else new_mesh
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		viewport.add_child(part)
		if index == 1: part.set_blend_shape_value(0, 1.0)
	var captions := CanvasLayer.new()
	viewport.add_child(captions)
	for index in 2:
		var label := Label.new()
		label.text = "BEFORE / REST NORMALS" if index == 0 else "AFTER / DEFORMED NORMALS"
		label.position = Vector2(60 if index == 0 else 525, 40)
		label.add_theme_font_size_override("font_size", 21)
		captions.add_child(label)
	var note := Label.new()
	note.text = "Same bent mesh and light - procedural animation test"
	note.position = Vector2(190, 490)
	note.add_theme_font_size_override("font_size", 18)
	captions.add_child(note)
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var contrast: Array[float] = []
	var to_image := Vector2(image.get_size()) / viewport.get_visible_rect().size
	for centre in [-1.4, 1.4]:
		var left := camera.unproject_position(Vector3(centre - 0.65, 0, 0)) * to_image
		var right := camera.unproject_position(Vector3(centre + 0.65, 0, 0)) * to_image
		var first := image.get_pixelv(Vector2i(left))
		var second := image.get_pixelv(Vector2i(right))
		contrast.append(Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b)))
	check(contrast[1] > contrast[0] + 0.04, "rendered morph lighting follows the curved surface (contrast %.3f -> %.3f)" % [contrast[0], contrast[1]])
	var folder := "user://material_presentation"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("material-morph-normals.png")
	check(image.save_png(path) == OK, "rendered morph comparison saved to %s" % path)
	viewport.free()
