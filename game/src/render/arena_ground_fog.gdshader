shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled;

uniform vec4 fog_colour : source_color;
uniform float fog_size;
uniform float fog_height;
uniform sampler2D mist_noise : filter_linear, repeat_enable;
uniform sampler2D wake_mask : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
varying vec2 floor_position;

void vertex() {
	floor_position = VERTEX.xz;
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = max(VERTEX.z - scene.z / scene.w, 0.0);
	vec3 view_ray = normalize(VERTEX);
	vec3 ray = transpose(mat3(MODEL_MATRIX)) * mat3(INV_VIEW_MATRIX) * view_ray;
	float slab = fog_height / max(-ray.y, 0.05);
	float fraction = clamp(gap / max(-view_ray.z * slab, 0.001), 0.0, 1.0);
	float thickness = slab * fraction * fraction;
	vec2 ground_point = floor_position + ray.xz * (slab * fraction * 0.8);

	// Only the density moves. The height stays level across the arena.
	vec2 drift = vec2(0.32, 0.12) * TIME;
	float mist = texture(mist_noise, (ground_point - drift) * 0.018).r;
	float wisps = texture(mist_noise, (ground_point + drift * 0.6) * 0.038 + vec2(0.47, 0.29)).r;
	float density = mix(0.22, 0.92, smoothstep(0.22, 0.81, mix(mist, wisps, 0.30)));
	float wake = texture(wake_mask, ground_point / fog_size + 0.5).r;
	float rim = 4.0 * wake * (1.0 - wake);
	density *= 1.0 - wake + 0.23 * rim;

	float radius = length(ground_point);
	float edge = 1.0 - smoothstep(17.0, 26.5, radius);
	float centre_fade = mix(0.58, 1.0, smoothstep(5.0, 15.0, radius));
	float camera_fade = smoothstep(1.0, 4.0, length(VERTEX));
	ALBEDO = fog_colour.rgb;
	ALPHA = (1.0 - exp(-2.0 * thickness)) * density * edge * centre_fade * camera_fade * fog_colour.a;
}
