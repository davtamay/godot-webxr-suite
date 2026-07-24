shader_type spatial;
// Alpha punch for room-mesh occlusion in AR: drawn depth-tested in the
// transparent pass, it subtracts everything (color and alpha) wherever the
// real-world mesh is closer than rendered content, so those pixels return
// to (0,0,0,0) and the compositor shows passthrough.
// cull_disabled: scan-chunk winding differs per platform (Quest CCW,
// Android XR CW from inside a room) - back-face culling erases the punch
// exactly where it matters.
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
