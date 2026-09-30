// Independent of the legacy mask's luminance preservation and Gap styles.
vec3 apply_phosphor_cells(vec3 input_rgb, vec2 fragcoord, float viewport_height, bool paired_rows) {
	const int PHOSPHOR_WIDTH = 2;
	const int SEPARATOR_WIDTH = 1;
	const int CELL_WIDTH = PHOSPHOR_WIDTH + SEPARATOR_WIDTH;
	const int TRIAD_WIDTH = 3 * CELL_WIDTH;
	// A 9px triad has a 4.5px half-period. Use 4px to keep every edge on an integer pixel.
	const int ROW_STAGGER = TRIAD_WIDTH / 2;
	float cell_scale = max(1.0, floor(viewport_height / 1080.0 + 0.5));
	ivec2 cell_position = ivec2(floor(fragcoord / cell_scale));
	int phase_row = paired_rows ? cell_position.y / 2 : cell_position.y;
	int row_offset = (phase_row % 2) * ROW_STAGGER;
	int triad_position = (cell_position.x + TRIAD_WIDTH - row_offset) % TRIAD_WIDTH;
	int phosphor_index = triad_position / CELL_WIDTH;
	vec3 cell_profile = vec3(0.0);
	if (triad_position % CELL_WIDTH < PHOSPHOR_WIDTH) {
		cell_profile[phosphor_index] = 1.0;
	}
	// The rectangular profile has PHOSPHOR_WIDTH unit-weight samples per channel.
	float profile_weight_sum = float(PHOSPHOR_WIDTH);
	float cell_gain = float(TRIAD_WIDTH) / profile_weight_sum;
	return input_rgb * cell_profile * cell_gain;
}
