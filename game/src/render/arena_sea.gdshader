shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 water_colour : source_color = vec3(0.19, 0.40, 0.46);
uniform vec3 horizon_colour : source_color = vec3(0.31, 0.57, 0.69);
uniform vec3 sky_colour : source_color = vec3(0.54, 0.76, 0.85);
uniform sampler2D ship_atlas : source_color, filter_linear_mipmap_anisotropic;
varying vec3 world_position;

#include "res://src/render/water_ripples.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_camera = CAMERA_POSITION_WORLD - world_position;
	vec3 view = normalize(to_camera);
	float distance_fade = 1.0 - smoothstep(22.0, 58.0, length(to_camera));
	vec4 ripple = water_ripples(world_position.xz);
	vec3 normal = normalize(vec3(ripple.y * distance_fade, 1.0, ripple.z * distance_fade));
	vec3 reflected = reflect(-view, normal);
	float fresnel = 0.10 + 0.56 * pow(1.0 - max(dot(view, normal), 0.0), 4.0);
	vec3 sky = mix(horizon_colour, sky_colour, smoothstep(0.0, 0.7, reflected.y));
	float crest = smoothstep(0.1, 0.57, ripple.x) * distance_fade;
	float glint = pow(max(dot(normal, normalize(sun_direction + view)), 0.0), 85.0) * distance_fade;
	vec3 water = mix(water_colour, sky, fresnel) + sky_colour * (0.12 * crest + 0.18 * glint);
	// The original panorama continues beyond the edge of the authored sea.
	float rim = smoothstep(22.0, 28.5, length(world_position.xz));
	water = mix(water, horizon_colour, rim * 0.55);
	// Fade through the authored narrow strip under the rails. Some texels
	// here include the hull's painted edge and contact shading.
	float open_sea = max(smoothstep(10.15, 11.1, abs(world_position.z - 0.0095)),
		smoothstep(13.0, 18.0, abs(world_position.x)));
	ALBEDO = mix(texture(ship_atlas, UV).rgb, water, open_sea);
}
