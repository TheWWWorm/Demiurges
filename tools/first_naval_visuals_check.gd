extends SceneTree
## Asset-free geometry, source selection, and harbor visibility checks.
## Rendering an actual frame is a separate visual test; these inspect the
## real meshes, materials, scene dispatch, and fog state without a GPU.
## godot --headless --path game --script ../tools/first_naval_visuals_check.gd

const Fixture = preload("first_naval_fixture.gd")
var failures: Array[String] = []
var checks := 0
var completed := 0

class RecordingModel extends ELModel:
	var source_used: ELProfile
	var model_used := ""
	func build(data: ELProfile, model: String, _texture: String, _secondary := "", _wave := "") -> bool:
		source_used = data
		model_used = model
		return true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: return
	failures.append(message)
	printerr("FAIL: " + message)

func _run() -> void:
	await process_frame
	_boats()
	_sources()
	_harbors()
	check(completed == 3, "all visual structure sections completed")
	print("FIRST NAVAL VISUALS: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boats() -> void:
	var profile := Fixture.Content.profile()
	var colors := {}
	for owner in range(1, 5):
		var boat := ELModel.new()
		check(ELFirstNavalVisuals.build_boat(boat, profile, owner), "fallback boat builds without either game's models")
		check(boat.parts.size() >= 7 and boat.profile == profile, "boat has a hull, deck, mast, sail, and details on its own profile")
		var geometry := true
		var bounds := AABB()
		var first := true
		for part: MeshInstance3D in boat.parts.values():
			geometry = geometry and part.mesh != null and part.mesh.get_surface_count() > 0 and part.material_override is StandardMaterial3D
			if part.mesh == null: continue
			for surface in part.mesh.get_surface_count():
				var arrays: Array = part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				geometry = geometry and not vertices.is_empty()
				for vertex: Vector3 in vertices: geometry = geometry and vertex.is_finite()
			var box := part.transform * part.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		check(geometry, "boat has finite drawable geometry and bound materials")
		check(bounds.size.x > 0.8 and bounds.size.x < 2.0 and bounds.size.y > 1.4 and bounds.size.y < 2.5 and bounds.size.z > 1.5 and bounds.size.z < 2.1, "boat proportions fit a single adventure cell")
		colors[boat.parts.pennant.material_override.albedo_color.to_html()] = true
		boat.free()
	check(colors.size() == 4, "four commanders receive distinct pennants")
	completed += 1

func _sources() -> void:
	var map := Fixture.world()
	var second := ELProfile.new()
	second.id = "el2"
	check(ELFirstNavalVisuals.ship_source(null) == null and ELFirstNavalVisuals.ship_source(map.profile) == null, "missing or first-game content never masquerades as an original second-game ship source")
	var scene := ELAdventureScene.new()
	scene.map = map
	scene._ship_profile = second
	var model := RecordingModel.new()
	var definition := {"first_ship": true, "ship_owner": 2, "model": "he551", "texture": "Heroes/Boat00", "secondary": ""}
	check(scene._build_model(model, definition) and model.source_used == second and model.model_used == "he551", "an explicitly supplied ship source is used for a first-game sailing hero")
	check(scene._build_model(model, {"model": "ordinary_hero", "texture": "fixture", "secondary": ""}) and model.source_used == map.profile, "ordinary first-game figures continue using first-game content")
	model.free()
	scene._ship_profile = null
	var fallback := ELModel.new()
	check(scene._build_model(fallback, definition) and fallback.parts.has("hull") and fallback.profile == map.profile, "the same scene path constructs a visible fallback boat without EL2")
	fallback.free()
	scene.free()
	completed += 1

func _harbors() -> void:
	var map := Fixture.world()
	var visuals := ELFirstNavalVisuals.new()
	root.add_child(visuals)
	visuals.build(map)
	check(visuals.harbors.size() == 2 and visuals.get_child_count() == 2, "every logical harbor receives one render model")
	check(visuals.harbors.all(func(port: Dictionary) -> bool: return not port.model.visible and port.model.parts.size() >= 7), "harbors start hidden until fog is supplied")
	var fog := PackedByteArray()
	fog.resize(map.width * map.height)
	fog.fill(255)
	visuals.set_fog(fog)
	check(visuals.harbors.all(func(port: Dictionary) -> bool: return not port.model.visible), "unexplored harbors stay hidden")
	var first: Dictionary = visuals.harbors[0]
	fog[first.land.y * map.width + first.land.x] = 0
	visuals.set_fog(fog)
	check(not first.model.visible, "a visible land endpoint does not reveal an unexplored sea endpoint")
	fog[first.water.y * map.width + first.water.x] = 133
	visuals.set_fog(fog)
	var pier: MeshInstance3D = first.model.parts.pier
	var base: Color = pier.get_meta("base_color")
	check(first.model.visible and pier.material_override.albedo_color.is_equal_approx(base * Color(0.3, 0.3, 0.3, 1.0)), "remembered harbor geometry uses the normal fog dimming")
	fog.fill(0)
	visuals.set_fog(fog)
	check(visuals.harbors.all(func(port: Dictionary) -> bool: return port.model.visible) and pier.material_override.albedo_color.is_equal_approx(base), "visible harbors return to their full original color")
	visuals.set_fog(PackedByteArray([0, 0]))
	check(visuals.harbors.all(func(port: Dictionary) -> bool: return not port.model.visible), "invalid fog dimensions fail closed")
	visuals.set_fog(PackedByteArray())
	check(visuals.harbors.all(func(port: Dictionary) -> bool: return port.model.visible), "turning fog off shows all harbors")
	visuals.build(Fixture.world(false))
	check(visuals.harbors.is_empty() and visuals.get_child_count() == 0, "ordinary maps allocate no harbor overlay")
	visuals.free()
	completed += 1
