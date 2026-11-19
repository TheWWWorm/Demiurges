shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D ring_atlas : source_color, filter_linear, repeat_disable;
uniform vec2 frame_from = vec2(0.0);
uniform vec2 frame_to = vec2(0.125, 0.0);
uniform float frame_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_modulate : source_color = vec4(1.0);
uniform vec4 ring_flash : source_color = vec4(0.0);
uniform float outline_strength : hint_range(0.0, 1.0) = 0.44;
const vec2 FRAME_SIZE = vec2(0.125);

// Transparent texels may contain unrelated RGB. Blend premultiplied colour
// between authored frames, then return to straight alpha for normal blending.
// Half-texel bounds keep bilinear taps inside the chosen 64 px frame (or its
// upscaled equivalent), including the last frame before a race-colour boundary.
vec4 frame_sample(vec2 offset, vec2 point, vec2 inset) {
	vec2 uv = clamp(offset + point * FRAME_SIZE, offset + inset, offset + FRAME_SIZE - inset);
	vec4 sample_colour = texture(ring_atlas, uv);
	return vec4(sample_colour.rgb * sample_colour.a, sample_colour.a);
}

vec4 ring_sample(vec2 point, vec2 inset) {
	return mix(frame_sample(frame_from, point, inset), frame_sample(frame_to, point, inset), frame_mix);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(ring_atlas, 0));
	vec2 inset = min(texel * 0.5, FRAME_SIZE * 0.49);
	vec4 ring = ring_sample(UV, inset);
	float outline = 0.0;
	if (outline_strength > 0.0) {
		// Roughly one display pixel, bounded by source texels. This dark
		// contour follows the actual artwork; the empty centre stays empty.
		vec2 radius = clamp(fwidth(UV) * 0.8, texel / FRAME_SIZE * 0.5, texel / FRAME_SIZE * 1.5);
		float around = max(max(ring_sample(UV + vec2(radius.x, 0.0), inset).a,
			ring_sample(UV - vec2(radius.x, 0.0), inset).a),
			max(ring_sample(UV + vec2(0.0, radius.y), inset).a,
			ring_sample(UV - vec2(0.0, radius.y), inset).a));
		outline = max(around - ring.a, 0.0) * outline_strength;
	}
	float opacity = ring.a + outline * (1.0 - ring.a);
	ALBEDO = (ring.rgb * ring_modulate.rgb + ring_flash.rgb * ring.a) / max(opacity, 0.0001);
	ALPHA = opacity * ring_modulate.a;
}
