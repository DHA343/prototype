shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;

uniform bool signal_enabled = true;
uniform bool signal_prefilter_enabled = true;
uniform int scanline_count : hint_range(180, 720, 1) = 360;
uniform float sharpness : hint_range(0.5, 1.0, 0.01) = 0.67;
uniform float signal_pitch : hint_range(0.5, 3.0, 0.1) = 1.5;
uniform float vertical_blur : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float scanline_strength : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float beam_width : hint_range(0.75, 1.25, 0.01) = 0.9;
uniform float mask_pitch : hint_range(2.0, 6.0, 1.0) = 3.0;
uniform int row_height : hint_range(1, 8, 1) = 3;
uniform int mask_model : hint_enum("Mask Redistribution", "Cell Emission") = 0;
uniform int mask_pattern : hint_enum("Staggered RGB:0", "RGB Stripes:1", "Green / Magenta Stripes:2") = 0;
uniform float mask_strength : hint_range(0.0, 1.0, 0.01) = 0.5;

const float HALF_PI = 1.57079632679;

#include "mask_geometry.gdshaderinc"


float signal_weight(float distance) {
	return 1.0 - smoothstep(0.0, 1.0, distance * sharpness);
}


vec3 sample_signal(vec2 sample_uv, vec2 pixel_size, vec2 footprint) {
	if (!signal_prefilter_enabled) {
		return textureLod(screen_texture, sample_uv, 0.0).rgb;
	}

	// Integrate source-pixel coverage before reducing the signal's sampling rate.
	// Pair adjacent pixels into one bilinear read without skipping thin features.
	vec2 footprint_start = sample_uv / pixel_size - footprint * 0.5;
	vec2 footprint_end = footprint_start + footprint;
	vec2 first_pixel = floor(footprint_start);
	ivec2 pixel_count = ivec2(ceil(footprint_end) - first_pixel);
	vec3 integrated_color = vec3(0.0);

	for (int row = 0; row < pixel_count.y; row += 2) {
		float pixel_y = first_pixel.y + float(row);
		vec2 row_start = vec2(pixel_y, pixel_y + 1.0);
		vec2 row_weights = max(
			min(vec2(footprint_end.y), row_start + 1.0)
			- max(vec2(footprint_start.y), row_start), vec2(0.0));
		float row_weight = row_weights.x + row_weights.y;
		float sample_y = pixel_y + 0.5 + row_weights.y / row_weight;

		for (int column = 0; column < pixel_count.x; column += 2) {
			float pixel_x = first_pixel.x + float(column);
			vec2 column_start = vec2(pixel_x, pixel_x + 1.0);
			vec2 column_weights = max(
				min(vec2(footprint_end.x), column_start + 1.0)
				- max(vec2(footprint_start.x), column_start), vec2(0.0));
			float column_weight = column_weights.x + column_weights.y;
			float sample_x = pixel_x + 0.5 + column_weights.y / column_weight;
			vec2 filtered_uv = clamp(vec2(sample_x, sample_y) * pixel_size,
				pixel_size * 0.5, vec2(1.0) - pixel_size * 0.5);
			integrated_color += textureLod(screen_texture, filtered_uv, 0.0).rgb
				* column_weight * row_weight;
		}
	}

	return integrated_color / (footprint.x * footprint.y);
}


vec3 reconstruct_signal(float row_y, float screen_x, vec2 pixel_size, vec2 footprint) {
	float signal_x = (screen_x / pixel_size.x - 0.5) / signal_pitch;
	float center_index = floor(signal_x + 0.5);
	vec3 weighted_color = vec3(0.0);
	float total_weight = 0.0;

	for (int offset = -2; offset <= 2; offset++) {
		float sample_index = center_index + float(offset);
		float weight = signal_weight(abs(signal_x - sample_index));
		if (weight > 0.0) {
			float sample_x = clamp((sample_index * signal_pitch + 0.5) * pixel_size.x,
				0.5 * pixel_size.x, 1.0 - 0.5 * pixel_size.x);
			weighted_color += sample_signal(vec2(sample_x, row_y), pixel_size, footprint) * weight;
		}
		total_weight += weight;
	}

	return weighted_color / total_weight;
}


vec3 sample_scanline(float row, float row_count, vec2 screen_uv, vec2 pixel_size) {
	float row_y = (clamp(row, 0.0, row_count - 1.0) + 0.5) / row_count;
	vec2 footprint = max(vec2(signal_pitch, 1.0 / (row_count * pixel_size.y)), vec2(1.0));
	return reconstruct_signal(row_y, screen_uv.x, pixel_size, footprint);
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


float scanline_light(float position, float pixel_span) {
	float power = beam_power_from_fwhm(beam_width);
	float integrated_light = 0.0;
	// Average the row profile across the output pixel to soften narrow bands.
	for (int index = 0; index < 4; index++) {
		float offset = (float(index) + 0.5) / 4.0 - 0.5;
		float phase = fract(position + offset * pixel_span);
		integrated_light += beam_profile(phase, power) + beam_profile(1.0 - phase, power);
	}
	return integrated_light * 0.25 * beam_light_compensation(power);
}


vec4 generate_mask(vec2 fragcoord) {
	float row_offset = mask_row_offset(
		fragcoord.y, mask_pitch, float(row_height), mask_pattern);
	vec3 coverage = mask_aperture_integral(
		fragcoord.x - 0.5, 1.0, row_offset, mask_pitch, mask_pattern, 0.0);
	return vec4(coverage, mask_occupancy(mask_pattern));
}


vec3 redistribute_mask(vec3 color, vec4 mask_sample) {
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
	float row_count = float(scanline_count);
	float scanline_position = SCREEN_UV.y * row_count - 0.5;

	if (signal_enabled) {
		if (vertical_blur > 0.0) {
			float upper_row = floor(scanline_position);
			float lower_row = upper_row + 1.0;
			vec3 upper_color = sample_scanline(upper_row, row_count, SCREEN_UV, SCREEN_PIXEL_SIZE);
			vec3 lower_color = sample_scanline(lower_row, row_count, SCREEN_UV, SCREEN_PIXEL_SIZE);
			float row_phase = fract(scanline_position);
			float lower_weight = 0.5 - 0.5 * cos(2.0 * HALF_PI * row_phase);
			scanline_color = mix(upper_color, lower_color, lower_weight);
		}
		if (vertical_blur < 1.0) {
			vec2 horizontal_footprint = vec2(max(signal_pitch, 1.0), 1.0);
			vec3 horizontal_color = reconstruct_signal(
				SCREEN_UV.y, SCREEN_UV.x, SCREEN_PIXEL_SIZE, horizontal_footprint);
			scanline_color = mix(horizontal_color, scanline_color, vertical_blur);
		}
	}

	if (scanline_strength > 0.0) {
		float pixel_span = row_count * SCREEN_PIXEL_SIZE.y;
		// Fade unresolved row frequencies before they turn into aliasing patterns.
		float visibility = 1.0 - smoothstep(0.4, 0.5, pixel_span);
		if (visibility > 0.0) {
			scanline_color *= mix(1.0, scanline_light(scanline_position, pixel_span),
				scanline_strength * visibility);
		}
	}

	vec3 output_color;
	if (mask_model == 1) {
		// The Cell pass samples this reconstructed HDR signal before Bloom.
		output_color = scanline_color;
	} else {
		output_color = redistribute_mask(scanline_color, generate_mask(FRAGCOORD.xy));
	}
	COLOR = vec4(output_color, screen_color.a);
}
