// Unshaded palette colours use display encoding in Compatibility and
// linear encoding in the forward renderers. Apply light changes in linear
// terms in both, without baking the arena's ordinary light into its art.
uniform vec3 scene_light_gain = vec3(1.0);

vec3 arena_atmosphere_light(vec3 colour) {
	vec3 gain = clamp(scene_light_gain, vec3(0.0), vec3(2.0));
	if (OUTPUT_IS_SRGB) {
		vec3 c = max(colour, vec3(0.0));
		vec3 linear = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
		linear *= gain;
		return mix(linear * 12.92, 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), linear));
	}
	return colour * gain;
}
