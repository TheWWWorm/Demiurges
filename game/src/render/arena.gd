class_name ELArena
extends Node3D

var objects_loaded := 0
var errors: Array[String] = []
var definition: Dictionary
var moving_layers: Array[StandardMaterial3D] = []
var layer_speeds: Array[float] = []
var light: DirectionalLight3D

static func title(id: String) -> String:
	var names := {"Green": "Vital forest", "Red": "Chaot desert", "Black": "Synthet wasteland", "Blue": "Kinet mountains",
		"Fort": "Fortress", "Ether": "Ether plane", "Dungeon": "Dungeon", "White": "White Lord's arena",
		"Ship": "Ship", "ChaotsCity": "Chaot city", "VitalsCity": "Vital city", "SynthetsCity": "Synthet city"}
	var key := id.get_slice(".", 0)
	return String(names.get(key, key)) + (" · " + str(int(id.get_slice(".", 1))) if key in ["Green", "Red", "Black", "Blue"] else "")

func build(profile: ELProfile, arena_id := "Green.001") -> bool:
	definition = profile.table("CombatSceneDB").get(arena_id, {})
	if definition.is_empty():
		errors.append("Missing arena " + arena_id)
		return false
	_add_model(profile, "cosu%d" % int(definition.SurfaceFigure), "CombatScenes/" + definition.SurfaceTexture)
	var ids: Array = definition.Objects
	var textures: Array = definition.Textures
	var transforms: Array = definition.PosRot
	for i in ids.size():
		var model := _add_model(profile, "coob%d" % int(ids[i]), "CombatScenes/" + textures[i])
		if model == null:
			continue
		var at := i * 7
		model.position = ELFigure.vector(Vector3(transforms[at], transforms[at + 1], transforms[at + 2]))
		model.quaternion = Quaternion(transforms[at + 4], transforms[at + 6], -transforms[at + 5], transforms[at + 3]).normalized()
	_build_background(profile)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("222927")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var ambient: Array = definition.AmbColor
	env.ambient_light_color = Color(ambient[0] / 255.0, ambient[1] / 255.0, ambient[2] / 255.0)
	env.ambient_light_energy = 0.38
	environment.environment = env
	add_child(environment)
	light = DirectionalLight3D.new()
	var sun: Array = definition.SunColor
	light.light_color = Color(sun[0] / 255.0, sun[1] / 255.0, sun[2] / 255.0)
	light.light_energy = 0.85
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 65.0
	var direction: Array = definition.SunDirection
	add_child(light)
	light.position = ELFigure.vector(Vector3(direction[0], direction[1], direction[2]))
	light.look_at(Vector3.ZERO)
	return errors.is_empty()

func ground_height(x: float, z: float) -> float:
	var surface: ELModel = get_child(0)
	var point := Vector2(x, z)
	for figure: Dictionary in surface.figures.values():
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
			if absf(determinant) < 0.00001:
				continue
			var u := (point - va).cross(vc - va) / determinant
			var v := (vb - va).cross(point - va) / determinant
			if u >= -0.001 and v >= -0.001 and u + v <= 1.001:
				return a.y + (b.y - a.y) * u + (c.y - a.y) * v
	return 0.0

func _build_background(profile: ELProfile) -> void:
	# The original engine wraps four atlas panels around a twelve-segment ring.
	var corners := [
		[Vector2(8, 348), Vector2(678, 348), Vector2(678, 679), Vector2(8, 679)],
		[Vector2(8, 8), Vector2(678, 8), Vector2(678, 339), Vector2(8, 339)],
		[Vector2(686, 8), Vector2(686, 678), Vector2(1017, 678), Vector2(1017, 8)],
		[Vector2(8, 689), Vector2(678, 689), Vector2(678, 1020), Vector2(8, 1020)]]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(32)
	uvs.resize(32)
	for panel in 4:
		var section := 3 - panel
		var quad: Array = corners[panel]
		for j in 4:
			var angle := (section * 3 + j) * PI / 6.0
			var x := cos(angle) * 28.5
			var z := -sin(angle) * 28.5
			var index := section * 4 + j
			vertices[index] = Vector3(x, ground_height(x, z), z)
			vertices[index + 16] = vertices[index] + Vector3(0, 20, 0)
			var f := j / 3.0
			uvs[index] = Vector2(lerpf(quad[2].x, quad[3].x, f) / 1024.0, 1 - lerpf(quad[3].y, quad[2].y, f) / 1024.0)
			uvs[index + 16] = Vector2(lerpf(quad[1].x, quad[0].x, f) / 1024.0, 1 - lerpf(quad[0].y, quad[1].y, f) / 1024.0)
			if j < 3:
				indices.append_array([index, index + 1, index + 17, index, index + 17, index + 16])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var backdrop := MeshInstance3D.new()
	backdrop.mesh = mesh
	backdrop.material_override = ELFigure.material(profile.texture("CombatScenes/" + definition.Background), true)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)
	# Original backdrop draw order: atlas, two independently scrolling halves
	# of BackGroundLayer (the cloud layer), then BackGroundOverlay, which uses
	# the backdrop's atlas UVs. All use this same ring. From the ring's foot to
	# its top, the first half spans image rows 0.5-1, the second rows 0-0.5.
	var clouds_name := String(definition.get("BackGroundLayer", ""))
	if not clouds_name.is_empty():
		var clouds := profile.texture("CombatScenes/" + clouds_name)
		if clouds != null:
			for layer in 2:
				var moving_uvs := uvs.duplicate()
				for section in 4:
					for j in 4:
						var at := section * 4 + j
						moving_uvs[at] = Vector2(j / 3.0, 0.5 - layer * 0.5)
						moving_uvs[at + 16] = Vector2(j / 3.0, 1.0 - layer * 0.5)
				var layer_arrays := arrays.duplicate()
				layer_arrays[Mesh.ARRAY_TEX_UV] = moving_uvs
				var material := _background_layer(layer_arrays, clouds, layer + 1)
				moving_layers.append(material)
				layer_speeds.append(float(definition.get("RotSpeed%d" % (layer + 1), 0.0)) * 2.0 / PI)
	var front_name := String(definition.get("BackGroundOverlay", ""))
	if not front_name.is_empty():
		var front := profile.texture("CombatScenes/" + front_name)
		if front != null: _background_layer(arrays, front, 3)

func _background_layer(arrays: Array, texture: Texture2D, order: int) -> StandardMaterial3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ELFigure.material(texture, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = order
	node.material_override = material
	add_child(node)
	return material

func _process(delta: float) -> void:
	for i in moving_layers.size():
		var material := moving_layers[i]
		material.uv1_offset.x = fposmod(material.uv1_offset.x + delta * layer_speeds[i], 1.0)

func clear_camera_view(camera_position: Vector3, target: Vector3) -> void:
	# Presentation-only occlusion: retain the original objects, but hide foliage
	# between the camera and the central play area. This follows camera movement.
	for child in get_children():
		if child is not ELModel or child.template.begins_with("cosu"):
			continue
		var obscures := false
		for part: MeshInstance3D in child.parts.values():
			if part.mesh == null:
				continue
			var box: AABB = part.global_transform * part.mesh.get_aabb()
			if box.size.y > 2.0 and box.intersects_segment(camera_position, target + Vector3(0, 1.5, 0)) != null:
				obscures = true
		child.visible = not obscures

func _add_model(profile: ELProfile, model_name: String, texture_name: String) -> ELModel:
	var model := ELModel.new()
	add_child(model)
	if not model.build(profile, model_name, texture_name):
		errors.append(model.error)
		model.queue_free()
		return null
	# The old scenery uses large crossed cards with lighting painted into the
	# texture. Projecting their geometry casts solid wedges across the arena.
	# Keep dynamic shadows on combatants; scenery retains its original shading.
	for part: MeshInstance3D in model.parts.values():
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objects_loaded += 1
	return model
