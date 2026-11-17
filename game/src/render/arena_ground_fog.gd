extends MeshInstance3D

const SHADER := preload("res://src/render/arena_ground_fog.gdshader")
const FLOOR_SIZE := 54.0
const FOG_HEIGHT := 0.33
const WAKE_RESOLUTION := 128
const TEXELS_PER_UNIT := WAKE_RESOLUTION / FLOOR_SIZE
const WAKE_LIFETIME := 1.6
const UPDATE_INTERVAL := 1.0 / 30.0

static var _mist_noise: ImageTexture
var _wake_image: Image
var _wake_texture: ImageTexture
## Only painted texels need updating. Each holds the time its wake closes.
var _wake_ends: Dictionary[Vector2i, float] = {}
var _time := 0.0
var _since_upload := 0.0

func build(tint: Color, floor_height: float) -> void:
	# The plane marks the top of a shallow volume above the arena floor.
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * FLOOR_SIZE
	mesh = plane
	position.y = floor_height + FOG_HEIGHT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _mist_noise == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.08
		noise.fractal_octaves = 2
		_mist_noise = ImageTexture.create_from_image(noise.get_seamless_image(128, 128))
	_wake_image = Image.create_empty(WAKE_RESOLUTION, WAKE_RESOLUTION, false, Image.FORMAT_R8)
	_wake_texture = ImageTexture.create_from_image(_wake_image)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("fog_colour", tint)
	material.set_shader_parameter("fog_size", FLOOR_SIZE)
	material.set_shader_parameter("fog_height", FOG_HEIGHT)
	material.set_shader_parameter("mist_noise", _mist_noise)
	material.set_shader_parameter("wake_mask", _wake_texture)
	material_override = material

func stir(from: Vector2, to: Vector2, creature_scale: float) -> void:
	if from.distance_squared_to(to) < 0.000001: return
	# Sweep the whole segment so fast creatures leave a continuous wake.
	var centre := Vector2.ONE * (WAKE_RESOLUTION * 0.5 - 0.5)
	var start := from * TEXELS_PER_UNIT + centre
	var finish := to * TEXELS_PER_UNIT + centre
	var radius := clampf(creature_scale * 1.2, 0.75, 1.9) * TEXELS_PER_UNIT
	var padding := Vector2.ONE * radius
	var low := (start.min(finish) - padding).floor().max(Vector2.ZERO)
	var high := (start.max(finish) + padding).ceil().min(Vector2.ONE * (WAKE_RESOLUTION - 1))
	for y in range(int(low.y), int(high.y) + 1):
		for x in range(int(low.x), int(high.x) + 1):
			var point := Vector2(x, y)
			var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, finish))
			var amount := 1.0 - smoothstep(radius * 0.4, radius, distance)
			if amount <= 0.0: continue
			var texel := Vector2i(x, y)
			var end := _time + WAKE_LIFETIME * amount
			_wake_ends[texel] = maxf(end, _wake_ends.get(texel, 0.0))

func _process(delta: float) -> void:
	_time += delta
	_since_upload += delta
	if _wake_ends.is_empty() or _since_upload < UPDATE_INTERVAL: return
	_since_upload = fmod(_since_upload, UPDATE_INTERVAL)
	for texel: Vector2i in _wake_ends.keys():
		var remaining := _wake_ends[texel] - _time
		var amount := smoothstep(0.0, WAKE_LIFETIME, remaining)
		_wake_image.set_pixelv(texel, Color(amount, 0.0, 0.0))
		if remaining <= 0.0: _wake_ends.erase(texel)
	_wake_texture.update(_wake_image)
