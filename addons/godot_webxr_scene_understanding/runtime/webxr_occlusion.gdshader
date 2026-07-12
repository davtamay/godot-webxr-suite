shader_type spatial;
// Real-world occlusion punch for AR (experimental): drawn last over the
// whole view, it compares the rendered scene depth against the headset's
// depth-sensing map and, where the real world is closer, subtracts the
// layer's alpha so passthrough shows through the virtual object.
render_mode unshaded, blend_sub, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D depth_map : filter_nearest, hint_default_black;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform float raw_to_meters = 1.0;
uniform float occlusion_enabled = 0.0;

void vertex() {
	// Fullscreen triangle in clip space (mesh provides a 2-triangle quad
	// with UV-covering vertices in [-1, 1]).
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

void fragment() {
	if (occlusion_enabled < 0.5) {
		discard;
	}
	float raw = texture(depth_map, SCREEN_UV).r;
	if (raw <= 0.0) {
		discard;
	}
	float real_m = raw * raw_to_meters;

	// Reconstruct the scene fragment's view-space distance from the depth
	// buffer (reverse-z aware via the inverse projection).
	float scene_ndc = texture(scene_depth, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_ndc, 1.0);
	float scene_m = -view_pos.z / view_pos.w;

	if (real_m + 0.02 >= scene_m) {
		discard; // Virtual content is in front; leave it alone.
	}
	// Real world is closer: subtract the pixel to reveal passthrough.
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
