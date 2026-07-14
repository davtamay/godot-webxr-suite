shader_type spatial;
// Per-object SOFT occlusion (the real Meta/Unity technique, GL-safe for XR).
// The object fades to passthrough where the real world is in FRONT of it, with
// a smoothstep-feathered edge. Env depth (metres) is pushed onto this material
// by the depth bridge from the CPU sensor harvest; it's compared against the
// fragment's OWN view-space depth (a varying). NO scene DEPTH_TEXTURE needed
// (unavailable to fullscreen quads in XR, which is why the fullscreen approach
// failed). Two array layers = per eye; the projection picks the eye.
render_mode cull_back, depth_draw_opaque;

uniform sampler2DArray env_depth : filter_linear, hint_default_black;   // metres
uniform vec2 env_size = vec2(128.0, 96.0);
uniform float occ_enabled = 0.0;

// Keep the object looking like its old StandardMaterial3D (lit, with specular).
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
// Edge softness 0..1: drives both the neighbourhood spread and the depth feather
// (0 = crisp, 1 = very soft). Adjustable from the panel's Edge button.
uniform float softness : hint_range(0.0, 1.0) = 0.0;

varying float v_depth;   // this fragment's view-space depth (metres)

void vertex() {
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (occ_enabled > 0.5) {
		vec2 uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
		// Pick the eye's depth layer WITHOUT ViewIndex (which only exists under
		// USE_MULTIVIEW). Each eye's frustum is off-centre with an opposite
		// horizontal shift in the projection, so its sign identifies the eye.
		float layer = (PROJECTION_MATRIX[2].x < 0.0) ? 0.0 : 1.0;
		// Meta SOFT_OCCLUSION: average the occlusion over a small NEIGHBOURHOOD
		// (spatial coverage), giving a consistent feathered silhouette instead
		// of an edge that snaps to the low-res depth grid's cells. `softness`
		// scales the spread and the depth feather: smaller = sharper.
		vec2 texel = mix(0.15, 3.0, softness) / env_size;
		float margin = mix(0.006, 0.1, softness);
		float occ = 0.0;
		float total = 0.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				float rm = texture(env_depth, vec3(uv + vec2(float(dx), float(dy)) * texel, layer)).r;
				if (rm > 0.05) {
					total += 1.0;
					occ += 1.0 - smoothstep(-margin, margin, rm - v_depth);
				}
			}
		}
		if (total > 0.0) {
			ALPHA = clamp(1.0 - occ / total, 0.0, 1.0);
		}
	}
}
