shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, depth_draw_always;

// Populated every frame by OpenXRMetaEnvironmentDepthExtension.
global uniform highp sampler2DArray META_ENVIRONMENT_DEPTH_TEXTURE : filter_nearest, repeat_disable, hint_default_black;
global uniform highp mat4 META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_LEFT;
global uniform highp mat4 META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_RIGHT;
global uniform highp mat4 META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_LEFT;
global uniform highp mat4 META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_RIGHT;

void vertex() {
	UV = VERTEX.xy * 0.5 + 0.5;
	POSITION = vec4(VERTEX.xyz, 1.0);
}

void fragment() {
	highp mat4 camera_to_depth_proj = (
		VIEW_INDEX == VIEW_MONO_LEFT
		? META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_LEFT
		: META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_RIGHT
	);
	highp mat4 depth_to_camera_proj = (
		VIEW_INDEX == VIEW_MONO_LEFT
		? META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_LEFT
		: META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_RIGHT
	);
	highp vec4 clip = vec4(UV * 2.0 - 1.0, 1.0, 1.0);
	highp vec4 reprojected = camera_to_depth_proj * clip;
	reprojected /= reprojected.w;
	highp vec2 depth_uv = reprojected.xy * 0.5 + 0.5;
	if (
		depth_uv.x < 0.0 || depth_uv.y < 0.0
		|| depth_uv.x > 1.0 || depth_uv.y > 1.0
	) {
		discard;
	}

	highp float depth = texture(
		META_ENVIRONMENT_DEPTH_TEXTURE,
		vec3(depth_uv, float(VIEW_INDEX))
	).r;
	if (depth == 0.0) {
		discard;
	}

	highp vec4 camera_clip = depth_to_camera_proj * vec4(
		reprojected.xy,
		depth * 2.0 - 1.0,
		1.0
	);
	highp float camera_ndc_z = camera_clip.z / camera_clip.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = 1.0 - (camera_ndc_z * 0.5 + 0.5);
#else
	DEPTH = camera_ndc_z;
#endif

	// Cyan range bands make the live sensor surface readable in-headset.
	highp float meters = abs(camera_clip.w);
	highp float bands = 0.5 + 0.5 * sin(meters * 18.0);
	vec3 scan_color = mix(
		vec3(0.015, 0.16, 0.42),
		vec3(0.05, 0.95, 1.0),
		bands
	);
	ALBEDO = scan_color;
	EMISSION = scan_color * 0.75;
}
