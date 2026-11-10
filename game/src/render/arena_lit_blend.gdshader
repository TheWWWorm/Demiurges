shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;
// Arena scenery in soft alpha (Alpha32 sheets such as running water): blended
// over what lies beneath, as the originals draw it, instead of cut out at half
// alpha. Lit as arena_lit.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
#include "res://src/render/arena_light.gdshaderinc"

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = base.rgb;
	ALPHA = base.a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += arena_sun(LIGHT_COLOR, ATTENUATION, NORMAL, LIGHT, ALBEDO);
}
