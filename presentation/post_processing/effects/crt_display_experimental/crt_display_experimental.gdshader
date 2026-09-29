shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;

uniform bool signal_enabled = true;
uniform int scanline_count : hint_range(180, 720, 1) = 360;
uniform float beam_min_width : hint_range(0.2, 0.55, 0.01) = 0.34;
uniform float beam_max_width : hint_range(0.2, 0.55, 0.01) = 0.42;
uniform int mask_style : hint_enum("Stretched VGA", "VGA") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;

const float HALF_PI = 1.57079632679;
const float BEAM_WIDEST_WIDTH = 0.55;
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);


vec3 sample_scanline(float row, float row_count, vec2 screen_uv) {
	float clamped_row = clamp(row, 0.0, row_count - 1.0);
	vec2 sample_uv = vec2(screen_uv.x, (clamped_row + 0.5) / row_count);
	return texture(screen_texture, sample_uv).rgb;
}


float beam_power(float width) {
	// Powers of at least 2 keep the beam center no dimmer than the gap.
	return 2.0 + 0.5 * (1.0 / width - 1.0 / BEAM_WIDEST_WIDTH);
}


float beam_profile(float distance, float power) {
	float cosine = max(cos(HALF_PI * clamp(distance, 0.0, 1.0)), 0.0);
	return pow(cosine, power);
}


float beam_light_compensation(float power) {
	float excess_power = power - 2.0;
	// Fit of 2 * integral(profile, 0..1); error stays below 0.04% for widths 0.2..0.55.
	float mean_light = 1.0 + excess_power * (
		-0.19181469 + excess_power * (0.04864666 - 0.00797780 * excess_power)
	);
	return 1.0 / mean_light;
}


float get_vga_phase(vec2 position) {
	if (mask_style == 1) {
		position = floor(position * vec2(1.0, 0.5));
	}

	return fract((position.x + position.y * 3.0) / 6.0);
}


vec3 get_active_phosphor(float phase) {
	if (phase < 0.3333) {
		return vec3(1.0, 0.0, 0.0);
	} else if (phase < 0.6666) {
		return vec3(0.0, 1.0, 0.0);
	}
	return vec3(0.0, 0.0, 1.0);
}


vec3 apply_phosphor_mask(vec3 color, vec3 active_phosphor) {
	vec3 positive_color = max(color, vec3(0.0));
	vec3 target_energy = positive_color * 3.0;
	// The active phosphor reaches full output first; highlights spread to the others.
	vec3 primary_energy = min(target_energy, max(positive_color, vec3(1.0)));
	vec3 secondary_energy = (target_energy - primary_energy) * 0.5;
	vec3 phosphor_color = primary_energy * active_phosphor
		+ secondary_energy * (vec3(1.0) - active_phosphor);
	return mix(positive_color, phosphor_color, mask_strength) + min(color, vec3(0.0));
}


void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 scanline_color = screen_color.rgb;

	if (signal_enabled) {
		float row_count = float(scanline_count);
		float scanline_position = SCREEN_UV.y * row_count - 0.5;
		float upper_row = floor(scanline_position);
		float lower_row = upper_row + 1.0;
		vec3 upper_color = sample_scanline(upper_row, row_count, SCREEN_UV);
		vec3 lower_color = sample_scanline(lower_row, row_count, SCREEN_UV);
		float min_width = min(beam_min_width, beam_max_width);
		float max_width = max(beam_min_width, beam_max_width);
		float upper_luma = clamp(dot(max(upper_color, vec3(0.0)), LUMA_WEIGHTS), 0.0, 1.0);
		float lower_luma = clamp(dot(max(lower_color, vec3(0.0)), LUMA_WEIGHTS), 0.0, 1.0);
		float upper_width = mix(min_width, max_width, upper_luma);
		float lower_width = mix(min_width, max_width, lower_luma);
		float upper_power = beam_power(upper_width);
		float lower_power = beam_power(lower_width);
		float upper_beam = beam_profile(abs(scanline_position - upper_row), upper_power)
			* beam_light_compensation(upper_power);
		float lower_beam = beam_profile(abs(scanline_position - lower_row), lower_power)
			* beam_light_compensation(lower_power);
		scanline_color = upper_color * upper_beam + lower_color * lower_beam;
	}

	vec2 mask_position = floor(1.000001 * FRAGCOORD.xy + vec2(0.5));
	vec3 active_phosphor = get_active_phosphor(get_vga_phase(mask_position));
	vec3 output_color = apply_phosphor_mask(scanline_color, active_phosphor);
	COLOR = vec4(output_color * brightness_compensation, screen_color.a);
}
