extends SceneTree
## Original-asset-free preview lifecycle and cache isolation checks.
## Real rendering verifies hidden framing and retained animated textures.
##   godot --headless --path game --script ../tools/portrait_presentation_performance_check.gd
##   godot --path game --script ../tools/portrait_presentation_performance_check.gd -- --render --shots=/absolute/output

class BustProbe extends ELAutochessBust:
	var draws := 0
	func _draw() -> void:
		draws += 1
		super()

class FigureProbe extends ELAutochessFigure:
	var draws := 0
	func _draw() -> void:
		draws += 1
		super()

class StageClock extends Node:
	var ticks := 0
	func _process(_delta: float) -> void:
		ticks += 1

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
	_cache_ownership()
	await _lifecycle()
	if OS.get_cmdline_user_args().has("--render"): await _rendered()
	else: print("SKIP: GPU framing, redraws and retained texture pixel checks (requires --render)")
	ELAutochessFigure.free_spares()
	await process_frame
	print("Portrait presentation performance: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _profile(colour: Color, height := 1.0) -> ELProfile:
	var profile := ELProfile.new()
	profile.id = "el2"
	profile.tables.HeroTemplates = {"Fixture": {"Model": "fixture", "Texture": "fixture"}}
	profile.tables.CombatCreatures = {"FIX": {"Model": "fixture", "Texture": "fixture", "Scale": 1.0}}
	var texture := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	texture.fill(colour)
	var skin := ImageTexture.create_from_image(texture)
	profile._textures["heroes/fixture"] = skin
	profile._textures["creatures/fixture"] = skin
	var body := CapsuleMesh.new()
	body.height = 1.8 * height
	body.radius = 0.4 * height
	var head := SphereMesh.new()
	head.radius = 0.28 * height
	head.height = 0.56 * height
	var body_mesh := _offset_mesh(body, Vector3(0, 0.9 * height, 0))
	var head_mesh := _offset_mesh(head, Vector3(0, 2.03 * height, 0))
	profile.model_resources.fixture = {"links": [["body", ""], ["head", ""]],
		"figures": {"body": {"material_id": ELFigure.MATERIAL_MAGIC, "texture_slot": 1}, "head": {"material_id": ELFigure.MATERIAL_MAGIC, "texture_slot": 1}},
		"meshes": {"base/body": body_mesh, "base/head": head_mesh}, "animations": null, "clips": {}, "timing": {}}
	return profile

func _offset_mesh(source: PrimitiveMesh, offset: Vector3) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in positions.size(): positions[index] += offset
	arrays[Mesh.ARRAY_VERTEX] = positions
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _cache_ownership() -> void:
	var first := _profile(Color("cf8f62"))
	var second := _profile(Color("79a8bd"), 1.5)
	var measurements := ELAutochessBust._measurements(first)
	measurements.Fixture = [Rect2(0, 2, 1, 1), 2.0, Vector3.ZERO]
	check(ELAutochessBust.is_measured("Fixture", first) and not ELAutochessBust.is_measured("Fixture", second), "same-named hero bust measurements stay in their source profile")
	first.generation = ELProfile.new().generation
	check(not ELAutochessBust.is_measured("Fixture", first), "remounting a profile discards its stale bust measurements")
	var key := "FIX|%.3f|%.3f|%.3f|true" % [deg_to_rad(-28.0), deg_to_rad(10.0), 0.88]
	ELAutochessFigure._profile_framings(first)[key] = {"fixture": true}
	check(ELAutochessFigure.is_framed("FIX", deg_to_rad(-28.0), deg_to_rad(10.0), 0.88, true, first)
		and not ELAutochessFigure.is_framed("FIX", deg_to_rad(-28.0), deg_to_rad(10.0), 0.88, true, second), "same-named creature framings stay in their source profile")
	first.generation = ELProfile.new().generation
	check(not ELAutochessFigure.is_framed("FIX", deg_to_rad(-28.0), deg_to_rad(10.0), 0.88, true, first), "remounting a profile discards stale creature framing")

func _lifecycle() -> void:
	var first := _profile(Color("cf8f62"))
	var second := _profile(Color("79a8bd"), 1.5)
	var bust := ELAutochessBust.new()
	root.add_child(bust)
	bust.size = Vector2(240, 220)
	check(not bust.is_processing() and bust.view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "an empty bust does not process or draw its viewport")
	bust.show_hero(first, "Fixture")
	var old_model := bust.model
	bust.show_hero(first, "Fixture")
	check(bust.model == old_model, "repeating the same hero and profile reuses its live model")
	bust.show_hero(second, "Fixture")
	check(bust.model != old_model and bust.model.profile == second and old_model.is_queued_for_deletion(), "a same-named hero from another profile rebuilds with that profile's model")
	old_model = bust.model
	second.generation = ELProfile.new().generation
	bust._process(0.0)
	check(bust.model != old_model and bust._source_generation == second.generation and not ELAutochessBust.is_measured("Fixture", second), "a remount during bust measurement rebuilds before publishing stale bounds")
	bust._framed = 7
	bust._sync_activity()
	bust.hide()
	check(not bust.is_processing() and bust.view.process_mode == Node.PROCESS_MODE_DISABLED and bust.view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "a hidden settled bust stops both animation and viewport work")
	bust.show()
	check(bust.is_processing() and bust.view.process_mode == Node.PROCESS_MODE_INHERIT and bust.view.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "showing a settled bust restores animation and visible-only rendering")
	bust.show_hero(second, "Missing")
	check(bust.model == null and bust._framed == 0 and not bust.is_processing(), "a missing hero clears the old bust and stops its empty stage")
	bust.free()
	ELAutochessFigure.free_spares()
	var figure := ELAutochessFigure.new()
	root.add_child(figure)
	figure.size = Vector2(160, 160)
	check(not figure.is_processing(), "an empty creature preview has no frame callback")
	figure.show_code(first, "FIX")
	var first_view := figure.view
	figure._framed = 24
	figure.release()
	check(ELAutochessFigure._spare_count == 1 and first_view.get_parent() == null and first_view.process_mode == Node.PROCESS_MODE_DISABLED, "a released settled creature reuses a detached, fully paused stage")
	figure.show_code(second, "FIX")
	check(figure.view != first_view and figure.model.profile == second, "the spare-view pool cannot reuse another profile's same-named creature")
	figure._framed = 24
	figure.release()
	figure.show_code(first, "FIX")
	check(figure.view == first_view and figure.view.process_mode == Node.PROCESS_MODE_INHERIT, "the matching source profile recovers its own paused spare")
	figure._framed = 24
	figure._sync_activity()
	figure.hide()
	check(not figure.is_processing() and figure.view.process_mode == Node.PROCESS_MODE_DISABLED and figure.view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "a hidden settled creature preview pauses its model, effects and viewport")
	figure.show()
	check(figure.is_processing() and figure.view.process_mode == Node.PROCESS_MODE_INHERIT, "showing a creature preview restores its whole stage")
	var old_view := figure.view
	first.generation = ELProfile.new().generation
	figure._process(0.0)
	check(figure.view != old_view and old_view.is_queued_for_deletion(), "remounting a live creature rebuilds before publishing stale framing and discards its older-generation viewport")
	figure.release()
	figure.free()
	ELAutochessFigure.free_spares()
	var portraits := ELAutochessPortraits.new()
	root.add_child(portraits)
	portraits.profile = first
	check(not portraits.is_processing(), "an empty still-portrait cache has no frame callback")
	portraits.texture("FIX")
	check(portraits.is_processing() and portraits.settling() == 1, "a new still portrait enables its finite framing sequence")
	var view: SubViewport = portraits._views.FIX
	portraits._settling.FIX = 22
	portraits._process(0.0)
	check(not portraits.is_processing() and portraits.settling() == 0 and view.process_mode == Node.PROCESS_MODE_DISABLED
		and view.render_target_update_mode == SubViewport.UPDATE_ONCE, "a settled portrait freezes its entire stage and stops the manager callback")
	portraits.profile = second
	check(portraits._views.is_empty() and view.is_queued_for_deletion(), "changing portrait profile discards all older content views")
	portraits.texture("FIX")
	view = portraits._views.FIX
	second.generation = ELProfile.new().generation
	portraits.texture("FIX")
	check(portraits._views.FIX != view and view.is_queued_for_deletion(), "remounting the same portrait profile replaces its old generated textures")
	portraits.free()
	var failed_bust := ELAutochessBust.new()
	var failed_figure := ELAutochessFigure.new()
	root.add_child(failed_bust)
	root.add_child(failed_figure)
	failed_bust.show_hero(second, "Missing")
	failed_figure.show_code(second, "MISSING")
	# Exercise only the real in-flight filter. The existing load wait returns
	# before the screen starts unrelated loading work in this fixture.
	var screen: Node = load("res://src/autochess/screen.gd").new()
	screen._load_tasks.assign([["settle", ""]])
	screen._load_wait = 1
	var already_freed := ELAutochessBust.new()
	screen._framing.assign([failed_bust, failed_figure, already_freed])
	already_freed.free()
	screen._load_step()
	check(screen._framing.is_empty() and failed_bust.is_queued_for_deletion() and failed_figure.is_queued_for_deletion(), "missing preview assets and an already-freed control leave the loading queue without blocking its finite framing slots")
	screen.free()
	await process_frame

func _settle(frames := 3) -> void:
	for frame in frames: await process_frame
	await RenderingServer.frame_post_draw

func _rendered() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--render requires a windowed backend")
		return
	var profile := _profile(Color("cf8f62"))
	var bust := BustProbe.new()
	bust.size = Vector2(240, 220)
	bust.position = Vector2(80, 150)
	bust.hide()
	root.add_child(bust)
	bust.show_hero(profile, "Fixture")
	for frame in 40:
		if bust._framed > 6: break
		await process_frame
	check(bust._framed > 6 and ELAutochessBust.is_measured("Fixture", profile), "a hidden loading bust finishes real GPU head measurement")
	check(not bust.is_processing() and bust.view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the hidden bust stops work immediately after framing")
	bust.show()
	await _settle()
	var draws := bust.draws
	await _settle(12)
	check(bust.draws == draws, "an unchanged visible bust retains its canvas draw commands across 12 display frames")
	var prior := root.get_texture().get_image()
	(bust.model.parts.head as MeshInstance3D).position.x += 0.12
	await _settle()
	check(bust.draws == draws and root.get_texture().get_image().get_data() != prior.get_data(), "the bust's live viewport texture changes on screen without a CanvasItem redraw")
	var clock := StageClock.new()
	bust.view.add_child(clock)
	await _settle()
	bust.hide()
	var ticks := clock.ticks
	await _settle(12)
	check(clock.ticks == ticks, "hidden bust descendants execute zero frame callbacks")
	bust.show()
	await _settle()
	check(clock.ticks > ticks, "hidden bust descendants resume when the bust returns")
	bust.scale = Vector2.ONE * 1.5
	await _settle()
	check(bust.view.size == Vector2i(360, 330), "a scaled bust retains its full on-screen rendering resolution")
	bust.scale = Vector2.ONE
	var figure := FigureProbe.new()
	figure.size = Vector2(240, 220)
	figure.position = Vector2(460, 150)
	figure.hide()
	root.add_child(figure)
	figure.show_code(profile, "FIX")
	for frame in 40:
		if figure._framed >= 24: break
		await process_frame
	check(figure._framed >= 24, "a hidden loading creature finishes its real GPU framing sequence")
	check(not figure.is_processing() and figure.view.process_mode == Node.PROCESS_MODE_DISABLED, "the hidden creature stage pauses once framing has completed")
	figure.show()
	await _settle()
	draws = figure.draws
	await _settle(12)
	check(figure.draws == draws, "an unchanged live creature preview retains its canvas commands across 12 display frames")
	prior = root.get_texture().get_image()
	(figure.model.parts.head as MeshInstance3D).position.x += 0.14
	await _settle()
	check(figure.draws == draws and root.get_texture().get_image().get_data() != prior.get_data(), "the creature's animated viewport remains live without rebuilding canvas commands")
	var effect_clock := StageClock.new()
	figure.view.add_child(effect_clock)
	figure.hide()
	ticks = effect_clock.ticks
	await _settle(12)
	check(effect_clock.ticks == ticks, "hidden creature effects execute zero frame callbacks")
	figure.show()
	await _settle()
	check(effect_clock.ticks > ticks, "creature effects resume with their preview")
	var portraits := ELAutochessPortraits.new()
	root.add_child(portraits)
	portraits.profile = profile
	portraits.texture("FIX")
	var portrait_view: SubViewport = portraits._views.FIX
	var still_clock := StageClock.new()
	portrait_view.add_child(still_clock)
	for frame in 30:
		if portraits.settling() == 0: break
		await process_frame
	await _settle()
	check(portraits.settling() == 0 and not portraits.is_processing(), "a real still portrait finishes its finite GPU framing sequence")
	ticks = still_clock.ticks
	var still_pixels := portrait_view.get_texture().get_image().get_data()
	await _settle(12)
	check(still_clock.ticks == ticks and portrait_view.get_texture().get_image().get_data() == still_pixels, "a finished portrait keeps stable pixels with no descendant frame callbacks")
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): folder = arg.trim_prefix("--shots=")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		bust.view.get_texture().get_image().save_png(folder.path_join("preview_bust_generated_fixture.png"))
		figure.view.get_texture().get_image().save_png(folder.path_join("preview_creature_generated_fixture.png"))
		portrait_view.get_texture().get_image().save_png(folder.path_join("preview_still_generated_fixture.png"))
	bust.free()
	figure.release()
	figure.free()
	portraits.free()
	await process_frame
