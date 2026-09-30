shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform int mask_style : hint_enum("Stretched VGA Phosphor:7", "VGA Phosphor:8") = 7;
uniform int cell_scale : hint_range(1, 4, 1) = 1;
uniform float phosphor_brightness : hint_range(0.5, 3.0, 0.1) = 1.0;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;


float cell_axis_profile(int local_pixel, int cell_size, float edge_weight) {
	return (local_pixel == 0 || local_pixel == cell_size - 1) ? edge_weight : 1.0;
}


void fragment() {
	ivec2 pixel_position = ivec2(floor(FRAGCOORD.xy));
	int subpixel_pitch = 2 * cell_scale;
	int row_pitch = 2 * cell_scale;
	int triad_width = 3 * subpixel_pitch;
	int phosphor_row = pixel_position.y / row_pitch;
	int phase_row = mask_style == 8 ? phosphor_row / 2 : phosphor_row;
	int row_offset = (phase_row % 2) * (triad_width / 2);
	int shifted_column = pixel_position.x - row_offset;
	int triad_column = int(mod(float(shifted_column), float(triad_width)));
	int phosphor_index = triad_column / subpixel_pitch;
	int local_column = triad_column % subpixel_pitch;
	int local_row = pixel_position.y % row_pitch;
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	float edge_weight = cell_scale == 1 ? 0.9 : 0.8;
	float cell_profile = cell_axis_profile(local_column, subpixel_pitch, edge_weight)
		* cell_axis_profile(local_row, row_pitch, edge_weight);
	float horizontal_average = 1.0 - 2.0 * (1.0 - edge_weight) / float(subpixel_pitch);
	float vertical_average = 1.0 - 2.0 * (1.0 - edge_weight) / float(row_pitch);
	// Each channel occupies one third of the triad. Normalize the discrete profile too.
	float normalization = 3.0 / (horizontal_average * vertical_average);
	vec3 emission = vec3(0.0);
	emission[phosphor_index] = screen_color[phosphor_index] * cell_profile
		* normalization * phosphor_brightness * brightness_compensation;
	COLOR = vec4(emission, screen_color.a);
}
