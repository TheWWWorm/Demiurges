extends SceneTree
## Asset-free world/HUD correctness checks, plus optional comparative CPU
## timings against the delivered V3 algorithms. No full-game FPS claim.
## godot --headless --path game --script ../tools/world_presentation_performance_check.gd -- --benchmark

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_ground()
	_overview()
	_hidden_mist()
	await _minimap()
	if "--benchmark" in OS.get_cmdline_user_args(): _benchmark()
	if "--render" in OS.get_cmdline_user_args(): await _render_minimap()
	print("WORLD PRESENTATION PERFORMANCE: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _figures(side := 24) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in side:
		for x in side:
			var low := Vector2(float(x) - side * 0.5, float(z) - side * 0.5)
			var first := vertices.size()
			for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				var p: Vector2 = low + corner
				vertices.append(Vector3(p.x, sin(p.x * 0.3) * 0.4 + cos(p.y * 0.2) * 0.25, p.y))
			indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"ground": {"arrays": arrays}}

## Kept byte-for-byte in its arithmetic/order from V3's ground_height().
func _reference_height(figures: Dictionary, x: float, z: float) -> float:
	var point := Vector2(x, z)
	for figure: Dictionary in figures.values():
		var vertices: PackedVector3Array = figure.arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = figure.arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i + 1]]
			var c := vertices[indices[i + 2]]
			var va := Vector2(a.x, a.z)
			var vb := Vector2(b.x, b.z)
			var vc := Vector2(c.x, c.z)
			var determinant := (vb - va).cross(vc - va)
			if absf(determinant) < 0.00001: continue
			var u := (point - va).cross(vc - va) / determinant
			var v := (vb - va).cross(point - va) / determinant
			if u >= -0.001 and v >= -0.001 and u + v <= 1.001:
				return a.y + (b.y - a.y) * u + (c.y - a.y) * v
	return 0.0

func _ground() -> void:
	var figures := _figures()
	var index := ELGroundHeightIndex.new()
	index.build(figures)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4204
	var equal := true
	var maximum_error := 0.0
	for i in 240:
		var p := Vector2(rng.randf_range(-13, 13), rng.randf_range(-13, 13))
		var error := absf(index.height(p.x, p.y) - _reference_height(figures, p.x, p.y))
		maximum_error = maxf(maximum_error, error)
		equal = equal and error < 0.000001
	check(equal, "indexed heights match V3 across 240 seeded interior/exterior points (error %.9f)" % maximum_error)
	check(index.triangle_count == 1152 and index.candidates_at(0.25, 0.25) < 40, "ground queries visit a local bucket instead of all 1,152 triangles")
	check(index.candidates_at(1000, 1000) == 0 and index.height(1000, 1000) == 0.0, "outside-ground fallback avoids all triangle tests")
	var arrays: Array = figures.ground.arrays
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 2, 0), Vector3(10, 4, 0), Vector3(0, 6, 10), Vector3(0, 20, 0), Vector3(0, 20, 10), Vector3(10, 20, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 0, 0, 0, 1, 2, 3, 4, 5])
	index.build(figures)
	check(index.triangle_count == 2 and is_equal_approx(index.height(2, 2), 3.2), "degenerate triangles are skipped and overlapping surfaces keep authored first-hit order")
	var edges_ok := true
	for p in [Vector2(-0.009, -0.009), Vector2(10.018, -0.009), Vector2(-0.009, 10.018), Vector2(5, 5.009), Vector2(5, 5.02), Vector2(-0.02, 0)]:
		edges_ok = edges_ok and is_equal_approx(index.height(p.x, p.y), _reference_height(figures, p.x, p.y))
	check(edges_ok, "bucket boundaries preserve V3's full barycentric edge tolerance")
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-50000, 2, -50000), Vector3(50000, 2, -50000), Vector3(0, 2, 50000)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	index.build(figures)
	check(index._buckets.size() <= 1156 and index.height(0, 0) == 2.0, "a very large triangle keeps the grid bounded")
	var arena := ELArena.new()
	var first := ELModel.new()
	first.figures = figures
	arena.add_child(first)
	arena._ground = first
	check(arena._ground_height_index == null, "ground index remains unallocated until a height is requested")
	check(arena.ground_height(0, 0) == 2.0, "arena height queries use the prepared index")
	var cached := arena._ground_height_index
	arena.ground_height(1, 1)
	check(cached == arena._ground_height_index, "successive queries reuse the same index")
	var second := ELModel.new()
	second.figures = _figures(4)
	arena.add_child(second)
	arena._ground = second
	check(arena._ground_height_index == null and is_equal_approx(arena.ground_height(0, 0), 0.25), "replacing the arena surface invalidates its cached geometry")
	arena._ground = null
	check(arena._ground_height_index == null and arena.ground_height(0, 0) == 0.0, "removing the ground releases its index and retains the zero fallback")
	arena.free()

func _state(count := 250) -> ELAdventureSession:
	var profile := ELProfile.new()
	profile.id = "el1"
	profile.tables.ResourceMine = {"mine": {"Name": "Mine", "Level": 0, "Production": ["Stone(12)", "Root(7)", "Ruby(4)"]}}
	var map := ELAdventureMap.new()
	map.profile = profile
	map.width = 64
	map.height = 64
	var state := ELAdventureSession.new()
	state.map = map
	state.current_player = 1
	state.players = {1: {"color": "Red"}, 2: {"color": "Blue"}}
	state.explored.resize(map.width * map.height)
	state.fog = {"revision": 1, "visible": state.explored.duplicate()}
	for id in count:
		var item := {"uid": id, "type": "object", "group": "terrain", "name": "Rock", "alive": true, "visible": true, "placed": true, "owner": 1 + id % 2, "x": id % 64, "y": (id / 64) % 64, "node": {}}
		match id % 19:
			0: item.merge({"type": "hero", "group": "heroes", "name": "Hero", "fortified": id % 3 == 0}, true)
			1: item.merge({"type": "monster", "group": "monsters", "owner": 0}, true)
			2: item.merge({"type": "resource_mine", "group": "mines", "name": "Mine", "level": 0}, true)
			3: item.merge({"type": "mana_node", "group": "mana_nodes"}, true)
			4: item.merge({"type": "fort", "group": "forts"}, true)
			5: item.merge({"type": "rune_shop", "group": "factories"}, true)
			6: item.merge({"type": "el1_spell_shop", "group": "laboratories"}, true)
			7: item.merge({"type": "object", "group": "buildings", "name": "MainTower"}, true)
		if id % 17 == 0: item.alive = false
		if id % 23 == 0: item.visible = false
		state.objects[id] = item
	return state

func _reference_roster(state: ELAdventureSession, tower_only: bool) -> Array[int]:
	var result: Array[int] = []
	for actor: Dictionary in state.objects.values():
		if actor.type != "hero" or not actor.alive or not actor.visible or actor.owner != state.current_player: continue
		if tower_only and not ELGlobalSpells.held(actor): continue
		result.append(int(actor.uid))
	return result

func _overview() -> void:
	var state := _state()
	var hud := ELAdventureHud.new()
	hud.state = state
	hud.profile = state.map.profile
	for tower_only in [false, true]:
		hud.tower_only = tower_only
		for kind in 5:
			hud.building_kind = kind
			hud._refresh_overview(1)
			check(hud.roster == _reference_roster(state, tower_only) and hud.listing == ELBuildingScreen.owned(state, 1, kind), "one-pass overview preserves roster and category %d (tower filter %s)" % [kind, tower_only])
	check(hud._overview_income == ELResourceSites.income(state, 1) and hud._overview_income.Stone > 0, "one-pass overview preserves actual mine production")
	state.map.profile.tables.ResourceMine.mine.Production = ["Stone(2147483647)"]
	hud._refresh_overview(1)
	check(hud._overview_income == ELResourceSites.income(state, 1) and hud._overview_income.Stone == ELResources.MAX_AMOUNT, "one-pass overview preserves the resource cap across multiple mines")
	var counts_ok := true
	for kind in 5: counts_ok = counts_ok and hud._building_counts[kind] == ELBuildingScreen.owned(state, 1, kind).size()
	check(counts_ok, "all five building button counts match the original helpers")
	var old := hud._marker_state.duplicate()
	hud._refresh_overview(1)
	check(old == hud._marker_state, "unchanged map data leaves the minimap drawing key unchanged")
	state.objects[19].visible = not state.objects[19].visible
	hud._refresh_overview(1)
	check(old != hud._marker_state, "script visibility changes invalidate first-game minimap markers without movement")
	old = hud._marker_state.duplicate()
	state.objects[19].fortified = not state.objects[19].get("fortified", false)
	hud._refresh_overview(1)
	check(old != hud._marker_state, "entering or leaving a fort invalidates first-game minimap markers")
	old = hud._marker_state.duplicate()
	state.objects[19].placed = false
	hud._refresh_overview(1)
	check(old != hud._marker_state, "unplaced objects cannot leave stale minimap markers")
	old = hud._marker_state.duplicate()
	state.players[1].color = "Green"
	hud._refresh_overview(1)
	check(old != hud._marker_state, "player-colour changes invalidate fallback marker colours")
	hud.free()

func _fog_rect(shader_code: String) -> TextureRect:
	var rect := TextureRect.new()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = shader_code
	material.shader = shader
	rect.material = material
	return rect

func _hidden_mist() -> void:
	var state := _state(0)
	var parent := Node3D.new()
	root.add_child(parent)
	var world := ELAdventureScene.new()
	world.set_process(false)
	world.map = state.map
	world.fog_session = state
	world._fog_revision = ELFog.revision(state)
	world.mist = ELFogMist.new()
	world.mist.set_process(false)
	world.add_child(world.mist)
	parent.add_child(world)
	world._process(0.01)
	check(world.mist.render_active, "visible map keeps its mist generator available")
	parent.hide()
	world._process(0.01)
	var previous := world.mist.drift
	world.mist.advance(0.1)
	check(not world.mist.render_active and world.mist.render_target_update_mode == SubViewport.UPDATE_DISABLED and world.mist.drift > previous, "hidden ancestor suppresses mist rendering while preserving the original drift clock")
	parent.show()
	world._process(0.01)
	check(world.mist.render_active and world.mist.render_target_update_mode == SubViewport.UPDATE_ONCE, "reshown map requests its current mist image immediately")
	world.enable_fog(null)
	check(not world.mist.render_active, "detaching fog disables an existing mist viewport")
	parent.free()

func _minimap() -> void:
	var state := _state(40)
	# ELFog.applies needs a valid grid; the masks themselves stay synthetic.
	state.grid = ELAdventureGrid.new()
	state.grid.map = state.map
	var hud := ELAdventureHud.new()
	hud.state = state
	hud.profile = state.map.profile
	hud.minimap_fog = _fog_rect(ELAdventureHud.MINIMAP_FOG)
	hud.minimap_marks = Control.new()
	hud.add_child(hud.minimap_fog)
	hud.add_child(hud.minimap_marks)
	root.add_child(hud)
	hud._sync_minimap_fog()
	check(hud._fog_textures.size() == 2, "first-game minimap prepares both fog masks")
	var known := hud._fog_textures[0]
	var seen := hud._fog_textures[1]
	state.fog.visible[0] = 2
	state.fog.revision += 1
	hud._sync_minimap_fog()
	check(hud._fog_textures[0] == known and hud._fog_textures[1] == seen and hud._fog_masks[1][0] == 2 and hud._fog_masks[0][0] == 0, "sight changes reuse texture objects and retain the unchanged exploration mask")
	state.current_player = 2
	hud._sync_minimap_fog()
	check((hud.minimap_fog.material as ShaderMaterial).get_shader_parameter("bit") == 2, "first-game minimap switches player bit even without a fog revision")
	ELFog.reveal_for_console(state, 2, true)
	hud._sync_minimap_fog()
	check(not hud.minimap_fog.visible, "first-game console reveal hides the fog layer")
	ELFog.reveal_for_console(state, 2, false)
	hud._sync_minimap_fog()
	check(hud.minimap_fog.visible, "first-game fog returns after console reveal ends")
	var second := ELSecondAdventureHud.new()
	second.set_process(false)
	second.state = state
	second.profile = state.map.profile
	second.minimap_fog = _fog_rect(ELSecondAdventureHud.MINIMAP_FOG)
	second.minimap_marks = Control.new()
	second.add_child(second.minimap_fog)
	second.add_child(second.minimap_marks)
	root.add_child(second)
	second._sync_minimap_fog()
	var texture := second._fog_texture
	ELFog.reveal_for_console(state, 1, true)
	second._sync_minimap_fog()
	check(not second.minimap_fog.visible and second._fog_texture == texture, "second-game console reveal hides unchanged fog without a texture replacement")
	ELFog.reveal_for_console(state, 1, false)
	second._sync_minimap_fog()
	check(second.minimap_fog.visible, "second-game minimap restores its original exploration mask")
	second._markers = {19: state.objects[19]}
	second._sync_minimap_marks()
	var marks := second._marks.duplicate()
	state.objects[19].placed = false
	second._sync_minimap_marks()
	check(marks != second._marks, "second-game markers detect placement changes without a growing string key")
	var button := ELAdventureHud.CutButton.new()
	root.add_child(button)
	var draws := [0]
	button.draw.connect(func(): draws[0] += 1)
	await process_frame
	await process_frame
	var before: int = draws[0]
	for i in 3:
		button.active = false
		await process_frame
	check(draws[0] == before, "assigning an unchanged HUD tab state does not request another redraw")
	button.free()
	hud.free()
	second.free()

func _reference_overview(state: ELAdventureSession, selected_kind: int) -> void:
	_reference_roster(state, false)
	ELResourceSites.income(state, 1)
	for kind in 5: ELBuildingScreen.owned(state, 1, kind)
	ELBuildingScreen.owned(state, 1, selected_kind)
	var values := PackedInt64Array([-1, 0, state.day, ELFog.revision(state)])
	for item: Dictionary in state.objects.values():
		var kind: Variant = item.get("type")
		if kind == "hero" or kind == "monster": values.append_array([int(item.x), int(item.y), int(item.alive)])
		elif item.has("owner") and item.has("group"): values.append(int(item.owner))
	hash(values)

func _median(times: Array[float]) -> float:
	times.sort()
	return (times[2] + times[3]) * 0.5

func _benchmark() -> void:
	var figures := _figures(40)
	var index := ELGroundHeightIndex.new()
	var started := Time.get_ticks_usec()
	index.build(figures)
	var preparation := (Time.get_ticks_usec() - started) / 1000.0
	var points := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4204
	for i in 300: points.append(Vector2(rng.randf_range(-21, 21), rng.randf_range(-21, 21)))
	var before: Array[float] = []
	var after: Array[float] = []
	for run in 7:
		for mode in [run % 2, 1 - run % 2]:
			started = Time.get_ticks_usec()
			for point in points:
				if mode == 0: _reference_height(figures, point.x, point.y)
				else: index.height(point.x, point.y)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			if run > 0:
				if mode == 0: before.append(elapsed)
				else: after.append(elapsed)
	print("BENCHMARK_JSON: " + JSON.stringify({"name": "arena_ground_queries", "triangles": index.triangle_count, "queries": points.size(), "runs": 6, "v3_ms": _median(before), "v4_ms": _median(after), "prepare_ms": preparation, "bucket_references": index.bucket_references, "scope": "synthetic CPU queries; index build excluded and reported separately"}))
	var state := _state(3000)
	var hud := ELAdventureHud.new()
	hud.state = state
	hud.profile = state.map.profile
	hud.building_kind = 2
	before.clear()
	after.clear()
	for run in 7:
		for mode in [run % 2, 1 - run % 2]:
			started = Time.get_ticks_usec()
			for i in 30:
				if mode == 0: _reference_overview(state, 2)
				else: hud._refresh_overview(1)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			if run > 0:
				if mode == 0: before.append(elapsed)
				else: after.append(elapsed)
	print("BENCHMARK_JSON: " + JSON.stringify({"name": "first_game_hud_overview", "objects": state.objects.size(), "refreshes": 30, "runs": 6, "v3_ms": _median(before), "v4_ms": _median(after), "scope": "synthetic CPU lists, income and marker keys; all current state read each refresh"}))
	hud.free()

func _render_minimap() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "render probes require a windowed renderer")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 240)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.28, 0.43, 0.24)
	background.size = Vector2(240, 240)
	viewport.add_child(background)
	var state := _state(0)
	state.grid = ELAdventureGrid.new()
	state.grid.map = state.map
	var hud := ELSecondAdventureHud.new()
	hud.set_process(false)
	hud.state = state
	hud.profile = state.map.profile
	hud.minimap_fog = _fog_rect(ELSecondAdventureHud.MINIMAP_FOG)
	hud.minimap_fog.size = Vector2(240, 240)
	hud.minimap_fog.stretch_mode = TextureRect.STRETCH_SCALE
	(hud.minimap_fog.material as ShaderMaterial).set_shader_parameter("bit", 1)
	hud.add_child(hud.minimap_fog)
	viewport.add_child(hud)
	hud._sync_minimap_fog()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var hidden := viewport.get_texture().get_image()
	ELFog.reveal_for_console(state, 1, true)
	hud._sync_minimap_fog()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var revealed := viewport.get_texture().get_image()
	check(hidden.get_pixel(120, 120).get_luminance() < 0.01 and revealed.get_pixel(120, 120).g > 0.3, "actual second-game fog shader clears on console reveal with unchanged explored bytes")
	ELFog.reveal_for_console(state, 1, false)
	hud._sync_minimap_fog()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(120, 120).get_luminance() < 0.01, "actual second-game fog shader returns after reveal ends")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var folder := arg.trim_prefix("--shots=")
			hidden.save_png(folder.path_join("world_minimap_fog.png"))
			revealed.save_png(folder.path_join("world_minimap_revealed.png"))
	viewport.free()
