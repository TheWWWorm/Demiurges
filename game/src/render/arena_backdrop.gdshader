shader_type spatial;
render_mode unshaded, cull_disabled;
// Arena pieces painted on the backdrop's own sheet (distant valleys and mist
// around the field). They belong to the backdrop: unlit like it, and drawn at
// the far depth, so every other part of the scene, the backdrop ring
// included, stays in front of them and they only fill what lies behind.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Clip-space depth of the far plane in the Compatibility renderer (reversed
// depth over the -1..1 range: -1 is farthest), kept just inside it.
uniform float far_depth = -0.99999;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.w * far_depth;
}

void fragment() {
	vec4 base = texture(albedo_texture, UV);
	ALBEDO = base.rgb;
}
