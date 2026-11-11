class_name ELArena
extends Node3D

var objects_loaded := 0
var errors: Array[String] = []
var scene_id := ""
var definition: Dictionary
var moving_layers: Array[StandardMaterial3D] = []
var layer_speeds: Array[float] = []
var light: DirectionalLight3D
## The scene's ambient light (combat effects dim it with the sun).
var environment_settings: Environment
var _profile: ELProfile
var _ground: ELModel
var _sea: MeshInstance3D
var _ship_surface: MeshInstance3D
var _ship_original_mesh: Mesh
var _ship_deck_mesh: ArrayMesh
var _ground_materials: Dictionary = {}
var _detail_materials: Dictionary = {}
var _secondary_overlays: Dictionary = {}
var _secondary_sources := PackedFloat32Array()
var _secondary_traced := false
var _secondary_scenery: Array[ELModel] = []
var _camera_obstacles: Array[ELModel] = []
var _scenery: Dictionary = {}
## Scenery standing in the ring (not the backdrop), and its triangles in
## arena space once asked for: [{"box": Rect2 (x, z), "triangles": PackedVector3Array}].
var _solid_models: Array[ELModel] = []
var _solids: Array = []
## Scenery materials whose ambient plus sun light is limited to full brightness.
var _lit_materials: Array[ShaderMaterial] = []
var _ambient_seen := Color(-1, -1, -1)
## Upper bound of ambient plus sun on scenery (1 = the originals' full brightness).
var light_limit := 1.0
const LIT_SHADER := preload("res://src/render/arena_lit.gdshader")
const LIT_BLEND_SHADER := preload("res://src/render/arena_lit_blend.gdshader")
const SECONDARY_SHADER := preload("res://src/render/arena_secondary.gdshader")
const BACKDROP_SHADER :=preload("res://src/render/arena_backdrop.gdshader")
const SEA_SHADER := preload("res://src/render/arena_sea.gdshader")
## The original cutout pass accepts alpha bytes greater than 200.
const MASKED_ALPHA_CUTOFF := 201.0 / 255.0
var _lit: Dictionary = {}
var _unlit: Dictionary = {}

static func title(id: String) -> String:
	var names := {"Green": "Vital forest", "Red": "Chaot desert", "Black": "Synthet wasteland", "Blue": "Kinet mountains",
		"Fort": "Fortress", "Ether": "Ether plane", "Dungeon": "Dungeon", "White": "White Lord's arena",
		"Ship": "Ship", "ChaotsCity": "Chaot city", "VitalsCity": "Vital city", "SynthetsCity": "Synthet city"}
	var key := id.get_slice(".", 0)
	return String(names.get(key, key)) + (" · " + str(int(id.get_slice(".", 1))) if key in ["Green", "Red", "Black", "Blue"] else "")

func build(profile: ELProfile, arena_id := "Green.001") -> bool:
	_profile = profile
	scene_id = arena_id
	definition = profile.table("CombatSceneDB").get(arena_id, {})
	if definition.is_empty():
		errors.append("Missing arena " + arena_id)
		return false
	_ground = _add_model(profile, "cosu%d" % int(definition.SurfaceFigure), "CombatScenes/" + definition.SurfaceTexture)
	var ids: Array = definition.Objects
	var textures: Array = definition.Textures
	var transforms: Array = definition.PosRot
	var types: Array = definition.get("ObjectTypes", [])
	for i in ids.size():
		# Pieces painted on the backdrop's own sheet extend the backdrop (its
		# mist and distant valleys, reaching beyond the ring): drawn unlit and
		# behind everything else, like the backdrop itself.
		var model := _add_model(profile, "coob%d" % int(ids[i]), "CombatScenes/" + textures[i], ELArchive.key(str(textures[i])) == ELArchive.key(str(definition.get("Background", ""))))
		if model == null:
			continue
		var at := i * 7
		model.position = ELFigure.vector(Vector3(transforms[at], transforms[at + 1], transforms[at + 2]))
		# PosRot stores an axis and angle in radians after each position.
		var axis := ELFigure.vector(Vector3(transforms[at + 3], transforms[at + 4], transforms[at + 5]))
		if not axis.is_zero_approx(): model.quaternion = Quaternion(axis.normalized(), transforms[at + 6])
		var id := int(ids[i])
		if not _scenery.has(id): _scenery[id] = model
		if ELArchive.key(str(textures[i])) != ELArchive.key(str(definition.get("Background", ""))): _solid_models.append(model)
		# Only authored tall scenery can clear the camera's viewing corridor.
		# Low pieces include whole hills supporting separately placed trees;
		# their wide bounds can cross the view without blocking the action.
		if i < types.size():
			if types[i] == "H": _camera_obstacles.append(model)
			if types[i] == "S": _secondary_scenery.append(model)
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
	environment_settings = env
	add_child(environment)
	light = DirectionalLight3D.new()
	var sun: Array = definition.SunColor
	light.light_color = Color(sun[0] / 255.0, sun[1] / 255.0, sun[2] / 255.0)
	light.light_energy = 0.85
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 65.0
	# The sun shines down along the SunDirection line, whichever way the vector
	# points: the original throws figure shadows along it, away from the sun
	# (a wasteland arena points it along -Z, the forest arena along +Z).
	var direction: Array = definition.SunDirection
	add_child(light)
	var toward := ELFigure.vector(Vector3(direction[0], direction[1], direction[2])).normalized()
	if toward.y > 0.0: toward = -toward
	light.look_at_from_position(-toward * 10.0, Vector3.ZERO, Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD)
	if arena_id == "Ship.001": _build_sea(-toward)
	_sync_light()
	return errors.is_empty()

## Ship's flat surface combines the deck with the sea. Most of the sea uses
## a planar atlas mapping, while the planks have bespoke UVs.
func _build_sea(sun_direction: Vector3) -> void:
	if _ground == null: return
	var part := _ground.parts.get("surface") as MeshInstance3D
	if part == null or part.mesh == null: return
	var texture := part.get_meta("albedo", null) as Texture2D
	if texture == null: return
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var deck := PackedInt32Array()
	var water := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var sea_triangle := true
		var centre_z := 0.0
		for j in range(i, i + 3):
			var vertex := vertices[indices[j]]
			centre_z += vertex.z / 3.0
			var projected := Vector2(0.500163, 0.5) - Vector2(vertex.z, vertex.x) * 0.0171833
			sea_triangle = sea_triangle and projected.distance_squared_to(uvs[indices[j]]) <= 0.0001 * 0.0001
		# The strip either side of the hull uses different UVs. The sea shader
		# keeps its wood texels under the rails and replaces the open water.
		if sea_triangle or absf(centre_z - 0.0095) > 10.0: water.append_array(indices.slice(i, i + 3))
		else: deck.append_array(indices.slice(i, i + 3))
	if deck.is_empty() or water.is_empty(): return
	_ship_surface = part
	_ship_original_mesh = part.mesh
	_ship_deck_mesh = ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = deck
	_ship_deck_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sea_mesh := ArrayMesh.new()
	arrays[Mesh.ARRAY_INDEX] = water
	sea_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_sea = MeshInstance3D.new()
	_sea.mesh = sea_mesh
	_sea.transform = part.transform
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SEA_SHADER
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter("ship_atlas", texture)
	_sea.material_override = material
	_ground.add_child(_sea)
	set_water(false)

func set_water(enabled: bool) -> void:
	if _sea == null: return
	_ship_surface.mesh = _ship_deck_mesh if enabled else _ship_original_mesh
	_sea.visible = enabled

func is_surface(model: ELModel) -> bool:
	return model == _ground

func is_normal_secondary_receiver(model: ELModel, part: MeshInstance3D) -> bool:
	var material := part.material_override as ShaderMaterial
	return model in _secondary_scenery and material != null and material.shader == LIT_SHADER

func set_secondary_lights(sources: PackedFloat32Array) -> void:
	if _secondary_sources == sources: return
	_secondary_sources = sources
	_update_secondary_overlays()

func set_secondary_traced(traced: bool) -> void:
	if _secondary_traced == traced: return
	_secondary_traced = traced
	_update_secondary_overlays()

func _update_secondary_overlays() -> void:
	if _secondary_traced or _secondary_sources.is_empty():
		for part: MeshInstance3D in _secondary_overlays:
			if is_instance_valid(part) and part.material_overlay == _secondary_overlays[part]:
				part.material_overlay = null
		return
	var sources := PackedVector4Array()
	# The shader accepts two vectors for each combat light slot.
	sources.resize(ELCombatEffects.LIGHT_POOL * 2)
	for i in _secondary_sources.size() / 4:
		var at := 4 * i
		sources[i] = Vector4(_secondary_sources[at], _secondary_sources[at + 1],
			_secondary_sources[at + 2], _secondary_sources[at + 3])
	if is_instance_valid(_ground):
		_update_secondary_model(_ground, sources)
	for model: ELModel in _secondary_scenery:
		if is_instance_valid(model):
			_update_secondary_model(model, sources)

func _update_secondary_model(model: ELModel, sources: PackedVector4Array) -> void:
	for part: MeshInstance3D in model.parts.values():
		var base := part.material_override as ShaderMaterial
		if base == null or not part.has_meta("albedo"): continue
		var detail: bool = base == _detail_materials.get(part)
		var normal_aware := model != _ground
		if normal_aware:
			if not is_normal_secondary_receiver(model, part): continue
		elif not detail and base.shader != LIT_SHADER: continue
		var overlay: ShaderMaterial = _secondary_overlays.get(part)
		if part.material_overlay != null and part.material_overlay != overlay: continue
		if overlay == null:
			overlay = ShaderMaterial.new()
			overlay.shader = SECONDARY_SHADER
			overlay.render_priority = Material.RENDER_PRIORITY_MIN
			overlay.set_shader_parameter("base_texture", part.get_meta("albedo"))
			_secondary_overlays[part] = overlay
		var tint: Color = Color.WHITE if detail else base.get_shader_parameter("albedo_tint")
		overlay.set_shader_parameter("base_alpha", tint.a)
		overlay.set_shader_parameter("alpha_cutoff", 0.5 if detail else base.get_shader_parameter("alpha_cutoff"))
		overlay.set_shader_parameter("two_sided", detail)
		overlay.set_shader_parameter("normal_aware", normal_aware)
		overlay.set_shader_parameter("sources", sources)
		overlay.set_shader_parameter("source_count", _secondary_sources.size() / 8)
		if part.material_overlay != overlay: part.material_overlay = overlay

func scenery(id: int) -> ELModel:
	return _scenery.get(id)

## Keeps the scenery's light limit in step with the ambient light, which
## combat effects dim and restore.
func _sync_light() -> void:
	if environment_settings == null: return
	var ambient := environment_settings.ambient_light_color * environment_settings.ambient_light_energy
	# Only the Compatibility renderer adds a shadowed sun in a display-encoded pass.
	var encoded := light != null and light.visible and light.shadow_enabled 		and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	ambient.a = light_limit + (1000.0 if encoded else 0.0)
	if ambient == _ambient_seen: return
	_ambient_seen = ambient
	# The colour is given in display encoding; shaders light in linear terms.
	var linear := environment_settings.ambient_light_color.srgb_to_linear() * environment_settings.ambient_light_energy
	var level := Vector3(linear.r, linear.g, linear.b)
	for material: ShaderMaterial in _lit_materials:
		material.set_shader_parameter("ambient_light", level)
		material.set_shader_parameter("light_limit", light_limit)
		material.set_shader_parameter("encoded_sun_pass", encoded)

## Optional close-up ground grain using the arena's authored detail texture
## and world-space tile size. Missing detail art keeps the original material.
## Materials are created on demand; Off restores the exact original material.
func set_detail(enabled: bool) -> void:
	if _ground == null: return
	if enabled and _detail_materials.is_empty():
		var name := str(definition.get("DetailTextureName", ""))
		if name.is_empty(): return
		var texture := _profile.texture("CombatScenes/" + name)
		if texture == null: return
		# These original maps are dark grain, not neutral-grey detail maps.
		# Centre their signal so the option preserves the arena's brightness.
		var average := texture.get_image()
		average.clear_mipmaps()
		average.resize(1, 1, Image.INTERPOLATE_LANCZOS)
		var neutral := average.get_pixel(0, 0)
		for part: MeshInstance3D in _ground.parts.values():
			var base := part.material_override
			if part.mesh == null or base == null or not part.has_meta("albedo"): continue
			_ground_materials[part] = base
			var detail := ShaderMaterial.new()
			detail.shader = load("res://src/render/arena_ground.gdshader")
			detail.set_shader_parameter("base_texture", part.get_meta("albedo"))
			_lit_materials.append(detail)
			_ambient_seen = Color(-1, -1, -1)
			detail.set_shader_parameter("detail_texture", texture)
			detail.set_shader_parameter("detail_neutral", (neutral.r + neutral.g + neutral.b) / 3.0)
			detail.set_shader_parameter("detail_tile_size", maxf(0.01, float(definition.get("DetailTextureTileSize", 2.0))))
			_detail_materials[part] = detail
	for part: MeshInstance3D in _ground_materials:
		part.material_override = _detail_materials[part] if enabled else _ground_materials[part]
	_update_secondary_overlays()

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

## Whether a figure `radius` wide stands clear at `spot` (x, z): no scenery
## (rocks, walls, trees, bushes) rises between its knees and its head inside
## that circle, and the ground there is not a slope or a cliff.
func clear_spot(spot: Vector2, radius: float, height := 3.0) -> bool:
	var floor_height := ground_height(spot.x, spot.y)
	for angle in 8:
		var around := spot + Vector2.from_angle(angle * TAU / 8.0) * radius
		if absf(ground_height(around.x, around.y) - floor_height) > 0.6: return false
	var low := floor_height + 0.35
	var high := floor_height + height
	var reach := Rect2(spot - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	for solid: Dictionary in _solid_list():
		if not (solid.box as Rect2).intersects(reach): continue
		var triangles: PackedVector3Array = solid.triangles
		for i in range(0, triangles.size(), 3):
			var a := triangles[i]
			var b := triangles[i + 1]
			var c := triangles[i + 2]
			if minf(a.x, minf(b.x, c.x)) > reach.end.x or maxf(a.x, maxf(b.x, c.x)) < reach.position.x: continue
			if minf(a.z, minf(b.z, c.z)) > reach.end.y or maxf(a.z, maxf(b.z, c.z)) < reach.position.y: continue
			if minf(a.y, minf(b.y, c.y)) > high or maxf(a.y, maxf(b.y, c.y)) < low: continue
			# The surface over the spot itself.
			var va := Vector2(a.x, a.z)
			var determinant := (Vector2(b.x, b.z) - va).cross(Vector2(c.x, c.z) - va)
			if absf(determinant) > 0.00001:
				var u := (spot - va).cross(Vector2(c.x, c.z) - va) / determinant
				var v := (Vector2(b.x, b.z) - va).cross(spot - va) / determinant
				if u >= 0.0 and v >= 0.0 and u + v <= 1.0:
					var over := a.y + (b.y - a.y) * u + (c.y - a.y) * v
					if over > low and over < high: return false
			# Its edges crossing the circle (upright cards and walls).
			for edge: Array in [[a, b], [b, c], [c, a]]:
				var from: Vector3 = edge[0]
				var to: Vector3 = edge[1]
				var flat := Vector2(to.x - from.x, to.z - from.z)
				var along := 0.0 if flat.length_squared() < 0.000001 else clampf((spot - Vector2(from.x, from.z)).dot(flat) / flat.length_squared(), 0.0, 1.0)
				var closest := from.lerp(to, along)
				if Vector2(closest.x, closest.z).distance_to(spot) > radius: continue
				# The edge's highest and lowest point within the circle are
				# near its closest point; its ends cover upright edges.
				var top := maxf(closest.y, maxf(from.y, to.y) if flat.length() < radius * 2.0 else closest.y)
				var bottom := minf(closest.y, minf(from.y, to.y) if flat.length() < radius * 2.0 else closest.y)
				if top > low and bottom < high: return false
	return true

func _solid_list() -> Array:
	if not _solids.is_empty() or _solid_models.is_empty(): return _solids
	for model: ELModel in _solid_models:
		if not is_instance_valid(model): continue
		var triangles := PackedVector3Array()
		var low := Vector2.INF
		var high := -Vector2.INF
		for part: MeshInstance3D in model.parts.values():
			if part.mesh == null: continue
			var place := model.transform * part.transform
			for surface in part.mesh.get_surface_count():
				var arrays := part.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
				for index in indices:
					var point := place * vertices[index]
					triangles.append(point)
					low = low.min(Vector2(point.x, point.z))
					high = high.max(Vector2(point.x, point.z))
		if not triangles.is_empty(): _solids.append({"box": Rect2(low, high - low), "triangles": triangles})
	return _solids

func _backdrop_foot(point: Vector3) -> Vector3:
	if _ground == null: return point
	var nearest := Vector3.ZERO
	var distance := INF
	for figure: Dictionary in _ground.figures.values():
		var vertices: PackedVector3Array = figure.arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var distance_squared := point.distance_squared_to(vertex)
			if distance_squared < distance:
				distance = distance_squared
				nearest = vertex
	# The backdrop shares the ground's outline, with a small overlap at its foot.
	return nearest - Vector3(signf(nearest.x), 1.0, signf(nearest.z)) * 0.01

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
			vertices[index] = _backdrop_foot(Vector3(x, 0, z))
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
	# The ring faces inward and is drawn one-sided, as in the original: a view
	# from just outside it (EL2's default view) does not see the near wall.
	backdrop.material_override.cull_mode = BaseMaterial3D.CULL_BACK
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
	material.cull_mode = BaseMaterial3D.CULL_BACK
	node.material_override = material
	add_child(node)
	return material

func _process(delta: float) -> void:
	_sync_light()
	for i in moving_layers.size():
		var material := moving_layers[i]
		material.uv1_offset.x = fposmod(material.uv1_offset.x + delta * layer_speeds[i], 1.0)

func clear_camera_view(camera_position: Vector3, target: Vector3) -> void:
	# Hide tall scenery between the camera and the central play area. Terrain
	# and small scenery stay visible, including the ground under distant trees.
	for child: ELModel in _camera_obstacles:
		var obscures := false
		for part: MeshInstance3D in child.parts.values():
			if part.mesh == null:
				continue
			var box: AABB = part.global_transform * part.mesh.get_aabb()
			if box.size.y > 2.0 and box.intersects_segment(camera_position, target + Vector3(0, 1.5, 0)) != null:
				obscures = true
		child.visible = not obscures

func _add_model(profile: ELProfile, model_name: String, texture_name: String, backdrop := false) -> ELModel:
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
		var standard := part.material_override as StandardMaterial3D
		if standard == null: continue
		if backdrop:
			if not _unlit.has(standard):
				var far := ShaderMaterial.new()
				far.shader = BACKDROP_SHADER
				far.set_shader_parameter("albedo_texture", standard.albedo_texture)
				_unlit[standard] = far
			part.material_override = _unlit[standard]
			continue
		if model_name.begins_with("coob") and standard.albedo_texture != null and standard.albedo_texture.has_meta(ELTexture.ONE_BIT_ALPHA):
			standard.alpha_scissor_threshold = MASKED_ALPHA_CUTOFF
		if standard.has_meta(ELFigure.AUTHORED_FULLBRIGHT):
			# Magic parts keep their authored light. Match the one-sided arena
			# scenery while leaving their texture and authored emission intact.
			standard.cull_mode = BaseMaterial3D.CULL_BACK
			if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				standard.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				standard.render_priority = -1
			continue
		if not _lit.has(standard):
			var lit := ShaderMaterial.new()
			# Soft-alpha sheets (Alpha32: the Mines' running water) blend.
			var soft := standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			lit.shader = LIT_BLEND_SHADER if soft else LIT_SHADER
			if soft: lit.render_priority = -1
			lit.set_shader_parameter("albedo_texture", standard.albedo_texture)
			lit.set_shader_parameter("albedo_tint", standard.albedo_color)
			if not soft: lit.set_shader_parameter("alpha_cutoff", standard.alpha_scissor_threshold)
			_lit[standard] = lit
			_lit_materials.append(lit)
		part.material_override = _lit[standard]
		part.set_meta("albedo", standard.albedo_texture)
	objects_loaded += 1
	return model
