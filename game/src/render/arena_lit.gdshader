shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Arena scenery: the original texture, lit as arena_light describes.
// One-sided, as D3D-era back-face culling draws it (like the backdrop ring):
// the authored standing view (Default1) stands outside the walls of closed
// arenas such as the first game's «Круг времени» and looks in through their
// backs; drawn double-sided, the near wall filled the screen with darkness.
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
