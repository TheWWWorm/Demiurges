shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D mask_texture : filter_linear_mipmap, repeat_disable;
// Ground shadows sit over the terrain's mist pass. Sample the same masks so
// they fade into that mist instead of leaving a dark rectangle on top of it.
uniform bool fog_enabled = false;
uniform sampler2D fog_from : filter_linear, repeat_disable;
uniform sampler2D fog_to : filter_linear, repeat_disable;
uniform ivec2 fog_size = ivec2(1, 1);
uniform float fog_fade = 1.0;
varying flat float opacity;
varying vec2 cell;

void vertex() {
	opacity = INSTANCE_CUSTOM.x;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cell = vec2(world.x, -world.z) / 2.0;
}

void fragment() {
	float alpha = texture(mask_texture, UV).a * opacity;
	if (fog_enabled) {
		vec2 corner = (cell + vec2(0.5)) / vec2(fog_size + ivec2(1));
		float from = texture(fog_from, corner).r;
		float fog = from + clamp(texture(fog_to, corner).r - from, -fog_fade, fog_fade);
		alpha *= 1.0 - fog;
	}
	ALBEDO = vec3(0.0);
	// The original blends black over the ground in display space.
	ALPHA = OUTPUT_IS_SRGB ? alpha : 1.0 - pow(1.0 - alpha, 2.2);
}
