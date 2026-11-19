shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The figure keeps its real skin underneath a brief tint. The same alpha
// mask and UV transform keep feathers, hair and carried blades cut out;
// an opaque override used to reveal their whole rectangular mesh cards.
uniform sampler2D skin : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 skin_uv = vec4(1.0, 1.0, 0.0, 0.0);
uniform bool repeat_skin = true;
uniform bool alpha_enabled = true;
uniform bool cutout = true;
uniform float alpha_cutoff = 0.5;
uniform float figure_opacity = 1.0;
uniform vec4 flash_colour : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV * skin_uv.xy + skin_uv.zw;
	if (!repeat_skin) {
		vec2 margin = 0.5 / vec2(textureSize(skin, 0));
		uv = clamp(uv, margin, vec2(1.0) - margin);
	}
	float alpha = (alpha_enabled ? texture(skin, uv).a : 1.0) * figure_opacity;
	if (cutout && alpha < alpha_cutoff) discard;
	ALBEDO = flash_colour.rgb;
	ALPHA = clamp(alpha * flash_colour.a * strength * 0.62, 0.0, 1.0);
}
