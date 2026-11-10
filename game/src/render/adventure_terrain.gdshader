shader_type spatial;
// Lit only by the sun's shadow: the ground keeps its texture colour where the
// sun reaches it and darkens by `shadow_strength` in the silhouette shadows
// the original lays on the ground (the sun pass draws it then; without
// silhouettes, emission does); ambient light and highlights stay off.
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
uniform float shadow_strength = 0.0;
varying float shadow_weight;
uniform sampler2D tiles : source_color, filter_linear_mipmap, repeat_disable;
uniform int columns;
uniform float tile_side;
uniform float pitch;
uniform float tile_margin;
uniform vec2 atlas_size;
// Optional surface detail from the original painted texture. No geometry or
// extra assets; animated liquid tiles keep their original appearance.
uniform bool detail_enabled = false;
uniform vec3 detail_sun = vec3(0.6634, 0.6428, -0.3830);
// The optional water surface uses the original liquid masks for its shores.
uniform bool water_enabled = false;
uniform sampler2D water_weights : filter_linear, repeat_disable;
uniform vec2 water_atlas_size = vec2(1.0);
uniform bool water_reflection_enabled = false;
uniform sampler2D water_reflection : source_color, filter_linear, repeat_disable;
// World-space rectangles from active, authored EL2 rain particles.
uniform int water_rain_count = 0;
uniform vec4 water_rain_areas[64];
const float WATER_SIDE = 32.0;
const float WATER_PITCH = 34.0;
// Fog (ELFog) as the original's mist pass draws it: per map corner a mist
// opacity (unexplored 255, remembered 133, visible 0 of 255; a corner takes
// its most fogged tile), moving toward the new value at 150/255 a second
// (`fog_fade` is the change allowed since the masks last changed). The mist
// texture (ELFogMist) repeats every 20 tiles and drifts along the rows.
uniform bool fog_enabled = false;
uniform sampler2D fog_from : filter_linear, repeat_disable;
uniform sampler2D fog_to : filter_linear, repeat_disable;
uniform ivec2 fog_size = ivec2(1, 1);
uniform float fog_fade = 1.0;
uniform sampler2D fog_mist : filter_linear, repeat_enable;
uniform float fog_drift = 0.0;
const float MIST_SCALE = 0.05;
// Second-game colourless zones for the current level (ELAdventureTerrain.colorless_layer):
// per cell a grey index (0 colour, 1 grey, n >= 2 weight tile n - 2) and quarter turns.
uniform bool clrless_enabled = false;
uniform sampler2D clrless_cells : filter_nearest, repeat_disable;
uniform sampler2D clrless_weights : filter_linear, repeat_disable;
uniform int clrless_columns = 1;
uniform vec2 clrless_atlas = vec2(1.0);
uniform ivec2 clrless_size = ivec2(1, 1);
const float CLRLESS_SIDE = 32.0;
const float CLRLESS_PITCH = 34.0;
varying vec2 cell;

void vertex() {
	cell = vec2(VERTEX.x, -VERTEX.z) / 2.0;
	// The ground mesh is flat and carries no normals of its own.
	NORMAL = vec3(0.0, 1.0, 0.0);
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

#include "res://src/render/water_ripples.gdshaderinc"

vec2 rain_ring_slope(vec2 point) {
	float rain = 0.0;
	for (int i = 0; i < water_rain_count; i++) {
		vec4 area = water_rain_areas[i];
		vec2 inside = area.zw - abs(point - area.xy);
		rain = max(rain, smoothstep(0.0, 2.5, min(inside.x, inside.y)));
	}
	if (rain <= 0.0) return vec2(0.0);
	// The rings stay in world space as the original tile frames and UVs change.
	// A ring fits within reach of the four surrounding lattice points.
	vec2 grid = point * 1.18;
	vec2 base = floor(grid);
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 site = base + vec2(float(i % 2), float(i / 2));
		vec3 hash = fract(sin(vec3(dot(site, vec2(91.31, 57.61)), dot(site, vec2(74.17, 113.9)), dot(site, vec2(19.71, 81.7)))) * 27417.37);
		vec2 offset = grid - site - (hash.xy - 0.5) * 0.30;
		float distance = length(offset);
		float age = fract(TIME * 1.23 + hash.z);
		float radius = mix(0.03, 0.43, age);
		float band = (distance - radius) * 13.0;
		float envelope = (1.0 - smoothstep(0.5, 1.0, abs(band))) * smoothstep(0.0, 0.15, age) * (1.0 - age);
		slope += offset / max(distance, 0.001) * sin(band * 3.14159) * envelope;
	}
	return slope * rain;
}

vec3 water_surface(vec3 original, vec2 weights, vec3 view, vec2 screen_uv, mat3 view_basis, float ripple_fade, bool srgb) {
	float coverage = weights.r;
	float bog = clamp(weights.g / coverage, 0.0, 1.0);
	// Drift broad ripples and smaller chop in different directions through
	// world space. Both continue across the original terrain tile edges.
	vec2 point = cell * 2.0;
	vec4 ripple = water_ripples(point);
	float crest_height = ripple.x;
	float wind = ripple_fade * mix(1.0, 0.36, bog);
	vec2 slope = ripple.yz * wind;
	vec2 rain = vec2(0.0);
	if (water_rain_count > 0 && ripple_fade > 0.0 && coverage > 0.4) {
		rain = rain_ring_slope(point) * vec2(1.0, -1.0) * ripple_fade * smoothstep(0.4, 0.95, coverage) * 0.24;
	}
	slope += rain;
	vec3 normal = normalize(vec3(slope.x, 1.0, slope.y));
	vec3 sun = normalize(detail_sun);
	float grazing = 1.0 - clamp(dot(normal, view), 0.0, 1.0);
	// Clear water still reflects the sky from the map's steep default view.
	float fresnel = mix(0.075 + 0.24 * pow(grazing, 3.0), 0.18 * pow(grazing, 4.0), bog);
	// Bog's duckweed has no sun glint. Keep it on the water share of mixed tiles.
	float glint = pow(max(dot(normal, normalize(sun + view)), 0.0), 45.0) * ripple_fade * (1.0 - bog);
	float crest = smoothstep(0.12, 0.62, crest_height) * ripple_fade * (1.0 - bog);
	float shore = 4.0 * coverage * (1.0 - coverage);
	float foam = shore * smoothstep(0.04, 0.56, crest_height) * ripple_fade * (1.0 - bog);
	// Rain rings catch the sky even at steep view angles. Foam masks the reflection.
	fresnel += min(length(rain) * 0.6, 0.18) * (1.0 - foam);
	// Match the linear water lighting in both renderers. Compatibility
	// supplies the terrain sample in display space.
	vec3 base = srgb ? to_linear(original) : original;
	float sky_height = clamp(reflect(-view, normal).y, 0.0, 1.0);
	vec3 sky = to_linear(mix(vec3(0.63, 0.72, 0.77), vec3(0.39, 0.61, 0.80), sky_height));
	if (water_reflection_enabled && bog < 1.0) {
		vec2 offset = (view_basis * vec3(slope.x, 0.0, slope.y)).xy * 0.055;
		vec2 uv = vec2(1.0 - screen_uv.x, screen_uv.y) + offset;
		vec2 edge = min(uv, 1.0 - uv);
		vec4 mirror = texture(water_reflection, uv);
		float reflected = mirror.a * smoothstep(0.0, 0.025, min(edge.x, edge.y)) * (1.0 - bog);
		// The transparent viewport stores premultiplied edges.
		vec3 reflected_colour = clamp(mirror.rgb / max(mirror.a, 0.001), 0.0, 1.0);
		if (srgb) reflected_colour = to_linear(reflected_colour);
		sky = mix(sky, reflected_colour, reflected);
		fresnel = mix(fresnel, max(fresnel, 0.40), reflected);
	}
	vec3 sparkle = to_linear(vec3(0.66, 0.79, 0.85));
	float ring_light = dot(rain, sun.xz);
	vec3 shallows = to_linear(vec3(0.30, 0.46, 0.45));
	vec3 deep = to_linear(vec3(0.10, 0.21, 0.27));
	vec3 liquid = mix(shallows, deep, smoothstep(0.15, 1.0, coverage));
	// Only the bog's duckweed uses the painted colour within the water.
	liquid = mix(liquid, base, bog);
	vec3 waves = liquid * (1.0 + ripple.w * wind + ring_light);
	vec3 water = mix(waves, sky, fresnel) + sparkle * (0.14 * glint + 0.016 * crest + 0.15 * foam + 0.4 * max(ring_light, 0.0));
	vec3 enhanced = mix(base, water, coverage);
	return srgb ? to_srgb(enhanced) : enhanced;
}

void fragment() {
	// Rounded: a perspective view interpolates the per-cell constants with
	// small errors, and truncation would pick the neighbouring atlas tile.
	int frame = int(floor(TIME * 10.0)) % max(1, int(round(UV2.y)));
	int index = int(round(UV2.x)) + frame;
	vec2 start = vec2(float(index % columns), float(index / columns)) * pitch + vec2(tile_margin);
	vec2 tex_uv = (start + UV * tile_side) / atlas_size;
	// Filter fine ground detail as it recedes instead of sampling only the
	// full-resolution tiles. The four-texel gutter remains separate through
	// level two; coarser atlas levels would mix unrelated neighbouring tiles.
	vec2 footprint_x = dFdx(UV) * tile_side;
	vec2 footprint_y = dFdy(UV) * tile_side;
	float footprint = max(length(footprint_x), length(footprint_y));
	float terrain_lod = clamp(log2(max(footprint, 1.0)), 0.0, 2.0);
	ALBEDO = textureLod(tiles, tex_uv, terrain_lod).rgb;
	if (detail_enabled && int(round(UV2.y)) == 1) {
		vec2 dx = dFdx(UV);
		vec2 dy = dFdy(UV);
		float edge = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y)) * tile_side;
		// Fade before the source texels become too small, and at tile borders
		// where the atlas gutter cannot describe the neighbouring ground.
		float fade = (1.0 - smoothstep(1.25, 3.5, footprint)) * smoothstep(0.0, 2.0, edge);
		if (fade > 0.0) {
			vec2 px = 1.0 / atlas_size;
			vec3 left = textureLod(tiles, tex_uv - vec2(px.x, 0.0), terrain_lod).rgb;
			vec3 right = textureLod(tiles, tex_uv + vec2(px.x, 0.0), terrain_lod).rgb;
			vec3 down = textureLod(tiles, tex_uv - vec2(0.0, px.y), terrain_lod).rgb;
			vec3 up = textureLod(tiles, tex_uv + vec2(0.0, px.y), terrain_lod).rgb;
			vec3 weights = vec3(0.2126, 0.7152, 0.0722);
			vec2 slope = vec2(dot(right - left, weights), dot(up - down, weights));
			vec3 normal = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			vec3 p2 = cross(dFdy(VERTEX), normal);
			vec3 p1 = cross(normal, dFdx(VERTEX));
			vec3 tangent = p2 * dx.x + p1 * dy.x;
			vec3 bitangent = p2 * dx.y + p1 * dy.y;
			float scale = inversesqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-12));
			vec3 relief = normalize(normal - (tangent * slope.x + bitangent * slope.y) * scale * 1.4);
			vec3 sun = normalize((VIEW_MATRIX * vec4(detail_sun, 0.0)).xyz);
			float light = clamp(dot(relief - normal, sun) * 0.7, -0.08, 0.08);
			vec3 lo = min(ALBEDO, min(min(left, right), min(down, up)));
			vec3 hi = max(ALBEDO, max(max(left, right), max(down, up)));
			vec3 enhanced = clamp(ALBEDO + (ALBEDO - (left + right + down + up) * 0.25) * 0.3, lo, hi);
			ALBEDO = mix(ALBEDO, enhanced * (1.0 + light), fade);
		}
	}
	if (water_enabled) {
		vec2 water_start = vec2(float(index % columns), float(index / columns)) * WATER_PITCH + vec2(1.0);
		vec2 weights = texture(water_weights, (water_start + UV * WATER_SIDE) / water_atlas_size).rg;
		float ripple_fade = 1.0 - smoothstep(0.035, 0.19, length(dFdx(cell)) + length(dFdy(cell)));
		if (weights.r > 0.0) {
			ALBEDO = water_surface(ALBEDO, weights, mat3(INV_VIEW_MATRIX) * VIEW,
				SCREEN_UV, mat3(VIEW_MATRIX), ripple_fade, OUTPUT_IS_SRGB);
		}
	}
	if (clrless_enabled) {
		ivec2 at = clamp(ivec2(floor(cell)), ivec2(0), clrless_size - ivec2(1));
		vec4 grey = texelFetch(clrless_cells, at, 0);
		int kind = int(grey.r * 255.0 + 0.5) + int(grey.g * 255.0 + 0.5) * 256;
		if (kind > 0) {
			float weight = 1.0;
			if (kind > 1) {
				// The weight tile is stored in its canonical corner order; turn
				// the cell-local position the way the terrain mesh turns its UVs.
				vec2 local = clamp(cell - vec2(at), vec2(0.0), vec2(1.0));
				int turns = int(grey.b * 255.0 + 0.5);
				for (int i = 0; i < turns; i++) local = vec2(local.y, 1.0 - local.x);
				int tile = kind - 2;
				vec2 origin = vec2(float(tile % clrless_columns), float(tile / clrless_columns)) * CLRLESS_PITCH + vec2(1.0);
				weight = texture(clrless_weights, (origin + local * CLRLESS_SIDE) / clrless_atlas).r;
			}
			// Grey is the plain mean of the 8-bit colour channels.
			vec3 colour = OUTPUT_IS_SRGB ? ALBEDO : to_srgb(ALBEDO);
			colour = mix(colour, vec3((colour.r + colour.g + colour.b) / 3.0), weight);
			ALBEDO = OUTPUT_IS_SRGB ? colour : to_linear(colour);
		}
	}
	if (fog_enabled) {
		vec2 corner = (cell + vec2(0.5)) / vec2(fog_size + ivec2(1));
		float from = texture(fog_from, corner).r;
		float alpha = from + clamp(texture(fog_to, corner).r - from, -fog_fade, fog_fade);
		vec3 mist = texture(fog_mist, cell * MIST_SCALE + vec2(0.0, fog_drift)).rgb;
		// Blended in display space, as the original's alpha blend.
		vec3 shown = mix(OUTPUT_IS_SRGB ? ALBEDO : to_srgb(ALBEDO), mist, alpha);
		ALBEDO = OUTPUT_IS_SRGB ? shown : to_linear(shown);
		// The mist is drawn over the shadows.
		shadow_weight = shadow_strength * (1.0 - alpha);
	} else {
		shadow_weight = shadow_strength;
	}
	// Up, whichever side of the double-sided ground mesh is drawn.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// With silhouettes on, the shadowed sun gives the whole colour in its own
	// pass: splitting it between this pass and the sun's (added together after
	// display encoding by the compatibility renderer) would brighten the ground.
	EMISSION = shadow_strength > 0.0 ? vec3(0.0) : ALBEDO;
}

void light() {
	// The original darkens the ground by shadow_strength as shown on screen;
	// this light is linear, so the shown factor is decoded from display space.
	if (LIGHT_IS_DIRECTIONAL && shadow_strength > 0.0) DIFFUSE_LIGHT += vec3(pow(1.0 - shadow_weight + shadow_weight * ATTENUATION, 2.2));
}
