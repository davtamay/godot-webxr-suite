shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// WebXR supplies nine RGB spherical-harmonic coefficients. Keeping each one
// explicit makes runtime updates dependable across Godot's GL and WebGPU
// shader backends while still evaluating the complete low-frequency field.
uniform vec3 sh0 = vec3(0.70);
uniform vec3 sh1 = vec3(0.0);
uniform vec3 sh2 = vec3(0.0);
uniform vec3 sh3 = vec3(0.0);
uniform vec3 sh4 = vec3(0.0);
uniform vec3 sh5 = vec3(0.0);
uniform vec3 sh6 = vec3(0.0);
uniform vec3 sh7 = vec3(0.0);
uniform vec3 sh8 = vec3(0.0);
instance uniform float sh_gain : hint_range(0.0, 4.0) = 1.0;

instance uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
instance uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
instance uniform float material_roughness : hint_range(0.04, 1.0) = 0.5;
instance uniform float reflection_strength : hint_range(0.0, 1.0) = 0.5;


vec3 evaluate_spherical_harmonics(vec3 n) {
	// Cosine-convolved irradiance evaluation, matching the LightProbe path
	// used by the reference Three.js WebXR sample rather than treating the
	// coefficients as a raw environment lookup.
	return
		sh0 * 0.886227 +
		sh1 * (1.023328 * n.y) +
		sh2 * (1.023328 * n.z) +
		sh3 * (1.023328 * n.x) +
		sh4 * (0.858086 * n.x * n.y) +
		sh5 * (0.858086 * n.y * n.z) +
		sh6 * (0.743125 * n.z * n.z - 0.247708) +
		sh7 * (0.858086 * n.x * n.z) +
		sh8 * (0.429043 * (n.x * n.x - n.y * n.y));
}


void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = base_color.rgb;
	METALLIC = material_metallic;
	ROUGHNESS = material_roughness;
	SPECULAR = reflection_strength;
	EMISSION = max(evaluate_spherical_harmonics(world_normal) * sh_gain, vec3(0.0));
}
