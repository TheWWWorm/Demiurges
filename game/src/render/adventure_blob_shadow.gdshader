shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D mask_texture : filter_linear_mipmap, repeat_disable;
varying flat float opacity;

void vertex() {
	opacity = INSTANCE_CUSTOM.x;
}

void fragment() {
	float alpha = texture(mask_texture, UV).a * opacity;
	ALBEDO = vec3(0.0);
	// The original blends black over the ground in display space.
	ALPHA = OUTPUT_IS_SRGB ? alpha : 1.0 - pow(1.0 - alpha, 2.2);
}
