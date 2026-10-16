shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tiles : source_color, filter_linear, repeat_disable;
uniform int columns;
uniform float tile_side;
uniform float pitch;
uniform vec2 atlas_size;
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
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	int frame = int(floor(TIME * 10.0)) % max(1, int(UV2.y));
	int index = int(UV2.x) + frame;
	vec2 start = vec2(float(index % columns), float(index / columns)) * pitch + vec2(2.0);
	ALBEDO = texture(tiles, (start + UV * tile_side) / atlas_size).rgb;
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
	}
}
