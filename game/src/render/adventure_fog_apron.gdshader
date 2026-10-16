shader_type spatial;
render_mode unshaded, cull_disabled;
// The fog's mist beyond the map edge (24 tiles out, as the original's fog
// pass draws it): opaque mist tinted red, the tint fading to none over the
// tile next to the edge.
uniform sampler2D fog_mist : filter_linear, repeat_enable;
uniform float fog_drift = 0.0;
uniform vec2 map_size = vec2(1.0);
const float MIST_SCALE = 0.05;
varying vec2 cell;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cell = vec2(world.x, -world.z) / 2.0;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 outside = max(-cell, cell - map_size);
	float beyond = max(outside.x, outside.y);
	if (beyond <= 0.0) discard;
	vec3 tint = mix(vec3(1.0), vec3(1.0, 0.0, 0.0), clamp(beyond, 0.0, 1.0));
	vec3 shown = texture(fog_mist, cell * MIST_SCALE + vec2(0.0, fog_drift)).rgb * tint;
	ALBEDO = OUTPUT_IS_SRGB ? shown : to_linear(shown);
}
