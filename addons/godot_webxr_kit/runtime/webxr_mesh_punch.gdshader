shader_type spatial;
// Alpha punch for room-mesh occlusion in AR: drawn depth-tested in the
// transparent pass, it subtracts everything (color and alpha) wherever the
// real-world mesh is closer than rendered content, so those pixels return
// to (0,0,0,0) and the compositor shows passthrough.
render_mode unshaded, blend_sub, depth_draw_never, cull_back;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
