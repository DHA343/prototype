shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;

uniform bool signal_enabled = true;
uniform int scanline_count : hint_range(180, 720, 1) = 360;
uniform float sharpness : hint_range(0.5, 1.0, 0.01) = 0.67;
uniform float signal_pitch : hint_range(0.5, 3.0, 0.1) = 1.5;
uniform float beam_width : hint_range(0.75, 1.25, 0.01) = 1.0;
uniform int mask_style : hint_enum("Stretched VGA", "VGA", "Dots", "Aperture Grille", "Wide Grille", "Wide Soft Grille", "Slot Mask") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float brightness_compensation : hint_range(0.5, 2.0, 0.01) = 1.0;

const float HALF_PI = 1.57079632679;


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


float beam_power_from_fwhm(float width) {
	float half_max_distance = width * 0.5;
	float cosine_at_half = cos(HALF_PI * half_max_distance);
	return log(0.5) / log(cosine_at_half);
}


float beam_profile(float distance, float power) {
	float cosine = max(cos(HALF_PI * clamp(distance, 0.0, 1.0)), 0.0);
	return pow(cosine, power);
}


float beam_light_compensation(float power) {
	float excess_power = power - 2.0;
	float mean_light = 1.0 + excess_power * (
		-0.19329331 + excess_power * (
			0.05479169 + excess_power * (
				-0.01519815 + 0.00253758 * excess_power
			)
		)
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


// Additional pattern cells and averages follow https://godotshaders.com/shader/crt-with-luminance-preservation/
vec4 generate_mask(vec2 fragcoord) {
	if (mask_style < 2) {
		vec2 vga_position = floor(1.000001 * fragcoord + vec2(0.5));
		return vec4(get_active_phosphor(get_vga_phase(vga_position)), 1.0 / 3.0);
	}

	int column = int(floor(fragcoord.x));
	int row = int(floor(fragcoord.y));
	if (mask_style == 2) {
		int phase = (row * 2 + column) % 4;
		if (phase == 0) {
			return vec4(1.0, 0.0, 0.0, 0.25);
		} else if (phase == 1) {
			return vec4(0.0, 1.0, 0.0, 0.25);
		} else if (phase == 2) {
			return vec4(0.0, 0.0, 1.0, 0.25);
		}
		return vec4(0.0, 0.0, 0.0, 0.25);
	}
	if (mask_style == 3) {
		return column % 2 == 0
			? vec4(0.0, 1.0, 0.0, 0.5) : vec4(1.0, 0.0, 1.0, 0.5);
	}
	if (mask_style == 4) {
		int phase = column % 4;
		if (phase == 0) {
			return vec4(1.0, 0.0, 0.0, 0.25);
		} else if (phase == 1) {
			return vec4(0.0, 1.0, 0.0, 0.25);
		} else if (phase == 2) {
			return vec4(0.0, 0.0, 1.0, 0.25);
		}
		return vec4(0.0, 0.0, 0.0, 0.25);
	}
	if (mask_style == 5) {
		int phase = column % 4;
		if (phase == 0) {
			return vec4(1.0, 0.125, 0.0, 0.3125);
		} else if (phase == 1) {
			return vec4(0.125, 1.0, 0.125, 0.3125);
		} else if (phase == 2) {
			return vec4(0.0, 0.125, 1.0, 0.3125);
		}
		return vec4(0.125, 0.0, 0.125, 0.3125);
	}

	int slot_row = row % 4;
	int slot_column = column % 4;
	if (slot_row == 0 || slot_row == 2) {
		return slot_column % 2 == 0
			? vec4(1.0, 0.0, 1.0, 0.375) : vec4(0.0, 1.0, 0.0, 0.375);
	}
	if (slot_row == 1) {
		if (slot_column == 0) {
			return vec4(0.0, 0.0, 1.0, 0.375);
		} else if (slot_column == 1) {
			return vec4(0.0, 1.0, 0.0, 0.375);
		} else if (slot_column == 2) {
			return vec4(1.0, 0.0, 0.0, 0.375);
		}
		return vec4(0.0, 0.0, 0.0, 0.375);
	}
	if (slot_column == 0) {
		return vec4(1.0, 0.0, 0.0, 0.375);
	} else if (slot_column == 2) {
		return vec4(0.0, 0.0, 1.0, 0.375);
	} else if (slot_column == 3) {
		return vec4(0.0, 1.0, 0.0, 0.375);
	}
	return vec4(0.0, 0.0, 0.0, 0.375);
}


vec3 apply_phosphor_mask(vec3 color, vec4 mask_sample) {
	vec3 positive_color = max(color, vec3(0.0));
	vec3 target_color = positive_color / mask_sample.a;
	vec3 primary_color = clamp(target_color, vec3(0.0), vec3(1.0));
	vec3 secondary_color = (target_color - primary_color) / (1.0 / mask_sample.a - 1.0);
	vec3 phosphor_color = primary_color * mask_sample.rgb
		+ secondary_color * (vec3(1.0) - mask_sample.rgb);
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
		float power = beam_power_from_fwhm(beam_width);
		float compensation = beam_light_compensation(power);
		float upper_beam = beam_profile(abs(scanline_position - upper_row), power) * compensation;
		float lower_beam = beam_profile(abs(scanline_position - lower_row), power) * compensation;
		scanline_color = upper_color * upper_beam + lower_color * lower_beam;
	}

	vec3 output_color = apply_phosphor_mask(scanline_color, generate_mask(FRAGCOORD.xy));
	COLOR = vec4(output_color * brightness_compensation, screen_color.a);
}
