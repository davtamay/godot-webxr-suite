shader_type spatial;
// Meta/Unity-style per-pixel SOFT occlusion, GL-safe. Env depth comes from an
// ImageTexture the depth bridge uploads from the CPU harvest (metres, no decode
// needed - sidesteps the broken engine GL depth-texture wrap). Scene depth uses
// hint_depth_texture with a MANUAL linearize (INV_PROJECTION_MATRIX does not
// compile on the GL Compatibility renderer). Sampling the env-depth NEIGHBOURHOOD
// and smoothstepping over a margin gives the feathered edge a mesh punch can't.
render_mode unshaded, blend_sub, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D env_depth : filter_linear, hint_default_black;   // metres
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform float near = 0.05;
uniform float far = 100.0;
// Soft transition half-width in metres: within +/- margin of the boundary the
// occlusion ramps 0..1 instead of a hard cut.
uniform float margin = 0.06;
uniform vec2 env_size = vec2(128.0, 96.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

void fragment() {
	// The XR view is bottom-up vs the depth grid's top-down rows.
	vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
	// Virtual scene depth, manual reverse-z-agnostic linearize.
	float d = texture(scene_depth, SCREEN_UV).r;
	float scene_m = near * far / (far - d * (far - near));

	vec2 texel = 1.0 / env_size;
	float occl = 0.0;
	float total = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			float rm = texture(env_depth, uv + vec2(float(dx), float(dy)) * texel).r;
			if (rm <= 0.05) {
				continue; // no depth data at this sample
			}
			total += 1.0;
			// Real clearly in front (rm - scene_m <= -margin) => 1; behind
			// (>= margin) => 0; feathered between.
			occl += 1.0 - smoothstep(-margin, margin, rm - scene_m);
		}
	}
	float a = (total > 0.0) ? occl / total : 0.0;
	if (a <= 0.001) {
		discard; // Virtual content is in front; leave it alone.
	}
	ALBEDO = vec3(1.0);
	ALPHA = a;
}
