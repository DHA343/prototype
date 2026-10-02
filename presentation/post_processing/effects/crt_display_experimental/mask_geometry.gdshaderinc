// Output-pixel coverage shared by Redistribution and Cell Emission.
float mask_row_offset(float output_y, float pitch, float height, int pattern_kind) {
	return pattern_kind == 0 ? mod(floor(output_y / height), 2.0) * pitch * 0.5 : 0.0;
}


float mask_occupancy(int pattern_kind) {
	return pattern_kind == 2 ? 0.5 : 1.0 / 3.0;
}


vec3 mask_aperture_integral(
	float interval_left, float interval_width, float row_offset,
	float pitch, int pattern_kind, float alignment_offset
) {
	float channel_width = pitch / (pattern_kind == 2 ? 2.0 : 3.0);
	vec3 channel_start = pattern_kind == 2
		? vec3(channel_width, 0.0, channel_width) : vec3(0.0, channel_width, 2.0 * channel_width);
	// Local periods avoid cancellation of large cumulative integrals at screen edges.
	float local_left = mod(interval_left - row_offset - alignment_offset, pitch);
	float local_right = local_left + interval_width;
	vec3 left_integral = clamp(vec3(local_left) - channel_start, vec3(0.0), vec3(channel_width));
	vec3 right_integral = clamp(vec3(mod(local_right, pitch)) - channel_start,
		vec3(0.0), vec3(channel_width))
		+ vec3(floor(local_right / pitch) * channel_width);
	return right_integral - left_integral;
}
