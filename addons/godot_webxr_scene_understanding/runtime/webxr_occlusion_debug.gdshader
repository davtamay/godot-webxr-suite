shader_type spatial;
// Full-FOV diagnostic for the soft-occlusion COMPARE. Normal blending (paints
// the whole view). Three horizontal bands (note: the XR view is Y-flipped, so
// on-device the TOP band appears at the BOTTOM):
//   TOP    = scene depth / 4 (virtual): passthrough should be BRIGHT (far),
//            virtual objects DARK (near). All-dark => linearize wrong.
//   MIDDLE = env depth / 4 (real room): should show room/hand structure.
//   BOTTOM = occlusion factor: BRIGHT where real is in front of virtual.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D env_depth : filter_linear, hint_default_black;   // metres
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform float near = 0.05;
uniform float far = 1000.0;
uniform float margin = 0.06;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

void fragment() {
	vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	float d = texture(scene_depth, SCREEN_UV).r;
	float scene_m = near * far / (far - d * (far - near));
	float rm = texture(env_depth, uv).r;

	vec3 col;
	if (SCREEN_UV.y < 0.3333) {
		col = vec3(clamp(scene_m / 4.0, 0.0, 1.0));
	} else if (SCREEN_UV.y < 0.6666) {
		col = vec3(clamp(rm / 4.0, 0.0, 1.0));
	} else {
		float occl = (rm > 0.05) ? (1.0 - smoothstep(-margin, margin, rm - scene_m)) : 0.0;
		col = vec3(0.0, occl, 0.0);   // green where real occludes virtual
	}
	if (abs(SCREEN_UV.y - 0.3333) < 0.004 || abs(SCREEN_UV.y - 0.6666) < 0.004) {
		col = vec3(0.0, 1.0, 1.0);
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
