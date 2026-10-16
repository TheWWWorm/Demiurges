shader_type canvas_item;
// One ether-mist texel (ELFogMist): both frames are composed from their four
// grids (R: 8-texel cells, G: 4, B: 2, A: 1), cross-faded by `weight`/256 and
// coloured through the palette.
uniform sampler2D grids_from : filter_nearest, repeat_enable;
uniform sampler2D grids_to : filter_nearest, repeat_enable;
uniform sampler2D palette : filter_nearest;
uniform int weight = 1;

int cell(sampler2D grids, int index, int channel) {
	vec4 texel = texelFetch(grids, ivec2(index & 31, (index >> 5) & 31), 0);
	return int(texel[channel] * 255.0 + 0.5);
}

// Bilinear over `side`-texel cells of one grid; the right neighbour wraps
// within its row and the lower one over the whole grid.
int layer(sampler2D grids, int channel, int x, int y, int side, int shift) {
	int index = ((x >> shift) & 31) + ((y >> shift) & 31) * 32;
	int right = ((index + 1) & 31) != 0 ? index + 1 : index - 31;
	int fx = x & (side - 1);
	int fy = y & (side - 1);
	int top = cell(grids, right & 1023, channel) * fx + cell(grids, index, channel) * (side - fx);
	int bottom = cell(grids, (right + 32) & 1023, channel) * fx + cell(grids, (index + 32) & 1023, channel) * (side - fx);
	return bottom * fy + top * (side - fy);
}

int frame(sampler2D grids, int x, int y) {
	int value = (layer(grids, 0, x, y, 8, 3) - 7168 + layer(grids, 1, x, y, 4, 2) * 2
		+ (layer(grids, 2, x, y, 2, 1) + cell(grids, (x & 31) + (y & 31) * 32, 3) * 2) * 4) >> 6;
	return min(value, 255) & 255;
}

void fragment() {
	int x = int(FRAGCOORD.x);
	int y = int(FRAGCOORD.y);
	int value = (frame(grids_to, x, y) * weight + frame(grids_from, x, y) * (256 - weight)) >> 8;
	COLOR = vec4(texelFetch(palette, ivec2(value, 0), 0).rgb, 1.0);
}
