shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float edge_amplitudes[128];
uniform float depth = 110.0;
uniform float wavelength = 75.0;
uniform float wave_phase = 0.0;

float edge_amplitude(int edge, float along) {
	float sample_position = clamp(along, 0.0, 1.0) * 31.0;
	int sample_index = min(int(sample_position), 30);
	float weight = sample_position - float(sample_index);
	int base_index = edge * 32;
	float a = edge_amplitudes[base_index + max(sample_index - 1, 0)];
	float b = edge_amplitudes[base_index + sample_index];
	float c = edge_amplitudes[base_index + sample_index + 1];
	float d = edge_amplitudes[base_index + min(sample_index + 2, 31)];
	return max(0.0, 0.5 * ((2.0 * b) + (-a + c) * weight
		+ (2.0 * a - 5.0 * b + 4.0 * c - d) * weight * weight
		+ (-a + 3.0 * b - 3.0 * c + d) * weight * weight * weight));
}

// x/y are normal/tangent refraction; z is a transient water reflection.
vec3 surface_ripple(int edge, float distance_inward, float along, float edge_length) {
	float envelope = 1.0 - smoothstep(0.0, depth, distance_inward);
	float amplitude = edge_amplitude(edge, along / edge_length) * envelope * envelope;
	float normal_phase = distance_inward * TAU / wavelength;
	float tangent_phase = along * TAU / (wavelength * 2.4);
	float primary = normal_phase - wave_phase;
	float secondary = normal_phase * 1.7 - wave_phase * 1.3;
	float normal_wave = sin(primary) * 0.65 + sin(secondary) * cos(tangent_phase) * 0.35;
	float tangent_wave = cos(secondary) * sin(tangent_phase) * 0.3;
	float reflection = pow(max(0.0, cos(primary) * 0.6 + cos(secondary) * 0.4), 6.0);
	// The temporary crest makes the moving surface legible at the screen boundary.
	float crest_position = 3.0 + amplitude * 0.32 * (1.0 + sin(tangent_phase) * cos(wave_phase));
	float crest = exp(-pow((distance_inward - crest_position) / 2.2, 2.0));
	return vec3(normal_wave, tangent_wave, reflection * 0.006 + crest * 0.018) * amplitude;
}

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pixel_position = SCREEN_UV * viewport_size;
	vec2 far_distance = viewport_size - pixel_position;
	vec3 left_ripple = surface_ripple(0, pixel_position.x, pixel_position.y, viewport_size.y);
	vec3 right_ripple = surface_ripple(1, far_distance.x, pixel_position.y, viewport_size.y);
	vec3 top_ripple = surface_ripple(2, pixel_position.y, pixel_position.x, viewport_size.x);
	vec3 bottom_ripple = surface_ripple(3, far_distance.y, pixel_position.x, viewport_size.x);
	vec2 displacement = vec2(
		left_ripple.x - right_ripple.x + top_ripple.y + bottom_ripple.y,
		top_ripple.x - bottom_ripple.x + left_ripple.y + right_ripple.y
	);
	vec2 sample_uv = SCREEN_UV + displacement * SCREEN_PIXEL_SIZE;
	sample_uv = 1.0 - abs(1.0 - abs(sample_uv));
	sample_uv = clamp(sample_uv, SCREEN_PIXEL_SIZE * 0.5, 1.0 - SCREEN_PIXEL_SIZE * 0.5);
	vec4 screen_color = texture(screen_texture, sample_uv);
	float reflection = left_ripple.z + right_ripple.z + top_ripple.z + bottom_ripple.z;
	screen_color.rgb += vec3(0.55, 0.8, 1.0) * reflection;
	COLOR = screen_color;
}
