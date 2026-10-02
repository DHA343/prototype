// Shared output-pixel geometry for both RGB row layouts.
float rgb_row_offset(
	float output_y, float pitch, float row_height, int pattern_kind, int offset_mode
) {
	if (offset_mode == 0) {
		return 0.0;
	}
	float cell_row = floor(output_y / row_height);
	float phase_row = pattern_kind == 1 ? floor(cell_row * 0.5) : cell_row;
	float half_period = pitch * 0.5;
	float offset_width = offset_mode == 2 ? floor(half_period) : half_period;
	return mod(phase_row, 2.0) * offset_width;
}


vec3 rgb_aperture_integral(
	float interval_left, float interval_width, float row_offset,
	float pitch, float active_width, float alignment_offset
) {
	float channel_width = active_width / 3.0;
	float margin = (pitch - active_width) * 0.5;
	vec3 channel_start = vec3(margin) + vec3(0.0, channel_width, 2.0 * channel_width);
	// A local period avoids subtracting large cumulative integrals at screen edges.
	float local_left = mod(interval_left - row_offset - alignment_offset, pitch);
	float local_right = local_left + interval_width;
	vec3 left_integral = clamp(vec3(local_left) - channel_start, vec3(0.0), vec3(channel_width));
	vec3 right_integral = clamp(vec3(mod(local_right, pitch)) - channel_start,
		vec3(0.0), vec3(channel_width))
		+ vec3(floor(local_right / pitch) * channel_width);
	return right_integral - left_integral;
}
