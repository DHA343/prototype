shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;
// These textures contain linear HDR data, not sRGB color assets.
uniform sampler2D source_texture : repeat_disable, filter_linear;
uniform sampler2D near_texture : repeat_disable, filter_linear;
uniform sampler2D far_texture : repeat_disable, filter_linear;

uniform int pass_stage = 3;
uniform float bloom_hdr_limit : hint_range(1.0, 16.0, 0.1) = 2.0;
uniform float near_strength : hint_range(0.0, 0.25, 0.005) = 0.06;
uniform float far_strength : hint_range(0.0, 0.1, 0.001) = 0.01;
uniform float gaussian_fwhm = 2.0;
uniform vec2 gaussian_axis = vec2(1.0, 0.0);

const float FWHM_TO_SIGMA = 0.42466090014;


vec3 bloom_source(vec3 color) {
	float intensity = max(color.r, max(color.g, color.b));
	if (intensity <= 1.0) {
		return color;
	}
	// Limit = 1 is the zero-headroom case; avoid dividing by zero below.
	if (bloom_hdr_limit <= 1.0) {
		return color / intensity;
	}

	float headroom = bloom_hdr_limit - 1.0;
	float limited_intensity = 1.0 + headroom
		* (1.0 - exp(-(intensity - 1.0) / headroom));
	return color * (limited_intensity / intensity);
}


vec2 reflect_uv(vec2 uv) {
	return vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
}


vec3 gaussian_blur(vec2 uv) {
	vec2 pixel_size = 1.0 / vec2(textureSize(source_texture, 0));
	float sigma = gaussian_fwhm * FWHM_TO_SIGMA;
	float inverse_variance = 0.5 / (sigma * sigma);
	int radius = int(ceil(3.0 * sigma));
	vec3 center_color = textureLod(source_texture, uv, 0.0).rgb;
	vec3 weighted_delta = vec3(0.0);
	float total_weight = 1.0;

	// Pair adjacent discrete taps using bilinear filtering.
	for (int index = 1; index <= radius; index += 2) {
		float first_distance = float(index);
		float second_distance = first_distance + 1.0;
		float first_weight = exp(-first_distance * first_distance * inverse_variance);
		float second_weight = index + 1 <= radius
			? exp(-second_distance * second_distance * inverse_variance) : 0.0;
		float pair_weight = first_weight + second_weight;
		if (pair_weight == 0.0) {
			break;
		}
		float pair_distance = (first_distance * first_weight
			+ second_distance * second_weight) / pair_weight;
		vec2 offset_uv = gaussian_axis * pair_distance * pixel_size;
		weighted_delta += (
			textureLod(source_texture, reflect_uv(uv + offset_uv), 0.0).rgb
			+ textureLod(source_texture, reflect_uv(uv - offset_uv), 0.0).rgb
			- 2.0 * center_color
		) * pair_weight;
		total_weight += 2.0 * pair_weight;
	}
	// Difference form preserves a constant field exactly, including HDR buffer rounding.
	return center_color + weighted_delta / total_weight;
}


void fragment() {
	if (pass_stage == 0) {
		vec4 original = textureLod(source_texture, UV, 0.0);
		COLOR = vec4(bloom_source(original.rgb), original.a);
	} else if (pass_stage == 1 || pass_stage == 2) {
		COLOR = vec4(gaussian_blur(UV), 1.0);
	} else {
		vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);
		vec3 emission = textureLod(source_texture, SCREEN_UV, 0.0).rgb;
		vec3 near_color = textureLod(near_texture, SCREEN_UV, 0.0).rgb;
		vec3 far_color = textureLod(far_texture, SCREEN_UV, 0.0).rgb;
		vec3 redistributed = original.rgb + (near_color - emission) * near_strength
			+ (far_color - emission) * far_strength;
		COLOR = vec4(redistributed, original.a);
	}
}
