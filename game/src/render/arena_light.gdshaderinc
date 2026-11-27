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
// Ambient plus sun on level ground, in linear colour (ELArena._surface_light).
uniform vec3 daylight = vec3(1.0);

vec3 arena_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 arena_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// What lamps may add to a surface depends on how bright daylight already
// makes it: their light, summed, rolls off in each channel as the surface
// nears ARENA_LIT_CEILING, just under white. Grass and stone take a spell's
// light nearly in full; snow and ice, close to white in daylight, take only
// a tint and keep their texture, where they burned out to flat white. Each
// lamp takes what the lamps before it left (`so_far`, the light this pass
// has gathered): rolled off one by one, a spell, the figures' glowing
// weapons and the arena's torches each took the whole room and still burned
// the snow out together. (The path-traced composite rolls off the whole
// colour as well, which a lamp's own pass here cannot.) A surface in the
// sun's shadow is judged as if lit, so it takes a little less than it might.
const float ARENA_LIT_CEILING = 0.92;
const float ARENA_LIT_FLOOR = 0.02;
vec3 arena_lamp(vec3 albedo, vec3 lamp, vec3 so_far) {
	vec3 colour = max(albedo, vec3(1e-4));
	vec3 room = max(vec3(ARENA_LIT_CEILING) - albedo * daylight, vec3(ARENA_LIT_FLOOR));
	// The sun is gathered in this pass too (except in the Compatibility
	// renderer's separate shadowed-sun pass): what it gives level ground is
	// not the lamps'.
	vec3 sunlit = encoded_sun_pass ? vec3(0.0) : max(daylight - ambient_light, vec3(0.0));
	vec3 taken = clamp(colour * (so_far - sunlit), vec3(0.0), room * 0.999);
	vec3 before = -room * log(1.0 - taken / room);
	vec3 after = room * (1.0 - exp(-(before + colour * lamp) / room));
	return max(after - taken, vec3(0.0)) / colour;
}

// `directional`: only the sun has that pass; lamps (effect lights) are lit
// in the base pass with the ambient light, in linear terms on every
// renderer. The texture's own brightness limits the daylight, which the
// painting already carries, but not a lamp: a fire or a spell is a light of
// its own, and a dark arena has no daylight headroom to spare, so clamping
// it there left the scenery as black as before. A lamp may add up to what
// the texture holds, rolled off by the daylight already there (arena_lamp).
// `so_far` is the light gathered for the surface so far (DIFFUSE_LIGHT).
vec3 arena_sun(vec3 light_color, float attenuation, vec3 normal, vec3 light_dir, vec3 albedo, bool directional, vec3 so_far) {
	vec3 sun = light_color / PI * attenuation * max(dot(normal, light_dir), 0.0);
	if (!directional) return arena_lamp(albedo, min(sun, vec3(light_limit)), so_far);
	sun = min(sun, max(vec3(light_limit) - ambient_light, vec3(0.0)));
	if (!encoded_sun_pass) return sun;
	vec3 base = clamp(albedo * ambient_light, 0.0, 1.0);
	vec3 lit = clamp(albedo * (ambient_light + sun), 0.0, 1.0);
	return arena_to_linear(arena_to_srgb(lit) - arena_to_srgb(base)) / max(albedo, vec3(0.0001));
}
