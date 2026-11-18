class_name ELFirstNavalVisuals
extends Node3D
## Public harbors and a self-contained ship appearance for EL1 installations.
## An installed EL2 supplies its original he551 / Heroes/Boat00 instead.
## No game assets are copied between editions or included with the generator.
const FLAG_COLORS := [Color("dfc077"), Color("df755e"), Color("75b8d0"), Color("a5bf77")]
var map: ELAdventureMap
var harbors: Array[Dictionary] = []

static func ship_source(source: ELProfile) -> ELProfile:
	if source == null or source.id != "el2": return null
	if not ELModel.prepare(source, "he551").is_empty(): return null
	if source.texture("Heroes/Boat00") == null: return null
	return source

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func _part(model: ELModel, key: String, mesh: Mesh, color: Color, at := Vector3.ZERO) -> void:
	var part := MeshInstance3D.new()
	part.name = key
	part.mesh = mesh
	part.material_override = _material(color)
	part.position = at
	model.add_child(part)
	model.parts[key] = part

static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

static func _triangles(vertices: PackedVector3Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in vertices: surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

## ELModel keeps the usual scene, fog, selection, and movement interfaces even
## when the original second-game figure is unavailable. The bow faces +Z,
## matching ELAdventureScene.move_actor's facing convention.
static func build_boat(model: ELModel, profile: ELProfile, owner := 1, faction := "") -> bool:
	model.profile = profile
	model.template = "el1_naval_sailboat"
	model.set_process(false)
	var upper := PackedVector3Array([
		Vector3(0, 0.26, 1.03), Vector3(0.47, 0.26, 0.45),
		Vector3(0.43, 0.26, -0.69), Vector3(0, 0.26, -0.86),
		Vector3(-0.43, 0.26, -0.69), Vector3(-0.47, 0.26, 0.45)])
	var bottom := PackedVector3Array()
	for vertex: Vector3 in upper: bottom.append(Vector3(vertex.x * 0.64, -0.04, vertex.z * 0.83))
	var hull := PackedVector3Array()
	var deck := PackedVector3Array()
	for index in upper.size():
		var next := (index + 1) % upper.size()
		hull.append_array(PackedVector3Array([upper[index], bottom[index], upper[next], upper[next], bottom[index], bottom[next]]))
		deck.append_array(PackedVector3Array([Vector3(0, 0.26, 0), upper[next], upper[index]]))
	_part(model, "hull", _triangles(hull), Color("5b3524"))
	_part(model, "deck", _triangles(deck), Color("b68b52"))
	_part(model, "mast", _box(Vector3(0.065, 1.55, 0.065)), Color("69482d"), Vector3(0, 0.99, -0.06))
	_part(model, "yard", _box(Vector3(1.18, 0.055, 0.055)), Color("69482d"), Vector3(0, 1.63, -0.02))
	var sail := PackedVector3Array([
		Vector3(-0.55, 1.59, 0), Vector3(-0.45, 0.72, 0.09), Vector3(0, 1.20, 0.24),
		Vector3(-0.55, 1.59, 0), Vector3(0, 1.20, 0.24), Vector3(0.55, 1.59, 0),
		Vector3(0.55, 1.59, 0), Vector3(0, 1.20, 0.24), Vector3(0.45, 0.72, 0.09),
		Vector3(-0.45, 0.72, 0.09), Vector3(0.45, 0.72, 0.09), Vector3(0, 1.20, 0.24)])
	_part(model, "canvas", _triangles(sail), Color("e3dab4"))
	var flag := PackedVector3Array([Vector3(0, 1.75, -0.06), Vector3(0.43, 1.62, -0.06), Vector3(0, 1.49, -0.06)])
	var ink: Color = {"Green": Color("80b858"), "Blue": Color("66b7dd"), "Red": Color("dd654c"), "Black": Color("8c879e")}.get(faction, FLAG_COLORS[posmod(owner - 1, FLAG_COLORS.size())])
	_part(model, "pennant", _triangles(flag), ink)
	_part(model, "bench", _box(Vector3(0.69, 0.07, 0.16)), Color("7c5535"), Vector3(0, 0.35, -0.40))
	return true

func build(source: ELAdventureMap) -> void:
	map = source
	for entry: Dictionary in harbors: entry.model.free()
	harbors.clear()
	if not ELFirstNaval.enabled(map): return
	for port: Dictionary in map.get_meta("first_naval", {}).get("ports", []):
		var land := Vector2i(int(port.land[0]), int(port.land[1]))
		var water := Vector2i(int(port.water[0]), int(port.water[1]))
		var model := ELModel.new()
		model.name = "Harbor_%s" % str(port.get("id", harbors.size()))
		model.profile = map.profile
		model.template = "el1_naval_harbor"
		model.set_process(false)
		add_child(model)
		model.position = ELAdventureScene.world_position(land.x, land.y)
		var direction := ELAdventureScene.world_position(water.x, water.y) - model.position
		model.rotation.y = atan2(direction.x, direction.z)
		# A narrow pier reaches from the land-cell center to the sea-cell
		# center; it marks the connection without blocking the hero.
		_part(model, "pier", _box(Vector3(0.82, 0.11, 2.16)), Color("9b784e"), Vector3(0, 0.11, 0.9))
		for at: Vector3 in [Vector3(-0.5, 0.28, 0.15), Vector3(0.5, 0.28, 0.15), Vector3(-0.5, 0.28, 1.65), Vector3(0.5, 0.28, 1.65)]:
			_part(model, "post_%d" % model.parts.size(), _box(Vector3(0.12, 0.65, 0.12)), Color("5e4930"), at)
		_part(model, "beacon", _box(Vector3(0.10, 1.75, 0.10)), Color("5e4930"), Vector3(-0.62, 0.87, -0.24))
		var flag := PackedVector3Array([Vector3(-0.62, 1.74, -0.24), Vector3(-0.62, 1.22, -0.24), Vector3(-0.03, 1.48, -0.24)])
		_part(model, "banner", _triangles(flag), Color("65becb"))
		model.hide()
		harbors.append({"model": model, "land": land, "water": water, "level": -1})

## The whole pier stays hidden until both endpoints have been explored. This
## prevents a dock from revealing the next tile through the fog boundary.
func set_fog(tiles: PackedByteArray) -> void:
	if map == null: return
	var valid := tiles.is_empty() or tiles.size() == map.width * map.height
	for entry: Dictionary in harbors:
		var level := 255
		if valid:
			level = 0 if tiles.is_empty() else maxi(tiles[entry.land.y * map.width + entry.land.x], tiles[entry.water.y * map.width + entry.water.x])
		if entry.level == level: continue
		entry.level = level
		entry.model.visible = level < 255
		var brightness := 1.0 if level == 0 else 0.3
		for part: MeshInstance3D in entry.model.parts.values():
			if not part.has_meta("base_color"): part.set_meta("base_color", part.material_override.albedo_color)
			part.material_override.albedo_color = part.get_meta("base_color") * Color(brightness, brightness, brightness, 1.0)
