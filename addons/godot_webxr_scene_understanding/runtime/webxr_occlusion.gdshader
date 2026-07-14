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
// Depth-camera projection terms P10/P14. When non-zero the raw value is a
// device depth-buffer sample that must be linearized (the mode-5 formula the
// CPU mesh path proved on Quest); zero => the value is already linear meters.
uniform vec2 depth_pm = vec2(0.0);
// Maps a normalized view coordinate to the depth texture's UV
// (normDepthBufferFromNormView); identity on renderers that pass no transform.
uniform mat4 depth_uv_transform = mat4(1.0);
// Soft edges: sample the sensor depth over a neighborhood and blend the
// occlusion (Meta's SOFT_OCCLUSION). Off = crisp binary punch (HARD).
uniform bool soft_edges = false;

// Linearize one raw sensor sample to metres: a device depth-buffer value via
// the projection terms (Quest), or an already-linear value scaled.
float sensor_metres(float raw) {
	if (abs(depth_pm.y) > 0.0) {
		float denom = 2.0 * raw - 1.0 + depth_pm.x;
		return (abs(denom) < 0.0001) ? -1.0 : abs(depth_pm.y / denom);
	}
	return raw * raw_to_meters;
}

void vertex() {
	// Fullscreen triangle in clip space (mesh provides a 2-triangle quad
	// with UV-covering vertices in [-1, 1]).
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

void fragment() {
	if (occlusion_enabled < 0.5) {
		discard;
	}
	vec2 depth_uv = (depth_uv_transform * vec4(SCREEN_UV, 0.0, 1.0)).xy;

	// Reconstruct the scene fragment's view-space distance from the depth
	// buffer (reverse-z aware via the inverse projection).
	float scene_ndc = texture(scene_depth, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_ndc, 1.0);
	float scene_m = -view_pos.z / view_pos.w;

	float occlude;
	if (!soft_edges) {
		// HARD: one sample, binary. real closer than virtual => punch.
		float real_m = sensor_metres(texture(depth_map, depth_uv).r);
		if (real_m <= 0.0) {
			discard;
		}
		occlude = (real_m + 0.02 < scene_m) ? 1.0 : 0.0;
	} else {
		// SOFT: fraction of a neighbourhood whose real depth is in front of
		// the virtual pixel, giving a gradual boundary (Meta SOFT_OCCLUSION).
		vec2 texel = 1.0 / vec2(textureSize(depth_map, 0));
		float hits = 0.0;
		float total = 0.0;
		for (int dy = -2; dy <= 2; dy++) {
			for (int dx = -2; dx <= 2; dx++) {
				float real_m = sensor_metres(texture(depth_map, depth_uv + vec2(float(dx), float(dy)) * texel).r);
				if (real_m <= 0.0) {
					continue;
				}
				total += 1.0;
				hits += (real_m + 0.02 < scene_m) ? 1.0 : 0.0;
			}
		}
		occlude = (total > 0.0) ? smoothstep(0.0, 1.0, hits / total) : 0.0;
	}

	if (occlude <= 0.0) {
		discard; // Virtual content is in front; leave it alone.
	}
	// Real world is closer: subtract to reveal passthrough (soft = partial).
	ALBEDO = vec3(1.0);
	ALPHA = occlude;
}
