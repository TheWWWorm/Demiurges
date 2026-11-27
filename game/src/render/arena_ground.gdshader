shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Detail is a modulation signal, not a colour; retain its neutral midpoint.
uniform sampler2D detail_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_tile_size = 2.0;
uniform float detail_neutral = 0.0;
// A shallow surface relief in world units. Derivatives reuse the sampled
// detail signal, so this does not need a normal map or extra texture reads.
uniform float detail_height : hint_range(0.0, 0.08) = 0.028;
#include "res://src/render/arena_light.gdshaderinc"
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
	// A surface-gradient bump works without authored tangent attributes,
	// including the originals' slopes and mirrored UVs. Filter it away with
	// the grain and limit the slope, so large texel steps never turn a flat
	// floor into jagged rocks or crawl against a distant silhouette.
	float height = (dot(grain, vec3(0.333333)) - detail_neutral) * detail_height * fade;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 across_x = cross(dy, NORMAL);
	vec3 across_y = cross(NORMAL, dx);
	float surface_determinant = dot(dx, across_x);
	vec3 gradient = dFdx(height) * across_x + dFdy(height) * across_y;
	if (abs(surface_determinant) > 0.00000001) {
		gradient /= surface_determinant;
		gradient *= min(1.0, 0.35 / max(length(gradient), 0.00001));
		NORMAL = normalize(NORMAL - gradient);
	}
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += arena_sun(LIGHT_COLOR, ATTENUATION, NORMAL, LIGHT, ALBEDO, LIGHT_IS_DIRECTIONAL, DIFFUSE_LIGHT);
}
