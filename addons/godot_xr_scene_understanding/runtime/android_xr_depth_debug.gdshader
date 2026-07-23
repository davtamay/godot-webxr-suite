shader_type spatial;
render_mode unshaded, world_vertex_coords, shadows_disabled, cull_disabled, depth_draw_always;

// Populated every frame by OpenXRAndroidEnvironmentDepthExtension.
global uniform bool ANDROID_ENVIRONMENT_DEPTH_AVAILABLE;
global uniform highp sampler2DArray ANDROID_ENVIRONMENT_DEPTH_TEXTURE : filter_nearest, repeat_disable, hint_default_black;
global uniform int ANDROID_ENVIRONMENT_DEPTH_RESOLUTION;
global uniform highp vec4 ANDROID_ENVIRONMENT_DEPTH_TANFOV_LEFT;
global uniform highp vec4 ANDROID_ENVIRONMENT_DEPTH_TANFOV_RIGHT;
global uniform highp mat4 ANDROID_ENVIRONMENT_DEPTH_CAMERA_TO_WORLD_LEFT;
global uniform highp mat4 ANDROID_ENVIRONMENT_DEPTH_CAMERA_TO_WORLD_RIGHT;

void vertex() {
	highp vec4 tanfov = (
		VIEW_INDEX == VIEW_MONO_LEFT
		? ANDROID_ENVIRONMENT_DEPTH_TANFOV_LEFT
		: ANDROID_ENVIRONMENT_DEPTH_TANFOV_RIGHT
	);
	highp mat4 depth_to_world = (
		VIEW_INDEX == VIEW_MONO_LEFT
		? ANDROID_ENVIRONMENT_DEPTH_CAMERA_TO_WORLD_LEFT
		: ANDROID_ENVIRONMENT_DEPTH_CAMERA_TO_WORLD_RIGHT
	);
	highp float resolution = float(ANDROID_ENVIRONMENT_DEPTH_RESOLUTION);
	highp vec2 uv = vec2(
		(float(VERTEX_ID % ANDROID_ENVIRONMENT_DEPTH_RESOLUTION) + 0.5) / resolution,
		(float(VERTEX_ID / ANDROID_ENVIRONMENT_DEPTH_RESOLUTION) + 0.5) / resolution
	);

	// Android XR depth images have their origin at the top left.
	highp vec2 depth_uv = vec2(uv.x, 1.0 - uv.y);
	highp float depth = texture(
		ANDROID_ENVIRONMENT_DEPTH_TEXTURE,
		vec3(depth_uv, float(VIEW_INDEX))
	).x;

	// Reproject each depth texel from the depth camera into play-space.
	highp vec3 depth_pose = depth * vec3(
		mix(tanfov.xz, tanfov.yw, uv),
		-1.0
	);
	VERTEX = (depth_to_world * vec4(depth_pose, 1.0)).xyz;
	// The Android XR feed is deliberately low resolution. Twelve-pixel points
	// fill its texel grid without turning neighboring samples into large tiles.
	POINT_SIZE = 12.0;
}

void fragment() {
	if (!ANDROID_ENVIRONMENT_DEPTH_AVAILABLE) {
		discard;
	}

	highp vec4 camera_clip = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	if (camera_clip.w <= 0.1) {
		discard;
	}

	highp float camera_ndc_z = camera_clip.z / camera_clip.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = camera_ndc_z * 0.5 + 0.5;
#else
	DEPTH = camera_ndc_z;
#endif

	// Use a continuous range tint. Repeating bands made the low-resolution
	// surface look like an artificial wavy texture rather than sensor data.
	highp float meters = abs(camera_clip.w);
	highp float distance_mix = smoothstep(0.2, 5.0, meters);
	vec3 scan_color = mix(
		vec3(0.05, 0.95, 1.0),
		vec3(0.015, 0.12, 0.55),
		distance_mix
	);
	ALBEDO = scan_color;
	EMISSION = scan_color * 0.55;
}
