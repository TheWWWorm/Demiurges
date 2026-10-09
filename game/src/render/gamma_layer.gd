class_name ELGammaLayer
extends CanvasLayer
## Options gamma for the whole screen. The original sets one hardware gamma
## ramp from the Gamma setting (-1..1; Brightness and Contrast have no
## control and stay 0): c = gamma / 2, exponent 1 / (5c + 1) above zero and
## 1 / (c / 2 + 1) below, each level (i / 255) ^ exponent. Here a last pass
## over the finished frame applies the same curve; at gamma 0 it is skipped.
const LAYER := 120
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float exponent = 1.0;
void fragment() {
	vec3 colour = textureLod(screen, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(pow(max(colour, vec3(0.0)), vec3(exponent)), 1.0);
}
"""
var rect: ColorRect
var value := 0.0
## When set, the layer follows this preference set's "gamma" (it changes
## with Options OK and with the active edition).
var settings: ELSettings

static func exponent(gamma: float) -> float:
	var c := clampf(gamma, -1.0, 1.0) * 0.5
	if c > 0.0: return 1.0 / (c * 5.0 + 1.0)
	if c < 0.0: return 1.0 / (c * 0.5 + 1.0)
	return 1.0

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
	var wanted := clampf(float(settings.values.get("gamma", 0.0)), -1.0, 1.0)
	if not is_equal_approx(wanted, value): apply(wanted)

func apply(gamma: float) -> void:
	value = clampf(gamma, -1.0, 1.0)
	var power := exponent(value)
	visible = not is_equal_approx(power, 1.0)
	if rect != null and rect.material is ShaderMaterial: (rect.material as ShaderMaterial).set_shader_parameter("exponent", power)
