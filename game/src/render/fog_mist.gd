class_name ELFogMist
extends SubViewport
## The adventure fog's animated ether mist (both games share the generator,
## its palette and the fog tables):
## - each mist frame is a 256 x 256 sum of four 32 x 32 hashed noise grids,
##   smoothed, then sampled over 8-, 4-, 2- and 1-texel cells;
## - the shown texture cross-fades the older frame into the newer one over 16
##   steps at 4 steps a second, then the next frame takes over (a new frame
##   every 4 seconds), through a 256-colour palette from dark 050505 to
##   303030 (RGB565);
## - FogAnimations off keeps the first frame; the mist still drifts.
## The frame composition runs as a canvas shader on the GPU; the grids are made
## here. The engine's random source for the grid seeds is not reproduced.

const SIZE := 256
const GRID := 32
const RATE := 4.0
const STEPS := 16
## The palette (dark end below index 0x77, pow(0xf8 / 255) falloff above).
const DARK := Color8(5, 5, 5)
const LIGHT := Color8(0x30, 0x30, 0x30)

var animate := true
## Texture offset along the map rows, 0.01 a second whether animated or not.
var drift := 0.0
var step := 0
var fraction := 0.0
var rng := RandomNumberGenerator.new()
var _from: ImageTexture
var _to: ImageTexture
var _material: ShaderMaterial

func _init() -> void:
	size = Vector2i(SIZE, SIZE)
	disable_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	_material = ShaderMaterial.new()
	_material.shader = load("res://src/render/fog_mist.gdshader")
	rect.material = _material
	add_child(rect)
	_material.set_shader_parameter("palette", ImageTexture.create_from_image(palette_image()))
	_from = ImageTexture.create_from_image(grids_image(rng))
	_to = ImageTexture.create_from_image(grids_image(rng))
	_material.set_shader_parameter("grids_from", _from)
	_material.set_shader_parameter("grids_to", _to)
	_apply_weight()

## Byte weight of the newer frame (1..255) for the current step.
func weight() -> int:
	return int((float(step) + fraction) * 0.0625 * 254.0 + 1.0)

func advance(delta: float) -> void:
	drift = fposmod(drift + delta * 0.01, 1.0)
	if not animate: return
	fraction += delta * RATE
	while fraction >= 1.0:
		fraction -= 1.0
		if step == STEPS - 1:
			step = 0
			var older := _from
			_from = _to
			older.update(grids_image(rng))
			_to = older
			_material.set_shader_parameter("grids_from", _from)
			_material.set_shader_parameter("grids_to", _to)
		else:
			step += 1
	_apply_weight()

func _process(delta: float) -> void:
	advance(delta)

func _apply_weight() -> void:
	_material.set_shader_parameter("weight", weight())

## Four noise grids for one frame, one per RGBA channel.
static func grids_image(source: RandomNumberGenerator) -> Image:
	var data := PackedByteArray()
	data.resize(GRID * GRID * 4)
	for channel in 4:
		var grid := noise_grid(source.randi(), source.randi(), source.randi())
		for k in GRID * GRID: data[k * 4 + channel] = grid[k]
	return Image.create_from_data(GRID, GRID, false, Image.FORMAT_RGBA8, data)

## One smoothed 32 x 32 grid: a 29-bit integer hash per cell, then a 3 x 3
## weighted sum (centre 1/4, sides 1/8, corners 1/16) over the flat index with
## 1024-cell wrap, top 8 bits kept.
static func noise_grid(a: int, b: int, c: int) -> PackedByteArray:
	const MASK := 0x1fffffff
	a &= MASK
	b &= MASK
	c &= MASK
	var raw := PackedInt32Array()
	raw.resize(GRID * GRID)
	for row in GRID:
		var u := row
		for column in GRID:
			var v := ((u << 13) ^ u) & MASK
			var h := (((v * v) & MASK) * a) & MASK
			raw[row * GRID + column] = ((((h + b) & MASK) * v & MASK) + c) & MASK
			u += 0x39
	var result := PackedByteArray()
	result.resize(GRID * GRID)
	for k in GRID * GRID:
		var sides := raw[(k - 32) & 0x3ff] + raw[(k - 1) & 0x3ff] + raw[(k + 1) & 0x3ff] + raw[(k + 32) & 0x3ff]
		var corners := raw[(k - 33) & 0x3ff] + raw[(k - 31) & 0x3ff] + raw[(k + 31) & 0x3ff] + raw[(k + 33) & 0x3ff]
		result[k] = (((sides >> 3) + (corners >> 4) + (raw[k] >> 2)) >> 21) & 0xff
	return result

## 256 palette colours as the RGB565 texture stores them.
static func palette_image() -> Image:
	var image := Image.create(256, 1, false, Image.FORMAT_RGB8)
	for i in 256:
		var t := pow(248.0 / 255.0, float(maxi(i - 0x77, 0)))
		var r := roundi(((1.0 - t) * LIGHT.r8 / 255.0 + t * DARK.r8 / 255.0) * 31.0)
		var g := roundi(((1.0 - t) * LIGHT.g8 / 255.0 + t * DARK.g8 / 255.0) * 63.0)
		var b := roundi(((1.0 - t) * LIGHT.b8 / 255.0 + t * DARK.b8 / 255.0) * 31.0)
		image.set_pixel(i, 0, Color(r / 31.0, g / 63.0, b / 31.0))
	return image
