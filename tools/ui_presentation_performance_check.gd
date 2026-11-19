extends SceneTree
## Asset-free UI scheduling, pointer and mist regressions. The rendering
## probes count real CanvasItem redraws and compare actual viewport pixels.
##   godot --headless --path game --script ../tools/ui_presentation_performance_check.gd
##   godot --path game --script ../tools/ui_presentation_performance_check.gd -- --render --shots=/absolute/output

class SymbolProbe extends ELCombatSymbols:
	var draws := 0
	var glyphs := 0
	func _draw() -> void:
		draws += 1
		super()
	func _draw_glyph(code: int, colour: Color, rect: Rect2) -> void:
		glyphs += 1
		super(code, colour, rect)

class NoticeProbe extends ELCombatNotices:
	var draws := 0
	var drawn_icons := 0
	func _draw() -> void:
		draws += 1
		super()
	func icon_texture(index: int) -> Texture2D:
		drawn_icons += 1
		return super(index)

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_cursors()
	_mist()
	_notices()
	_symbols()
	if OS.get_cmdline_user_args().has("--render"): await _rendered()
	else: print("SKIP: actual CanvasItem redraw counts and mist pixels (requires --render)")
	print("UI presentation performance: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _texture(colour: Color, extent := Vector2i(48, 48)) -> ImageTexture:
	var image := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

func _cursors() -> void:
	var profile := ELProfile.new()
	profile.id = "el2"
	var one := _texture(Color.WHITE)
	var two := _texture(Color("dbc58b"))
	profile.cursor_cache = {
		"default": {"frames": [one], "hotspot": Vector2i(2, 0)},
		"scroll_r": {"frames": [one], "hotspot": Vector2i(48, 24)},
		"scroll_dr": {"frames": [one], "hotspot": Vector2i(48, 48)},
		"spell": {"frames": [one, two], "hotspot": Vector2i.ZERO}}
	var driver := ELCursorDriver.new()
	root.add_child(driver)
	driver.select(profile, "default")
	check(not driver.is_processing() and driver.uploads == 1, "a single-frame cursor uploads once and has no frame callback")
	driver.select(profile, "scroll_r")
	check(driver.uploads == 2 and driver.shown.point == Vector2(47, 24), "a shared cursor image uploads its changed edge hotspot")
	driver.select(profile, "scroll_r")
	check(driver.uploads == 2, "repeated requests do not upload an unchanged cursor")
	check(driver.set_carry(profile, two), "the cursor can carry an independent icon texture")
	check(driver.shown.point == Vector2(47, 24), "a carried scroll cursor clamps its hotspot to the icon's last pixel")
	var carried_uploads := driver.uploads
	driver.select(profile, "scroll_dr")
	check(driver.uploads == carried_uploads + 1 and driver.shown.point == Vector2(47, 47), "a carried picture follows a changed hotspot without changing its image")
	driver.set_carry(profile, null)
	driver.select(profile, "spell")
	check(driver.is_processing(), "an animated cursor enables its frame clock")
	driver._process(ELCursors.FRAME_TIME * 0.5)
	check(int(driver.positions.get("spell", 0)) == 0, "a cursor frame is retained before its authored 125 ms interval")
	driver._process(ELCursors.FRAME_TIME * 0.5)
	check(driver.positions.spell == 1 and driver.shown.frame == 1, "the animated cursor steps at the authored interval")
	driver._process(ELCursors.FRAME_TIME * 5.0)
	check(driver.positions.spell == 0 and is_zero_approx(driver.clock), "a stalled cursor catches up modulo its frame count")
	driver.select(profile, "missing")
	check(not driver.is_processing() and driver.shown.is_empty(), "a missing cursor restores the system pointer and stops frame callbacks")
	driver.select(profile, "default")
	profile.cursor_cache.default = {"frames": [two], "hotspot": Vector2i(3, 1)}
	profile.generation = ELProfile.new().generation
	driver.select(profile, "default")
	check(driver.shown.image == two and driver.shown.point == Vector2(3, 1), "a remounted profile refreshes an unchanged cursor name from its new content")
	driver.free()

func _mist() -> void:
	var mist := ELFogMist.new()
	root.add_child(mist)
	mist.process_mode = Node.PROCESS_MODE_DISABLED
	var requests := 0
	for frame in 240:
		# Model consumption of UPDATE_ONCE without needing a GPU in this test.
		mist.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mist.advance(1.0 / 240.0)
		if mist.render_target_update_mode == SubViewport.UPDATE_ONCE: requests += 1
	check(requests >= 63 and requests <= 64, "240 frames request only the 63–64 distinct byte-weight mist images (%d)" % requests)
	check(is_equal_approx(mist.drift, 0.01) and mist.step == 4, "skipped mist renders preserve continuous drift and the four-step clock")
	mist.animate = false
	mist.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var old_weight := mist.weight()
	for frame in 60: mist.advance(1.0 / 60.0)
	check(mist.render_target_update_mode == SubViewport.UPDATE_DISABLED and mist.weight() == old_weight and is_equal_approx(mist.drift, 0.02), "disabled fog animation drifts without rerendering its unchanged texture")
	mist.animate = true
	mist.render_active = false
	var state := mist.rng.state
	mist.advance(8.25)
	check(mist.render_target_update_mode == SubViewport.UPDATE_DISABLED and mist.rng.state != state and is_equal_approx(mist.drift, 0.1025), "a hidden map keeps advancing noise and drift without drawing the mist viewport")
	mist.render_active = true
	check(mist.render_target_update_mode == SubViewport.UPDATE_ONCE and int(mist._material.get_shader_parameter("weight")) == mist.weight(), "reactivating mist requests its current blend immediately")
	mist.render_target_update_mode = SubViewport.UPDATE_DISABLED
	old_weight = mist.weight()
	mist.advance(4.0)
	check(mist.render_target_update_mode == SubViewport.UPDATE_ONCE and mist.weight() == old_weight, "replaced source grids request a render even when a whole cycle returns to the same byte weight")
	mist.free()

func _notices() -> void:
	var notices := ELCombatNotices.new()
	root.add_child(notices)
	check(not notices.is_processing(), "an empty notice layer has no frame callback")
	var icon := _texture(Color("bc9a63"))
	notices.add_icon(icon, "fixture", 0, "Generated test icon")
	check(not notices.is_processing(), "a static cast-icon list has no frame callback")
	notices.add_line("Generated cast message", Color.WHITE)
	check(notices.is_processing(), "a new timed message enables processing")
	var same_lines := notices.lines
	notices._process(1.0)
	check(is_equal_approx(float(notices.lines[0].age), 1.0), "a held message keeps its full original lifetime")
	notices._process(2.6)
	check(same_lines.is_empty() and notices.lines.is_empty() and not notices.is_processing(), "expired messages compact the existing array and stop processing")
	notices.halves.assign([icon, icon])
	notices.show_banner(1)
	check(notices.is_processing() and notices.banner == 1, "a phase banner enables processing")
	notices._process(0.3)
	check(notices._sounded and notices.banner == 1, "the original banner sound boundary is crossed once")
	notices._process(1.21)
	check(notices.banner == -1 and not notices.is_processing(), "the phase banner retires after its original 1.5 seconds")
	notices.clear()
	for index in 1000: notices.icons.append({"texture": icon, "card": "fixture", "side": index % 2, "tooltip": str(index)})
	var indices := notices.visible_icon_range()
	check(indices.y - indices.x <= 30 and indices.y == 1000, "a 1000-icon history submits at most its 30 potentially visible icons")
	var clipped_correctly := true
	var view := notices.get_viewport_rect()
	for index in notices.icons.size():
		if notices.icon_rect(index).intersects(view) and (index < indices.x or index >= indices.y): clipped_correctly = false
	check(clipped_correctly, "the clipped icon range includes the preceding row's visible five-pixel sliver")
	var identical := true
	var samples: Array[Vector2] = []
	for scale in [0.5, 0.75, 1.0, 1.175, 1.3333, 1.6, 2.25]:
		notices.ui_scale = scale
		for index in range(975, 1000):
			var cell := notices.icon_rect(index)
			for point: Vector2 in [cell.get_center(), cell.position, cell.end, cell.end + Vector2(1, 1)]:
				identical = identical and notices._icon_at(point) == _linear_notice_at(notices, point)
				if scale == 1.0: samples.append(point)
	check(identical, "direct icon picking matches the original scan at several scales, cell edges and gaps")
	notices.ui_scale = 1.0
	if OS.get_cmdline_user_args().has("--benchmark"): _benchmark_notices(notices, samples)
	notices.free()

func _benchmark_notices(notices: ELCombatNotices, samples: Array[Vector2]) -> void:
	var old_times: Array[float] = []
	var new_times: Array[float] = []
	# Warm both paths before interleaving six measured runs. The reference
	# is V3's rectangle scan, with the same real notice layout method.
	for repeat in 8:
		var begin := Time.get_ticks_usec()
		for point in samples: _linear_notice_at(notices, point)
		var elapsed := (Time.get_ticks_usec() - begin) / 1000.0
		if repeat >= 2: old_times.append(elapsed)
		begin = Time.get_ticks_usec()
		for point in samples: notices._icon_at(point)
		elapsed = (Time.get_ticks_usec() - begin) / 1000.0
		if repeat >= 2: new_times.append(elapsed)
	old_times.sort()
	new_times.sort()
	print("BENCHMARK_JSON: " + JSON.stringify({"name": "cast_icon_hit_test", "v3_ms": (old_times[2] + old_times[3]) * 0.5,
		"v4_ms": (new_times[2] + new_times[3]) * 0.5, "runs": 6, "queries": samples.size(), "history_icons": notices.icons.size(),
		"scope": "CPU-only synthetic hover queries against a long icon history; no game frame-rate claim"}))

func _linear_notice_at(notices: ELCombatNotices, at: Vector2) -> int:
	for index in notices.icons.size():
		if notices.icon_rect(index).has_point(at): return index
	return -1

func _symbols() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position.z = 10.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	var symbols := ELCombatSymbols.new()
	root.add_child(symbols)
	symbols.camera = camera
	check(not symbols.is_processing(), "an empty figure readout layer has no frame callback")
	var figures: Array = []
	for index in 8:
		figures.append({"id": index, "top": Vector3((index % 4) * 1.6 - 2.4, floori(index / 4.0) * 1.8 - 1.0, 0),
			"numbers": ELCombatSymbols.number_row(index, index + 2, false, false),
			"icons": [15, 17, 20, 37], "order": ELCombatSymbols.order_row(index + 1, 0)})
	symbols.figures = figures
	check(symbols.is_processing(), "visible figure readouts watch camera movement")
	var identical := true
	for projection in [Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_FRUSTUM]:
		camera.projection = projection
		camera.frustum_offset = Vector2(0.05, 0.03)
		for figure: Dictionary in figures:
			for icon: Dictionary in symbols.icon_rects(figure):
				for point: Vector2 in [icon.rect.get_center(), icon.rect.position, icon.rect.end]:
					identical = identical and symbols.icon_at(point) == _linear_symbol_at(symbols, point)
	check(identical, "direct figure-icon picking matches the original rectangle scan in all three camera projections")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	symbols.figures = [{"id": 1, "top": Vector3.ZERO, "icons": [15]}, {"id": 2, "top": Vector3(0, 0, 2), "icons": [17]}]
	var at: Vector2 = symbols.icon_rects(symbols.figures[0])[0].rect.get_center()
	check(symbols.icon_at(at).get("id", -1) == 2 and symbols.icon_at(at).get("bit", -1) == 3, "overlapping icons still pick the nearest figure")
	check(symbols._view_changed() and not symbols._view_changed(), "unchanged camera and canvas state does not invalidate static rows")
	camera.position.x += 1.0
	check(symbols._view_changed(), "camera movement invalidates projected readouts")
	camera.size += 1.0
	check(symbols._view_changed(), "camera zoom invalidates projected readouts")
	symbols.hide()
	check(not symbols.is_processing(), "hidden static readouts stop frame callbacks")
	symbols.add_number(Vector3.ZERO, 5, 7)
	var same_floating := symbols.floating
	check(symbols.is_processing(), "hidden floating numbers still advance their expiry clock")
	symbols._process(3.01)
	check(same_floating.is_empty() and symbols.floating.is_empty() and not symbols.is_processing(), "hidden numbers expire in the original array and leave no live frame callback")
	symbols.show()
	check(symbols.is_processing(), "showing a cached readout layer resumes camera tracking")
	symbols.figures = []
	check(not symbols.is_processing(), "turning off figure rows clears the layer and stops its empty callback")
	symbols.free()
	camera.free()

func _linear_symbol_at(symbols: ELCombatSymbols, point: Vector2) -> Dictionary:
	var found := {}
	var depth := INF
	for figure: Dictionary in symbols.figures:
		for entry: Dictionary in symbols.icon_rects(figure):
			if int(entry.bit) < 0 or not (entry.rect as Rect2).has_point(point): continue
			var distance := symbols.camera.global_position.distance_to(figure.get("top", Vector3.ZERO))
			if distance < depth:
				depth = distance
				found = entry
	return found

func _settle(frames := 3) -> void:
	for frame in frames: await process_frame
	await RenderingServer.frame_post_draw

func _rendered() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--render requires a windowed rendering backend")
		return
	var notices := NoticeProbe.new()
	root.add_child(notices)
	var icon := _texture(Color("b99256"))
	for index in 1000: notices.icons.append({"texture": icon, "card": "fixture", "side": index % 2, "tooltip": str(index)})
	notices.queue_redraw()
	await _settle()
	check(notices.drawn_icons <= 30, "the actual draw function submits at most 30 of 1000 historical cast icons")
	var before := notices.draws
	await _settle(24)
	check(notices.draws == before, "static spell icons generate zero additional redraws over 24 display frames")
	notices.add_line("Generated hold-period message", Color.WHITE)
	await _settle()
	notices.process_mode = Node.PROCESS_MODE_DISABLED
	before = notices.draws
	for frame in 24:
		notices._process(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	check(notices.draws == before, "a held message generates zero additional redraws over 24 display frames")
	notices._process(3.0)
	await _settle()
	check(notices.draws > before, "entering the original message fade redraws the notice layer")
	notices.free()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position.z = 10.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	var symbols := SymbolProbe.new()
	root.add_child(symbols)
	symbols.camera = camera
	symbols.sheet = _texture(Color.WHITE, Vector2i(256, 256))
	symbols.figures = [{"id": 0, "top": Vector3.ZERO, "numbers": ELCombatSymbols.number_row(12, 8, true, false), "icons": [15, 17]}]
	await _settle()
	before = symbols.draws
	for frame in 24:
		# The battle view supplies a fresh equal array every frame.
		symbols.figures = symbols.figures.duplicate(true)
		await process_frame
	await RenderingServer.frame_post_draw
	check(symbols.draws == before, "24 equal figure arrays and a static camera cause zero additional readout redraws")
	camera.position.x = 0.4
	await _settle()
	check(symbols.draws > before, "moving the actual camera redraws the retained readouts")
	before = symbols.draws
	symbols.figures = [{"id": 0, "top": Vector3(1000, 0, 0), "numbers": ELCombatSymbols.number_row(12, 8, true, false), "icons": [15, 17]}]
	var glyphs := symbols.glyphs
	await _settle()
	check(symbols.draws > before and symbols.glyphs == glyphs, "offscreen figure rows submit no glyph draw calls")
	symbols.free()
	camera.free()
	await _render_mist()

func _render_mist() -> void:
	var current := ELFogMist.new()
	var reference := ELFogMist.new()
	root.add_child(current)
	root.add_child(reference)
	current.process_mode = Node.PROCESS_MODE_DISABLED
	reference.process_mode = Node.PROCESS_MODE_DISABLED
	reference._from.update(current._from.get_image())
	reference._to.update(current._to.get_image())
	await _settle()
	var old_pixels := current.get_texture().get_image().get_data()
	current.render_active = false
	current.advance(1.5)
	reference.advance(1.5)
	reference.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _settle()
	check(current.get_texture().get_image().get_data() == old_pixels, "a disabled mist viewport retains its last completed pixels")
	check(reference.get_texture().get_image().get_data() != old_pixels, "the continuously rendered reference has a visibly different later noise blend")
	current.render_active = true
	await _settle()
	var resumed := current.get_texture().get_image()
	check(resumed.get_data() == reference.get_texture().get_image().get_data(), "reactivated one-shot mist exactly matches the continuously rendered reference pixels")
	# Changing a GPU uniform without requesting a frame must not redraw a
	# completed one-shot viewport. A continuously rendered viewport would
	# immediately show this conspicuously different blend.
	current._material.set_shader_parameter("weight", 255)
	await _settle(12)
	check(current.get_texture().get_image().get_data() == resumed.get_data(), "a changed GPU uniform does not rerender the completed one-shot mist across 12 display frames")
	current.advance(0.5)
	reference.advance(0.5)
	await _settle()
	resumed = current.get_texture().get_image()
	check(resumed.get_data() == reference.get_texture().get_image().get_data() and resumed.get_data() != old_pixels, "a later active mist weight correctly rearms UPDATE_ONCE and matches the continuous reference")
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		resumed.save_png(folder.path_join("ui_mist_resumed.png"))
		reference.get_texture().get_image().save_png(folder.path_join("ui_mist_continuous_reference.png"))
		print("Saved exact mist comparison pixels to " + folder)
	current.free()
	reference.free()
