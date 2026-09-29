shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;

uniform bool signal_enabled = true;
uniform int scanline_count : hint_range(180, 720, 1) = 360;
uniform float sharpness : hint_range(0.5, 1.0, 0.01) = 0.67;
uniform float signal_pitch : hint_range(0.5, 3.0, 0.1) = 1.5;
uniform float beam_min_width : hint_range(0.2, 0.55, 0.01) = 0.34;
uniform float beam_max_width : hint_range(0.2, 0.55, 0.01) = 0.42;
uniform int mask_style : hint_enum("Stretched VGA", "VGA", "Dots", "Aperture Grille", "Wide Grille", "Wide Soft Grille", "Slot Mask") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;

const float HALF_PI = 1.57079632679;
const float BEAM_WIDEST_WIDTH = 0.55;


float signal_weight(float distance) {
	return 1.0 - smoothstep(0.0, 1.0, distance * sharpness);
}


vec3 reconstruct_signal(float row_y, float screen_x, float pixel_width) {
	float signal_x = (screen_x / pixel_width - 0.5) / signal_pitch;
	float center_index = floor(signal_x + 0.5);
	vec3 weighted_color = vec3(0.0);
	float total_weight = 0.0;

	for (int offset = -2; offset <= 2; offset++) {
		float sample_index = center_index + float(offset);
		float weight = signal_weight(abs(signal_x - sample_index));
		float sample_x = clamp((sample_index * signal_pitch + 0.5) * pixel_width,
			0.5 * pixel_width, 1.0 - 0.5 * pixel_width);
		weighted_color += textureLod(screen_texture, vec2(sample_x, row_y), 0.0).rgb * weight;
		total_weight += weight;
	}

	return weighted_color / total_weight;
}


vec3 sample_scanline(float row, float row_count, vec2 screen_uv, float pixel_width) {
	float row_y = (clamp(row, 0.0, row_count - 1.0) + 0.5) / row_count;
	return reconstruct_signal(row_y, screen_uv.x, pixel_width);
}


vec3 beam_power(vec3 width) {
	return vec3(2.0) + 0.5 * (vec3(1.0) / width - vec3(1.0 / BEAM_WIDEST_WIDTH));
}


vec3 beam_profile(float distance, vec3 power) {
	float cosine = max(cos(HALF_PI * clamp(distance, 0.0, 1.0)), 0.0);
	return pow(vec3(cosine), power);
}


vec3 beam_light_compensation(vec3 power) {
	vec3 excess_power = power - vec3(2.0);
	// Fit of 2 * integral(profile, 0..1); error stays below 0.04% for widths 0.2..0.55.
	vec3 mean_light = vec3(1.0) + excess_power * (
		vec3(-0.19181469) + excess_power * (vec3(0.04864666) - 0.00797780 * excess_power)
	);
	return vec3(1.0) / mean_light;
}


vec3 beam_width(vec3 color) {
	vec3 intensity = clamp(max(color, vec3(0.0)), vec3(0.0), vec3(1.0));
	return mix(vec3(min(beam_min_width, beam_max_width)),
		vec3(max(beam_min_width, beam_max_width)), intensity);
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


vec3 mask_pattern(vec2 position) {
	if (mask_style < 2) {
		return get_active_phosphor(get_vga_phase(position));
	}

	float column = floor(position.x);
	float row = floor(position.y);
	if (mask_style == 2) {
		// Two-pixel cells alternate their phosphor order; neutral edge pixels separate the dots.
		float cell = floor(column / 2.0) + floor(row / 3.0);
		vec3 phosphor = get_active_phosphor(fract(cell / 3.0));
		return mix(phosphor, vec3(1.0 / 3.0), step(2.0, mod(row, 3.0)) * 0.65);
	}
	if (mask_style == 3) {
		return get_active_phosphor(fract(column / 3.0));
	}
	if (mask_style == 4) {
		return get_active_phosphor(fract(floor(column / 2.0) / 3.0));
	}
	if (mask_style == 5) {
		float stripe = floor(column / 2.0);
		vec3 current = get_active_phosphor(fract(stripe / 3.0));
		vec3 adjacent = get_active_phosphor(fract((stripe + (mod(column, 2.0) < 1.0 ? -1.0 : 1.0)) / 3.0));
		return mix(current, adjacent, 0.22);
	}

	float staggered_column = floor(column / 2.0) + mod(floor(row / 2.0), 2.0);
	vec3 slot = get_active_phosphor(fract(staggered_column / 3.0));
	return mix(slot, vec3(1.0 / 3.0), step(1.0, mod(row, 2.0)) * 0.35);
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
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 scanline_color = screen_color.rgb;

	if (signal_enabled) {
		float row_count = float(scanline_count);
		float scanline_position = SCREEN_UV.y * row_count - 0.5;
		float upper_row = floor(scanline_position);
		float lower_row = upper_row + 1.0;
		vec3 upper_color = sample_scanline(upper_row, row_count, SCREEN_UV, SCREEN_PIXEL_SIZE.x);
		vec3 lower_color = sample_scanline(lower_row, row_count, SCREEN_UV, SCREEN_PIXEL_SIZE.x);
		vec3 upper_power = beam_power(beam_width(upper_color));
		vec3 lower_power = beam_power(beam_width(lower_color));
		vec3 upper_beam = beam_profile(abs(scanline_position - upper_row), upper_power)
			* beam_light_compensation(upper_power);
		vec3 lower_beam = beam_profile(abs(scanline_position - lower_row), lower_power)
			* beam_light_compensation(lower_power);
		scanline_color = upper_color * upper_beam + lower_color * lower_beam;
	}

	vec2 mask_position = floor(1.000001 * FRAGCOORD.xy + vec2(0.5));
	vec3 output_color = apply_phosphor_mask(scanline_color, mask_pattern(mask_position));
	COLOR = vec4(output_color * brightness_compensation, screen_color.a);
}
