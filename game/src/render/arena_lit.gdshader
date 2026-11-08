shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
// Arena scenery: the original texture, lit as arena_light describes.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://src/render/arena_light.gdshaderinc"

void fragment() {
	vec4 base = texture(albedo_texture, UV);
	ALBEDO = base.rgb;
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += arena_sun(LIGHT_COLOR, ATTENUATION, NORMAL, LIGHT, ALBEDO);
}
