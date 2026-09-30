shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform int mask_style : hint_enum("Stretched VGA Phosphor:7", "VGA Phosphor:8") = 7;
uniform int cell_scale : hint_range(1, 4, 1) = 1;
uniform float phosphor_brightness : hint_range(0.5, 3.0, 0.1) = 1.5;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;


vec3 sample_excitation(vec2 pixel_position, vec2 pixel_size) {
	vec2 sample_uv = clamp(pixel_position * pixel_size,
		pixel_size * 0.5, vec2(1.0) - pixel_size * 0.5);
	return textureLod(screen_texture, sample_uv, 0.0).rgb;
}


void fragment() {
	ivec2 pixel_position = ivec2(floor(FRAGCOORD.xy));
	int subpixel_pitch = 4 * cell_scale;
	int row_pitch = 3 * cell_scale;
	int triad_width = 3 * subpixel_pitch;
	int phosphor_row = pixel_position.y / row_pitch;
	int phase_row = mask_style == 8 ? phosphor_row / 2 : phosphor_row;
	int row_offset = (phase_row % 2) * (triad_width / 2);
	int shifted_column = pixel_position.x - row_offset;
	int triad_index = int(floor(float(shifted_column) / float(triad_width)));
	int triad_column = int(mod(float(shifted_column), float(triad_width)));
	int phosphor_index = triad_column / subpixel_pitch;
	int local_column = triad_column % subpixel_pitch;
	int local_row = pixel_position.y % row_pitch;
	vec2 triad_size = vec2(float(triad_width), float(row_pitch));
	vec2 triad_center = vec2(float(triad_index * triad_width + row_offset),
		float(phosphor_row * row_pitch)) + triad_size * 0.5;
	vec2 sample_offset = triad_size * 0.25;
	// All RGB cells in this triad share these four linear HDR samples.
	vec3 excitation = (
		sample_excitation(triad_center + vec2(-sample_offset.x, -sample_offset.y), SCREEN_PIXEL_SIZE)
		+ sample_excitation(triad_center + vec2(sample_offset.x, -sample_offset.y), SCREEN_PIXEL_SIZE)
		+ sample_excitation(triad_center + vec2(-sample_offset.x, sample_offset.y), SCREEN_PIXEL_SIZE)
		+ sample_excitation(triad_center + vec2(sample_offset.x, sample_offset.y), SCREEN_PIXEL_SIZE)
	) * 0.25;
	float cell_profile = 0.0;
	if (local_column < 3 * cell_scale) {
		float horizontal_profile = sin(PI * (float(local_column) + 0.5) / float(3 * cell_scale));
		float vertical_profile = sin(PI * (float(local_row) + 0.5) / float(row_pitch));
		cell_profile = horizontal_profile * vertical_profile;
	}
	vec3 emission = vec3(0.0);
	emission[phosphor_index] = excitation[phosphor_index] * cell_profile
		* phosphor_brightness * brightness_compensation;
	float original_alpha = textureLod(screen_texture, SCREEN_UV, 0.0).a;
	COLOR = vec4(emission, original_alpha);
}
