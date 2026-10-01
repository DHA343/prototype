shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform int mask_style : hint_enum("Stretched VGA Phosphor:7", "VGA Phosphor:8") = 7;
uniform int cell_sampling : hint_enum("Reference", "Integrated", "Substrate") = 1;
uniform int cell_scale : hint_range(1, 4, 1) = 1;
uniform float triad_pitch : hint_range(2.0, 6.0, 0.1) = 2.5;
uniform int integration_samples = 2;
uniform int row_pitch : hint_range(2, 3, 1) = 3;
uniform float horizontal_fill : hint_range(0.75, 1.0, 0.01) = 0.90;
uniform float vertical_fill : hint_range(0.75, 1.0, 0.01) = 0.85;
uniform float phosphor_brightness : hint_range(0.5, 3.0, 0.1) = 1.0;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;


float cell_axis_profile(int local_pixel, int cell_size, float edge_weight) {
	return (local_pixel == 0 || local_pixel == cell_size - 1) ? edge_weight : 1.0;
}


vec3 reference_emission(vec3 screen_rgb, vec2 fragment_position) {
	ivec2 pixel_position = ivec2(floor(fragment_position));
	int subpixel_pitch = 2 * cell_scale;
	int reference_row_pitch = 2 * cell_scale;
	int triad_width = 3 * subpixel_pitch;
	int phosphor_row = pixel_position.y / reference_row_pitch;
	int phase_row = mask_style == 8 ? phosphor_row / 2 : phosphor_row;
	int row_offset = (phase_row % 2) * (triad_width / 2);
	int shifted_column = pixel_position.x - row_offset;
	int triad_column = int(mod(float(shifted_column), float(triad_width)));
	int phosphor_index = triad_column / subpixel_pitch;
	int local_column = triad_column % subpixel_pitch;
	int local_row = pixel_position.y % reference_row_pitch;
	float edge_weight = cell_scale == 1 ? 0.9 : 0.8;
	float cell_profile = cell_axis_profile(local_column, subpixel_pitch, edge_weight)
		* cell_axis_profile(local_row, reference_row_pitch, edge_weight);
	float horizontal_average = 1.0 - 2.0 * (1.0 - edge_weight) / float(subpixel_pitch);
	float vertical_average = 1.0 - 2.0 * (1.0 - edge_weight) / float(reference_row_pitch);
	// Each channel occupies one third of the triad. Normalize the discrete profile too.
	float normalization = 3.0 / (horizontal_average * vertical_average);
	vec3 emission = vec3(0.0);
	emission[phosphor_index] = screen_rgb[phosphor_index] * cell_profile
		* normalization * phosphor_brightness * brightness_compensation;
	return emission;
}


vec3 aperture_integral(float interval_left, float interval_width, float row_offset) {
	float channel_width = triad_pitch / 3.0;
	vec3 channel_start = vec3(0.0, channel_width, 2.0 * channel_width);
	// Work within one period to avoid subtracting large cumulative integrals at screen edges.
	float local_left = mod(interval_left - row_offset, triad_pitch);
	float local_right = local_left + interval_width;
	vec3 left_integral = clamp(vec3(local_left) - channel_start, vec3(0.0), vec3(channel_width));
	vec3 right_integral = clamp(vec3(mod(local_right, triad_pitch)) - channel_start,
		vec3(0.0), vec3(channel_width))
		+ vec3(floor(local_right / triad_pitch) * channel_width);
	return right_integral - left_integral;
}


vec3 integrated_emission(vec2 fragment_position, vec2 screen_uv, vec2 pixel_size) {
	int cell_row = int(floor(fragment_position.y / 2.0));
	int phase_row = mask_style == 8 ? cell_row / 2 : cell_row;
	float row_offset = float(phase_row % 2) * triad_pitch * 0.5;
	float interval_width = 1.0 / float(integration_samples);
	float pixel_left = fragment_position.x - 0.5;
	vec3 emission = vec3(0.0);
	for (int sample_index = 0; sample_index < integration_samples; sample_index++) {
		float sample_offset = (float(sample_index) + 0.5) * interval_width - 0.5;
		vec2 sample_uv = screen_uv + vec2(sample_offset * pixel_size.x, 0.0);
		vec3 screen_rgb = textureLod(screen_texture, sample_uv, 0.0).rgb;
		vec3 coverage = aperture_integral(
			pixel_left + float(sample_index) * interval_width, interval_width, row_offset);
		emission += screen_rgb * coverage;
	}
	// Coverage already contains the subinterval width; do not divide by the sample count again.
	return emission * 3.0 * phosphor_brightness * brightness_compensation;
}


vec3 substrate_aperture_integral(float interval_left, float row_offset) {
	float active_width = triad_pitch * horizontal_fill;
	float channel_width = active_width / 3.0;
	float margin = (triad_pitch - active_width) * 0.5;
	vec3 channel_start = vec3(margin) + vec3(0.0, channel_width, 2.0 * channel_width);
	float local_left = mod(interval_left - row_offset, triad_pitch);
	float local_right = local_left + 0.5;
	vec3 left_integral = clamp(vec3(local_left) - channel_start, vec3(0.0), vec3(channel_width));
	vec3 right_integral = clamp(vec3(mod(local_right, triad_pitch)) - channel_start,
		vec3(0.0), vec3(channel_width))
		+ vec3(floor(local_right / triad_pitch) * channel_width);
	return right_integral - left_integral;
}


float substrate_row_integral(float interval_top) {
	float period = float(row_pitch);
	float active_height = period * vertical_fill;
	float margin = (period - active_height) * 0.5;
	float local_top = mod(interval_top, period);
	float local_bottom = local_top + 0.5;
	float top_integral = clamp(local_top - margin, 0.0, active_height);
	float bottom_integral = clamp(mod(local_bottom, period) - margin, 0.0, active_height)
		+ floor(local_bottom / period) * active_height;
	return bottom_integral - top_integral;
}


vec3 substrate_emission(vec2 fragment_position, vec2 screen_uv, vec2 pixel_size) {
	int cell_row = int(floor(fragment_position.y / float(row_pitch)));
	int phase_row = mask_style == 8 ? cell_row / 2 : cell_row;
	float row_offset = float(phase_row % 2) * triad_pitch * 0.5;
	vec2 pixel_corner = fragment_position - vec2(0.5);
	vec3 emission = vec3(0.0);
	for (int sample_y = 0; sample_y < 2; sample_y++) {
		float vertical_coverage = substrate_row_integral(pixel_corner.y + float(sample_y) * 0.5);
		for (int sample_x = 0; sample_x < 2; sample_x++) {
			vec2 sample_offset = (vec2(float(sample_x), float(sample_y)) + vec2(0.5))
				* 0.5 - vec2(0.5);
			vec3 screen_rgb = textureLod(screen_texture, screen_uv + sample_offset * pixel_size, 0.0).rgb;
			vec3 coverage = substrate_aperture_integral(
				pixel_corner.x + float(sample_x) * 0.5, row_offset) * vertical_coverage;
			emission += screen_rgb * coverage;
		}
	}
	// Every channel has the same emitting area. Coverage already includes sample area.
	float normalization = 3.0 / (horizontal_fill * vertical_fill);
	return emission * normalization * phosphor_brightness * brightness_compensation;
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 emission;
	if (cell_sampling == 0) {
		emission = reference_emission(screen_color.rgb, FRAGCOORD.xy);
	} else if (cell_sampling == 1) {
		emission = integrated_emission(FRAGCOORD.xy, SCREEN_UV, SCREEN_PIXEL_SIZE);
	} else {
		emission = substrate_emission(FRAGCOORD.xy, SCREEN_UV, SCREEN_PIXEL_SIZE);
	}
	COLOR = vec4(emission, screen_color.a);
}
