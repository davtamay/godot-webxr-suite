shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The hero sphere is lit by the WebXR light estimate through the scene's SH
// environment SKY (ambient + reflections) - like every other object - instead of
// self-emitting the SH. So it's genuinely grounded in the real room's light: its
// diffuse shade tracks the room's ambient, and metallic/glossy settings reflect
// the room. The XR panel tunes its PBR look.
instance uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
instance uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
instance uniform float material_roughness : hint_range(0.04, 1.0) = 0.5;
instance uniform float reflection_strength : hint_range(0.0, 1.0) = 0.5;


void fragment() {
	ALBEDO = base_color.rgb;
	METALLIC = material_metallic;
	ROUGHNESS = material_roughness;
	SPECULAR = reflection_strength;
}
