shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform sampler2D phosphor_source_texture : repeat_disable, filter_linear;

uniform float phosphor_bloom_radius : hint_range(0.0, 12.0, 0.1) = 5.0;
uniform float phosphor_bloom_strength : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform int phosphor_bloom_taps : hint_range(9, 17, 2) = 13;

const float HALF_CIRCLE = 3.14159265359;


vec3 gaussian_blur(vec2 center_uv, vec2 pixel_size) {
	float sigma = max(phosphor_bloom_radius * 0.5, 0.0001);
	vec2 half_pixel = pixel_size * 0.5;
	int pair_count = (phosphor_bloom_taps - 1) / 2;
	vec3 weighted_sum = textureLod(phosphor_source_texture, center_uv, 0.0).rgb;
	float weight_sum = 1.0;

	for (int pair_index = 0; pair_index < 8; pair_index++) {
		if (pair_index >= pair_count) {
			break;
		}

		float angle = HALF_CIRCLE * float(pair_index) / float(pair_count);
		// Vary the radius across the evenly spaced directions without favoring one axis.
		float sample_radius = phosphor_bloom_radius * sqrt(0.55 + 0.35 * cos(4.0 * angle));
		vec2 offset_uv = vec2(cos(angle), sin(angle)) * sample_radius * pixel_size;
		float weight = exp(-(sample_radius * sample_radius) / (2.0 * sigma * sigma));
		vec2 positive_uv = clamp(center_uv + offset_uv, half_pixel, vec2(1.0) - half_pixel);
		vec2 negative_uv = clamp(center_uv - offset_uv, half_pixel, vec2(1.0) - half_pixel);
		weighted_sum += (textureLod(phosphor_source_texture, positive_uv, 0.0).rgb
			+ textureLod(phosphor_source_texture, negative_uv, 0.0).rgb) * weight;
		weight_sum += 2.0 * weight;
	}

	return weighted_sum / weight_sum;
}


void fragment() {
	vec4 sharp_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (phosphor_bloom_radius > 0.0 && phosphor_bloom_strength > 0.0) {
		vec3 blurred_color = gaussian_blur(SCREEN_UV, SCREEN_PIXEL_SIZE);
		COLOR = vec4(mix(sharp_color.rgb, blurred_color, phosphor_bloom_strength), sharp_color.a);
	} else {
		COLOR = sharp_color;
	}
}
