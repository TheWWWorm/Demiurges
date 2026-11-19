shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 water_colour : source_color = vec3(0.19, 0.40, 0.46);
uniform vec3 horizon_colour : source_color = vec3(0.31, 0.57, 0.69);
uniform vec3 sky_colour : source_color = vec3(0.54, 0.76, 0.85);
uniform sampler2D ship_atlas : source_color, filter_linear_mipmap_anisotropic;
varying vec3 world_position;

#include "res://src/render/water_ripples.gdshaderinc"
#include "res://src/render/arena_atmosphere.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_camera = CAMERA_POSITION_WORLD - world_position;
	vec3 view = normalize(to_camera);
	float distance_fade = 1.0 - smoothstep(22.0, 58.0, length(to_camera));
	// Distance alone cannot tell when a grazing view packs many ripples
	// into a pixel. Fade those frequencies before the surface sparkles.
	float footprint = max(length(dFdx(world_position.xz)), length(dFdy(world_position.xz)));
	float ripple_fade = distance_fade * (1.0 - smoothstep(0.08, 0.42, footprint));
	vec4 ripple = water_ripples(world_position.xz);
	vec3 normal = normalize(vec3(ripple.y * ripple_fade, 1.0, ripple.z * ripple_fade));
	vec3 reflected = reflect(-view, normal);
	float fresnel = 0.10 + 0.56 * pow(1.0 - max(dot(view, normal), 0.0), 4.0);
	vec3 sky = mix(horizon_colour, sky_colour, smoothstep(0.0, 0.7, reflected.y));
	float crest = smoothstep(0.1, 0.57, ripple.x) * ripple_fade;
	vec3 half_vector = sun_direction + view;
	float half_length = max(length(half_vector), 0.0001);
	float variance = dot(dFdx(normal), dFdx(normal)) + dot(dFdy(normal), dFdy(normal));
	float shininess = 1.0 / (1.0 / 85.0 + variance * 2.0);
	float glint = pow(max(dot(normal, half_vector / half_length), 0.0), shininess) * (shininess / 85.0) * ripple_fade;
	vec3 water = mix(water_colour, sky, fresnel) + sky_colour * (0.12 * crest + 0.18 * glint);
	// The original panorama continues beyond the edge of the authored sea.
	float rim = smoothstep(22.0, 28.5, length(world_position.xz));
	water = mix(water, horizon_colour, rim * 0.55);
	// Fade through the authored narrow strip under the rails. Some texels
	// here include the hull's painted edge and contact shading.
	float open_sea = max(smoothstep(10.15, 11.1, abs(world_position.z - 0.0095)),
		smoothstep(13.0, 18.0, abs(world_position.x)));
	// Broken, low-contrast foam in the existing hull transition. Its mask
	// never extends onto the deck or replaces the painted contact shading.
	float foam_band = 4.0 * open_sea * (1.0 - open_sea);
	float foam = foam_band * smoothstep(-0.08, 0.52, ripple.x) * ripple_fade;
	water = mix(water, sky_colour, foam * 0.16);
	// Broad, very faint interference catches angled sun without adding a
	// second texture or making a regular tile pattern. Filter toward zero
	// at the same grazing/distant footprints that suppress undersampled chop.
	vec2 drift = world_position.xz * 1.9 + vec2(0.11, -0.16) * TIME;
	float lines_a = sin(drift.x * 1.13 + sin(drift.y * 0.68));
	float lines_b = sin(drift.y * 1.37 - sin(drift.x * 0.51));
	float veil = smoothstep(0.40, 0.88, lines_a * lines_b * 0.5 + 0.5);
	water += sky_colour * (veil * 0.026 * ripple_fade * (1.0 - rim));
	ALBEDO = arena_atmosphere_light(mix(texture(ship_atlas, UV).rgb, water, open_sea));
}
