// Arena scenery lighting shared by arena_lit and arena_ground: ambient plus
// sun, the sum limited to full brightness as in the originals, so a lit
// surface never exceeds its texture.
// The scene's ambient light (colour times energy), kept current by ELArena.
uniform vec3 ambient_light = vec3(0.0);
uniform float light_limit = 1.0;
// Set while the sun casts shadows. The Compatibility renderer then adds the
// sun in a pass of its own after the colour is display (sRGB) encoded, which
// would brighten lit surfaces far beyond the light's share; the sun term is
// chosen so the encoded sum equals the linear one.
uniform bool encoded_sun_pass = false;

vec3 arena_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 arena_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 arena_sun(vec3 light_color, float attenuation, vec3 normal, vec3 light_dir, vec3 albedo) {
	vec3 sun = light_color / PI * attenuation * max(dot(normal, light_dir), 0.0);
	sun = min(sun, max(vec3(light_limit) - ambient_light, vec3(0.0)));
	if (!encoded_sun_pass) return sun;
	vec3 base = clamp(albedo * ambient_light, 0.0, 1.0);
	vec3 lit = clamp(albedo * (ambient_light + sun), 0.0, 1.0);
	return arena_to_linear(arena_to_srgb(lit) - arena_to_srgb(base)) / max(albedo, vec3(0.0001));
}
