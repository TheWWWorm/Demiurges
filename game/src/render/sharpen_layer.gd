extends CanvasLayer
## Optional sharpening of the 3D map and battle scenes (remake addition; the
## originals' textures are small and look soft on large screens). A contrast
## adaptive filter over the rendered scene, drawn below every interface layer
## so the original 2D art stays exact. The "sharpening" preference picks off,
## light or strong; off hides the layer and costs nothing.
const LAYER := -10
const AMOUNTS := [0.0, 0.45, 0.9]
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float amount = 0.45;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = textureLod(screen, SCREEN_UV, 0.0).rgb;
	vec3 n = textureLod(screen, SCREEN_UV + vec2(0.0, -px.y), 0.0).rgb;
	vec3 s = textureLod(screen, SCREEN_UV + vec2(0.0, px.y), 0.0).rgb;
	vec3 e = textureLod(screen, SCREEN_UV + vec2(px.x, 0.0), 0.0).rgb;
	vec3 w = textureLod(screen, SCREEN_UV + vec2(-px.x, 0.0), 0.0).rgb;
	vec3 low = min(c, min(min(n, s), min(e, w)));
	vec3 high = max(c, max(max(n, s), max(e, w)));
	// Less sharpening where the neighbourhood already has strong contrast.
	vec3 weight = sqrt(clamp(min(low, 1.0 - high) / max(high, vec3(1e-4)), 0.0, 1.0)) * (-1.0 / mix(8.0, 5.0, amount));
	vec3 result = (c + (n + s + e + w) * weight) / (1.0 + 4.0 * weight);
	COLOR = vec4(clamp(result, 0.0, 1.0), 1.0);
}
"""
var rect: ColorRect
var choice := -1
## The preference set whose "sharpening" this layer follows.
var settings: ELSettings

func _init() -> void:
	layer = LAYER
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	add_child(rect)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if settings == null: return
	var wanted := clampi(int(settings.values.get("sharpening", 1)), 0, AMOUNTS.size() - 1)
	if wanted != choice: apply(wanted)

func apply(value: int) -> void:
	choice = clampi(value, 0, AMOUNTS.size() - 1)
	visible = AMOUNTS[choice] > 0.0
	(rect.material as ShaderMaterial).set_shader_parameter("amount", AMOUNTS[choice])
