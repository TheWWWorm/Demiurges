class_name ELCombatBlood
extends Node3D
## Combat blood, shown when a figure dies with the blood preference on: one
## burst of falling drops from the figure's body point, and sixteen ground
## prints around it that appear, grow, stay for twenty seconds and fade.
## The first game always uses red blood. The second game colours it by the
## figure's `Blood` material (creature and hero tables): red for Alive, dark oil
## for Mech, green for Plant and blue for Unmaterial, Clrless or anything else.
## Positions and speeds use the original combat units (x east, y north, z up),
## converted with ELFigure.vector when drawn. Drops run on a 30 Hz tick;
## their displayed positions interpolate between ticks for smooth motion.

const TICK := 1.0 / 30.0
const DROPS_PER_BURST := 45
const DROP_LIMIT := 300
const PRINTS_PER_BURST := 16
const PRINT_LIMIT := 256
## Print timeline in seconds: hidden, growing, holding, fading.
const PRINT_SHOW := 0.3
const PRINT_GROWN := 0.8
const PRINT_HOLD := 20.8
const PRINT_GONE := 25.8
const PRINT_LIFT := 0.03
## Second-game materials and their looks: print block (column, row of the 2 x 2
## blocks of the prints atlas, each block holding 2 x 2 prints) and the drop
## cell of the 4 x 4 weather atlas. Cells count in the files' stored row order.
const MATERIALS := {"Mech": 0, "Alive": 1, "Plant": 2, "Unmaterial": 3, "Clrless": 4}
const LOOKS := [
	{"block": Vector2i(1, 0), "drop": 13},  # Mech: dark oil
	{"block": Vector2i(0, 0), "drop": 12},  # Alive: red
	{"block": Vector2i(0, 1), "drop": 14},  # Plant: green
	{"block": Vector2i(1, 1), "drop": 15},  # Unmaterial and unknown: blue
	{"block": Vector2i(1, 1), "drop": 15},  # Clrless: blue
]
## The first game: red splash drop, the two round prints of the third row.
const FIRST_DROP := 12
const FIRST_PRINT_ROW := 2

var enabled := true
## Whether the per-material second-game blood is used.
var second := false
## Each drop: position and velocity in original units, size, gravity, terminal speed.
var drops: Array[Dictionary] = []
## Each print: centre (Godot space), age, half-size, growth rate, alpha, atlas cell.
var prints: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var arena: ELArena
var _drop_node: MultiMeshInstance3D
var _print_node: MultiMeshInstance3D
var _clock := 0.0
var _drops_dirty := false
var _prints_dirty := false

func _ready() -> void:
	set_process(not drops.is_empty() or not prints.is_empty())

func _notification(what: int) -> void:
	# Hidden boards keep their original clocks, but defer RenderingServer
	# updates until visible. Held prints need an explicit refresh on reveal.
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		if _drops_dirty: _draw_drops()
		if _prints_dirty: _draw_prints()

func build(profile: ELProfile, battle_arena: ELArena, seed_value := 0, edition := "el1") -> bool:
	arena = battle_arena
	rng.seed = seed_value
	second = edition == "el2"
	var drop_texture := atlas(profile, "Effects/rainsnow")
	var print_texture := atlas(profile, "Effects/bloodprints")
	if drop_texture == null or print_texture == null: return false
	# Drops use a splash cell of the weather atlas; they face the camera.
	_drop_node = _layer(QuadMesh.new(), _material(DROP_SHADER, drop_texture), DROP_LIMIT)
	# Prints lie flat on the ground and use one of the round splats.
	var flat := PlaneMesh.new()
	flat.size = Vector2(2, 2)
	_print_node = _layer(flat, _material(PRINT_SHADER, print_texture), PRINT_LIMIT)
	return true

func _layer(mesh: PrimitiveMesh, material: ShaderMaterial, limit: int) -> MultiMeshInstance3D:
	if mesh is QuadMesh: mesh.size = Vector2(2, 2)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = limit
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 40, 80))
	add_child(node)
	return node

func _material(code: String, texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = ELParticleFile.sprite_shader(code)
	var material := ShaderMaterial.new()
	material.shader = shader
	ELParticleFile.set_atlas(material, texture, Vector2(4, 4))
	material.render_priority = 4
	return material

## An effect atlas in the file's stored row order (as every texture decodes),
## which the cell numbers above use.
static func atlas(profile: ELProfile, name: String) -> Texture2D:
	var bytes := profile.read("textures", ELArchive.key(name) + ".mmp")
	var image := ELTexture.decode(bytes)
	if image == null: return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## The second game's material number for a `Blood` value; unknown values count
## as Unmaterial.
static func material_kind(material: String) -> int:
	return int(MATERIALS.get(material, 3))

## Drop cell and four print cells (column, row in the 4 x 4 atlases) for a
## figure of the given material.
func look(material: String) -> Dictionary:
	if not second:
		return {"drop": Vector2i(FIRST_DROP % 4, 3 - FIRST_DROP / 4),
			"prints": [Vector2i(0, FIRST_PRINT_ROW), Vector2i(1, FIRST_PRINT_ROW)]}
	var entry: Dictionary = LOOKS[material_kind(material)]
	var block: Vector2i = entry.block
	var cells: Array[Vector2i] = []
	for row in 2:
		for column in 2:
			cells.append(Vector2i(block.x * 2 + column, 3 - (block.y * 2 + row)))
	var drop: int = entry.drop
	return {"drop": Vector2i(drop % 4, 3 - drop / 4), "prints": cells}

## Turning the preference off removes the ground prints at once.
func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		prints.clear()
		_draw_prints()
		set_process(not drops.is_empty())

## A figure dies: `origin` is its body point in Godot space; `material` is its
## `Blood` value (second game only).
func burst(origin: Vector3, material := "") -> void:
	if not enabled or _drop_node == null: return
	set_process(true)
	var cells := look(material)
	var prints_cells: Array = cells.prints
	var at := Vector3(origin.x, -origin.z, origin.y)  # original x, y, z
	var ground := arena.ground_height(origin.x, origin.z) if arena != null else 0.0
	var sources: Array[Vector2] = []
	for i in 4 + rng.randi() % 5:
		sources.append(Vector2(0.1 + rng.randf() * 0.2, rng.randf() * TAU))
	for i in DROPS_PER_BURST:
		if drops.size() >= DROP_LIMIT: break
		var source: Vector2 = sources[rng.randi() % sources.size()]
		var speed := source.x * 0.5 + rng.randf() * source.x
		var spread := deg_to_rad(10.0) * source.y
		var angle := source.y - spread + rng.randf() * spread * 2.0
		drops.append({"p": at, "previous": at, "v": Vector3(sin(angle) * speed, cos(angle) * speed, 0.0),
			"size": 0.1 + rng.randf() * 0.1, "gravity": -0.18 + rng.randf() * 0.12,
			"terminal": -0.6 + rng.randf() * 0.4, "floor": ground, "cell": cells.drop})
	for i in PRINTS_PER_BURST:
		var x := at.x
		var y := at.y
		var scale := 1.0
		if i > 0:
			scale = (0.1 + rng.randf() * 0.4) / 0.5
			x += rng.randf() * 3.0 - 1.5
			y += rng.randf() * 3.0 - 1.5
		var centre := ELFigure.vector(Vector3(x, y, 0.0))
		centre.y = (arena.ground_height(centre.x, centre.z) if arena != null else 0.0) + PRINT_LIFT
		var cell: Vector2i = prints_cells[rng.randi() % prints_cells.size()]
		# Vary the orientation without drawing from the established stream:
		# an added cosmetic rotation must not move later drops or change cells.
		var angle := float(hash([rng.state, centre, i]) & 0xffff) * (TAU / 65536.0) - PI
		prints.append({"at": centre, "age": 0.0, "half": 0.0, "rate": scale, "alpha": 1.0,
			"yaw": angle, "cell": cell})
	# A crowded battle must show its newest impact. Keeping invisible excess
	# prints behind the first 256 hid later deaths until old stains expired.
	if prints.size() > PRINT_LIMIT:
		prints = prints.slice(prints.size() - PRINT_LIMIT)
	_draw_drops()
	_draw_prints()

func clear() -> void:
	drops.clear()
	prints.clear()
	_clock = 0.0
	_draw_drops()
	_draw_prints()
	set_process(false)

func _process(delta: float) -> void:
	if not drops.is_empty():
		_clock += delta
		while _clock >= TICK:
			_clock -= TICK
			_step_drops()
		_draw_drops()
	else:
		_clock = 0.0
	if not prints.is_empty():
		advance_prints(delta)
	if drops.is_empty() and prints.is_empty(): set_process(false)

func _step_drops() -> void:
	var count := 0
	for i in drops.size():
		var drop: Dictionary = drops[i]
		var p: Vector3 = drop.p
		if p.z < drop.floor: continue
		var v: Vector3 = drop.v
		drop.previous = p
		drop.p = p + v
		v.z = maxf(v.z + float(drop.gravity), float(drop.terminal))
		drop.v = v
		if count != i: drops[count] = drop
		count += 1
	# Preserve order without allocating a replacement array on every tick.
	drops.resize(count)

## Print timeline: hidden, then growing to half its rate, held, then fading.
func advance_prints(delta: float) -> void:
	var count := 0
	var changed := false
	for i in prints.size():
		var mark: Dictionary = prints[i]
		var before: float = mark.age
		var age := before + delta
		mark.age = age
		if age >= PRINT_GONE:
			changed = true
			continue
		var grow := maxf(0.0, minf(age, PRINT_GROWN) - maxf(before, PRINT_SHOW))
		mark.half = float(mark.half) + grow * float(mark.rate)
		var fade := maxf(0.0, minf(age, PRINT_GONE) - maxf(before, PRINT_HOLD))
		mark.alpha = maxf(0.0, float(mark.alpha) - fade * 0.2)
		# Held prints need no redraw.
		changed = changed or grow > 0.0 or fade > 0.0 or (before < PRINT_SHOW and age >= PRINT_SHOW)
		if count != i: prints[count] = mark
		count += 1
	prints.resize(count)
	if changed: _draw_prints()

func _draw_drops() -> void:
	if _drop_node == null: return
	_drops_dirty = is_inside_tree() and not is_visible_in_tree()
	if _drops_dirty: return
	var multimesh := _drop_node.multimesh
	var count := mini(drops.size(), multimesh.instance_count)
	for i in count:
		var drop: Dictionary = drops[i]
		var size: float = drop.size
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), drop_position(drop)))
		var cell: Vector2i = drop.cell
		multimesh.set_instance_custom_data(i, Color(cell.x * 0.25, cell.y * 0.25, 0, 1))
	multimesh.visible_instance_count = count

## The displayed position between two authored 30 Hz samples (Godot space).
func drop_position(drop: Dictionary) -> Vector3:
	var previous: Vector3 = drop.get("previous", drop.p)
	return ELFigure.vector(previous.lerp(drop.p, clampf(_clock / TICK, 0.0, 1.0)))

func _draw_prints() -> void:
	if _print_node == null: return
	_prints_dirty = is_inside_tree() and not is_visible_in_tree()
	if _prints_dirty: return
	var multimesh := _print_node.multimesh
	var count := 0
	for mark: Dictionary in prints:
		if mark.age < PRINT_SHOW or count >= multimesh.instance_count: continue
		var half: float = mark.half
		var angle := float(mark.get("yaw", 0.0))
		multimesh.set_instance_transform(count, Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(half, 1.0, half)), mark.at))
		var cell: Vector2i = mark.cell
		multimesh.set_instance_custom_data(count, Color(cell.x * 0.25, cell.y * 0.25, 0, float(mark.alpha)))
		count += 1
	multimesh.visible_instance_count = count

## The figure's body point: its "soul" anchor, else 0.6 of its height.
static func body_point(model: ELModel) -> Vector3:
	var soul: Node3D = model.parts.get("soul")
	var mesh: Mesh = model._mesh_cache.get("base/soul")
	if soul != null and mesh != null: return soul.global_transform * mesh.get_aabb().get_center()
	var top := model.global_position.y
	for part: MeshInstance3D in model.parts.values():
		if part.mesh != null: top = maxf(top, (part.global_transform * part.mesh.get_aabb()).end.y)
	return model.global_position + Vector3(0, (top - model.global_position.y) * 0.6, 0)

## Visible ground prints (for checks).
func visible_prints() -> int:
	return _print_node.multimesh.visible_instance_count if _print_node != null else 0

const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(4.0);
varying flat vec2 atlas_slot;
SPRITE_SIZE_FUNCTION
ATLAS_FUNCTION
void vertex() {
	float size = sprite_half_extent(length(MODEL_MATRIX[0].xyz), PROJECTION_MATRIX);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	UV = UV * 0.25 + INSTANCE_CUSTOM.rg;
	atlas_slot = floor(INSTANCE_CUSTOM.rg * 4.0 + vec2(0.001));
}
void fragment() {
	vec4 texel = sprite_atlas(atlas, UV, atlas_slot, grid);
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
}
"""

const PRINT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(4.0);
varying float fade;
varying flat vec2 atlas_slot;
ATLAS_FUNCTION
void vertex() {
	UV = UV * 0.25 + INSTANCE_CUSTOM.rg;
	atlas_slot = floor(INSTANCE_CUSTOM.rg * 4.0 + vec2(0.001));
	fade = INSTANCE_CUSTOM.a;
}
void fragment() {
	vec4 texel = sprite_atlas(atlas, UV, atlas_slot, grid);
	ALBEDO = texel.rgb;
	ALPHA = texel.a * fade;
}
"""
