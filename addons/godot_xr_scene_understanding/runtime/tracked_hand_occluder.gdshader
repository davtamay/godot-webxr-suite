shader_type spatial;
render_mode unshaded, shadow_to_opacity, shadows_disabled, cull_disabled, depth_draw_always;

// Android XR's smoothed environment depth is stable for rooms but does not
// reliably preserve close hand silhouettes. This material turns the shared
// tracked-hand mesh into an invisible early depth writer. In alpha-blended
// passthrough, shadow_to_opacity keeps the camera image visible while later
// virtual geometry behind the hand fails its depth test.
void vertex() {
	// Slightly cover tracking/mesh disagreement at finger edges.
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
