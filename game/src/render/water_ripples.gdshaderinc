vec3 ripple_corner(vec2 lattice, vec2 offset) {
	vec3 seed = fract(lattice.xyx * vec3(0.1031, 0.1030, 0.0973));
	seed += dot(seed, seed.yzx + 33.33);
	vec2 gradient = 2.0 * fract((seed.xx + seed.yz) * seed.zy) - 1.0;
	float falloff = max(0.5 - dot(offset, offset), 0.0);
	float falloff2 = falloff * falloff;
	float height = dot(gradient, offset);
	return falloff2 * falloff * vec3(falloff * height, falloff * gradient - 8.0 * height * offset);
}

// Simplex height and slope, with a different gradient at each vertex.
vec3 ripple_field(vec2 point) {
	const float SKEW = 0.3660254;
	const float UNSKEW = 0.2113249;
	vec2 lattice = floor(point + (point.x + point.y) * SKEW);
	vec2 offset = point - lattice + (lattice.x + lattice.y) * UNSKEW;
	vec2 step_to_corner = offset.x > offset.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	return 70.0 * (ripple_corner(lattice, offset)
		+ ripple_corner(lattice + step_to_corner, offset - step_to_corner + UNSKEW)
		+ ripple_corner(lattice + 1.0, offset - 1.0 + 2.0 * UNSKEW));
}

// Crest height, two slope components and the water's brightness variation.
vec4 water_ripples(vec2 point) {
	mat2 swell_basis = mat2(vec2(0.92, 0.39), vec2(-0.39, 0.92));
	mat2 chop_basis = mat2(vec2(0.61, -0.79), vec2(0.79, 0.61));
	vec2 swell_scale = vec2(0.44, 1.20);
	vec2 chop_scale = vec2(1.45, 3.20);
	vec3 swell = ripple_field((transpose(swell_basis) * point) * swell_scale + TIME * vec2(0.12, -0.38));
	vec3 chop = ripple_field((transpose(chop_basis) * point) * chop_scale + vec2(17.3, 8.9) + TIME * vec2(-0.33, 0.71));
	float crest_height = 0.70 * swell.x + 0.30 * chop.x;
	vec2 slope = 0.030 * (swell_basis * (swell.yz * swell_scale))
		+ 0.009 * (chop_basis * (chop.yz * chop_scale));
	return vec4(crest_height, slope, 0.08 * swell.x + 0.04 * chop.x);
}
