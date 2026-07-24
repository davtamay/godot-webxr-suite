shader_type spatial;

// Room geometry is rendered as an alpha subtraction mask. With an OpenXR
// alpha-blend environment this reveals passthrough wherever the physical mesh
// sits in front of virtual content. Winding varies between Meta Scene Models
// and Android XR reconstruction, so both faces participate.
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
}
