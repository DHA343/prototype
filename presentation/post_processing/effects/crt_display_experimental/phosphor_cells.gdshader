shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform int cell_sampling : hint_enum("Horizontal 4:1", "2x2:2") = 1;
uniform float triad_pitch : hint_range(2.0, 6.0, 0.1) = 2.5;
uniform int row_pitch : hint_range(1, 4, 1) = 3;
uniform int mask_pattern : hint_enum("Staggered RGB:0", "Staggered RGB (Row Pairs):1") = 0;
uniform float horizontal_gap : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform int gap_alignment : hint_enum("Pixel Boundary", "Pixel Center") = 0;
uniform float vertical_gap : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float brightness_compensation : hint_range(0.25, 6.0, 0.01) = 1.0;


#include "rgb_aperture.gdshaderinc"


vec2 cell_active_size() {
	// Keep the emitting area nonzero even for values assigned outside Inspector ranges.
	return max(vec2(triad_pitch, float(row_pitch))
		- max(vec2(horizontal_gap, vertical_gap), vec2(0.0)), vec2(0.001));
}


float cell_row_integral(float interval_top, float interval_height, float active_height) {
	float period = float(row_pitch);
	float margin = (period - active_height) * 0.5;
	float local_top = mod(interval_top, period);
	float local_bottom = local_top + interval_height;
	float top_integral = clamp(local_top - margin, 0.0, active_height);
	float bottom_integral = clamp(mod(local_bottom, period) - margin, 0.0, active_height)
		+ floor(local_bottom / period) * active_height;
	return bottom_integral - top_integral;
}


vec3 cell_emission(vec2 fragment_position, vec2 screen_uv, vec2 pixel_size) {
	vec2 active_size = cell_active_size();
	float row_offset = rgb_row_offset(
		fragment_position.y, triad_pitch, float(row_pitch), mask_pattern);
	vec2 pixel_corner = fragment_position - vec2(0.5);
	int horizontal_samples = cell_sampling == 2 ? 2 : 4;
	int vertical_samples = cell_sampling == 2 ? 2 : 1;
	vec2 interval_size = vec2(1.0 / float(horizontal_samples), 1.0 / float(vertical_samples));
	vec3 emission = vec3(0.0);
	for (int sample_y = 0; sample_y < vertical_samples; sample_y++) {
		float vertical_coverage = cell_row_integral(
			pixel_corner.y + float(sample_y) * interval_size.y, interval_size.y, active_size.y);
		for (int sample_x = 0; sample_x < horizontal_samples; sample_x++) {
			vec2 sample_offset = (vec2(float(sample_x), float(sample_y)) + vec2(0.5))
				* interval_size - vec2(0.5);
			vec3 screen_rgb = textureLod(screen_texture, screen_uv + sample_offset * pixel_size, 0.0).rgb;
			vec3 coverage = rgb_aperture_integral(
				pixel_corner.x + float(sample_x) * interval_size.x, interval_size.x, row_offset,
				triad_pitch, active_size.x, gap_alignment == 1 ? 0.5 : 0.0) * vertical_coverage;
			emission += screen_rgb * coverage;
		}
	}
	// Coverage includes the sample area. Normalize each channel's emitting occupancy.
	float normalization = 3.0 * triad_pitch * float(row_pitch) / (active_size.x * active_size.y);
	return emission * normalization;
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = screen_color.rgb;
	if (mask_strength > 0.0) {
		vec3 emission = cell_emission(FRAGCOORD.xy, SCREEN_UV, SCREEN_PIXEL_SIZE);
		output_rgb = mix(screen_color.rgb, emission, mask_strength);
	}
	// Strength changes cell contrast; the common gain also applies at zero strength.
	COLOR = vec4(output_rgb * brightness_compensation, screen_color.a);
}
