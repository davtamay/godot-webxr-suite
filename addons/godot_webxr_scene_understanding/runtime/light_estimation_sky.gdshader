shader_type sky;

// Reconstructs the real room's low-frequency lighting from WebXR's nine RGB
// spherical-harmonic coefficients and renders it as a Godot Sky. Godot then
// convolves this radiance into ambient irradiance AND uses it for specular
// reflections - so every object in the scene is lit by, and reflects, the real
// world, instead of a single directional light + one flat ambient colour.
//
// This is RAW radiance (Y-basis), NOT the cosine-convolved irradiance form used
// by the debug sphere material - Godot does the cosine convolution itself when it
// bakes the ambient from the sky. Coefficient axis order matches WebXR / the
// LightProbe path: linear band = (y, z, x).

uniform vec3 sh0 = vec3(0.0);
uniform vec3 sh1 = vec3(0.0);
uniform vec3 sh2 = vec3(0.0);
uniform vec3 sh3 = vec3(0.0);
uniform vec3 sh4 = vec3(0.0);
uniform vec3 sh5 = vec3(0.0);
uniform vec3 sh6 = vec3(0.0);
uniform vec3 sh7 = vec3(0.0);
uniform vec3 sh8 = vec3(0.0);
uniform float sky_energy : hint_range(0.0, 8.0) = 1.0;


vec3 sh_radiance(vec3 n) {
	return sh0 * 0.282095
		+ sh1 * (0.488603 * n.y)
		+ sh2 * (0.488603 * n.z)
		+ sh3 * (0.488603 * n.x)
		+ sh4 * (1.092548 * n.x * n.y)
		+ sh5 * (1.092548 * n.y * n.z)
		+ sh6 * (0.315392 * (3.0 * n.z * n.z - 1.0))
		+ sh7 * (1.092548 * n.x * n.z)
		+ sh8 * (0.546274 * (n.x * n.x - n.y * n.y));
}


void sky() {
	COLOR = max(sh_radiance(EYEDIR) * sky_energy, vec3(0.0));
}
