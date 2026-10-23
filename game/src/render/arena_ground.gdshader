shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Detail is a modulation signal, not a colour; retain its neutral midpoint.
uniform sampler2D detail_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_tile_size = 2.0;
uniform float detail_neutral = 0.0;
varying vec2 detail_uv;

void vertex() {
	detail_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / detail_tile_size;
}

void fragment() {
	vec4 base = texture(base_texture, UV);
	vec3 grain = texture(detail_texture, detail_uv).rgb;
	vec2 texels = vec2(textureSize(detail_texture, 0));
	float footprint = max(length(dFdx(detail_uv) * texels), length(dFdy(detail_uv) * texels));
	// The original grain is deliberately restrained, and fades when its
	// texels become small to avoid sparkling as the camera pulls back.
	float fade = 1.0 - smoothstep(1.0, 4.0, footprint);
	float relief = clamp((dot(grain, vec3(0.333333)) - detail_neutral) * 1.2, -0.1, 0.1);
	ALBEDO = base.rgb * (1.0 + relief * fade);
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
