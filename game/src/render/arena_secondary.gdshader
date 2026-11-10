shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, cull_disabled;

// The opaque copy contains the receiver after its texture and diffuse lighting.
// Apply the original secondary vertex colour before the transparent effects.
uniform sampler2D opaque_colour : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float base_alpha = 1.0;
uniform float alpha_cutoff = 0.5;
uniform bool two_sided = false;
uniform bool normal_aware = false;
uniform int source_count = 0;
// Two vec4s per combat light: world position, then display RGB and reach.
uniform vec4 sources[192];
varying vec3 secondary;
#include "res://src/render/arena_light.gdshaderinc"

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = normal_aware ? normalize(MODEL_NORMAL_MATRIX * NORMAL) : vec3(0.0);
	vec3 colour = vec3(0.0);
	for (int i = 0; i < source_count; i++) {
		vec3 position = sources[2 * i].xyz;
		vec4 light = sources[2 * i + 1];
		// The original scenery draw gathers lights around the model origin.
		if (normal_aware && distance(position, MODEL_MATRIX[3].xyz) > light.w + 10.0) continue;
		vec3 offset = position - world;
		float distance_squared = dot(offset, offset);
		float weight = max(1.0 - distance_squared / (light.w * light.w), 0.0);
		if (normal_aware) {
			weight *= distance_squared > 0.0 ? max(dot(normal, offset) * inversesqrt(distance_squared), 0.0) : 0.0;
		}
		colour = max(colour, light.rgb * weight);
	}
	secondary = roundEven(colour * 255.0) / 255.0;
}

void fragment() {
	if ((!two_sided && !FRONT_FACING) || !any(greaterThan(secondary, vec3(0.0)))) discard;
	if (texture(base_texture, UV).a * base_alpha < alpha_cutoff) discard;
	vec3 base = clamp(textureLod(opaque_colour, SCREEN_UV, 0.0).rgb, 0.0, 1.0);
	if (OUTPUT_IS_SRGB) {
		ALBEDO = min(secondary, 1.0 - base);
	} else {
		ALBEDO = max(arena_to_linear(min(arena_to_srgb(base) + secondary, vec3(1.0))) - base, vec3(0.0));
	}
	ALPHA = 1.0;
}
