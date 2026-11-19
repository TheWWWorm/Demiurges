extends SceneTree
## Generated road mesh and fog regression checks. Requires no game assets.
## godot --headless --path game --script ../tools/first_random_map_roads_check.gd

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	var map := ELAdventureMap.new()
	map.id = ELFirstRandomMap.id_for_config({"seed": "roads-check"})
	map.width = 8
	map.height = 8
	map.roads.resize(64)
	for point: Vector2i in [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4)]: map.roads[point.y * 8 + point.x] = 5
	var roads := ELFirstRandomMapRoads.new()
	root.add_child(roads)
	check(roads.build(map), "generated road mesh builds")
	check(roads.road_cells == 4 and roads.vertex_count > 0 and roads.vertex_count < 1024, "connected dirt ribbons stay in a single small mesh")
	check(roads.surface != null and not roads.surface.visible, "no roads become visible before fog is applied")
	if roads.surface != null:
		var arrays: Array = roads.surface.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(vertices.size() == roads.vertex_count and arrays[Mesh.ARRAY_TEX_UV].size() == vertices.size(), "mesh vertices and visibility coordinates are complete")
		check(Array(vertices).all(func(point: Vector3): return is_equal_approx(point.y, ELFirstRandomMapRoads.HEIGHT)), "road surface is lifted above ground to prevent depth fighting")
		check(roads.surface.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "flat road decals do not cast shadows")
		var fog := PackedByteArray()
		fog.resize(64)
		fog.fill(ELAdventureScene.FOG_UNEXPLORED)
		roads.set_fog(fog)
		# Inspect the exact CPU mask uploaded by set_fog. Godot's headless
		# dummy backend returns the initial texture image even after update().
		check(roads.visibility_image.get_pixel(3, 3).a == 0.0, "unexplored roads are transparent in the uploaded mask")
		fog.fill(0)
		roads.set_fog(fog)
		check(roads.visibility_image.get_pixel(3, 3).is_equal_approx(Color.WHITE), "visible-road mask retains normal earth colour")
		fog.fill(ELAdventureScene.FOG_REMEMBERED)
		roads.set_fog(fog)
		var remembered := roads.visibility_image.get_pixel(3, 3)
		check(remembered.a == 1.0 and absf(remembered.r - 0.3) < 0.005, "remembered roads dim with the explored terrain")
		fog.fill(0)
		fog[3 * 8 + 3] = ELAdventureScene.FOG_UNEXPLORED
		roads.set_fog(fog)
		check(roads.visibility_image.get_pixel(3, 3).a == 0.0 and roads.visibility_image.get_pixel(4, 4).a == 0.0, "unknown neighbours conservatively mask shared corners")
		roads.set_fog(PackedByteArray([1, 2, 3]))
		check(not roads.surface.visible, "bad fog dimensions hide the road surface")
		roads.set_fog(PackedByteArray())
		check(roads.surface.visible and roads.visibility_image.get_pixel(0, 0).is_equal_approx(Color.WHITE), "disabling fog restores the full road visibility mask")
		check(roads.surface.material_override.albedo_texture == roads.visibility_texture, "the road material uses the maintained visibility texture")
	var current := ELFirstRandomMap.normalize({"seed": "roads-check"})
	map.set_meta("random_map", {"config": current})
	map.roads[3 * 8 + 2] = 6
	map.roads[3 * 8 + 3] = 6
	check(roads.build(map) and roads.road_cells == 4 and roads.vertex_count < 1024, "main roads and curved side paths share one mesh")
	if roads.surface != null:
		var shades: PackedColorArray = roads.surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(Array(shades).any(func(shade: Color) -> bool: return absf(shade.a - 0.78) < 0.01), "main roads have a distinct dirt surface")
		check(Array(shades).any(func(shade: Color) -> bool: return absf(shade.a - 0.58) < 0.01), "side paths keep the underlying ground visible")
	map.roads[4 * 8 + 3] = 5
	var junction := ELFirstRandomMapRoads._trail_network(map)
	var adjacent_count := 0
	for neighbors: Array in junction.values(): adjacent_count += neighbors.size()
	check(junction.size() == 5 and adjacent_count == 8, "a tight road loop becomes a single connected junction")
	map.relief.resize(81)
	map.relief[3 * 9 + 3] = 64
	map.relief[4 * 9 + 4] = 48
	check(roads.build(map), "roads build over steep and irregular ground")
	if roads.surface != null:
		var projected: PackedVector3Array = roads.surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var follows := true
		for index in range(0, projected.size(), 3):
			var at := (projected[index] + projected[index + 1] + projected[index + 2]) / 3.0
			follows = follows and absf(at.y - ELFirstRandomMapRoads.HEIGHT - map.surface_height(Vector2(at.x, -at.z) / ELAdventureTerrain.CELL)) < 0.003
		check(follows, "every road triangle follows the actual mesh surface between vertices")
	var ground := ELAdventureScene.new()
	ground.map = map
	var summit := ground.ground_position(2.5, 2.5)
	var hit: Variant = ground.ground_intersection(summit + Vector3(4.0, 20.0, -2.0), Vector3(-4, -20, 2).normalized())
	check(hit is Vector3 and (hit as Vector3).distance_to(summit) < 0.01, "an oblique pointer projects onto raised ground")
	ground.free()
	map.roads.fill(0)
	check(roads.build(map) and roads.road_cells == 0 and roads.surface == null, "roads-off maps allocate no render mesh")
	map.id = "mission11"
	check(not roads.build(map), "authored maps do not acquire generated road overlays")
	roads.free()
	print("FIRST RANDOM MAP ROADS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
