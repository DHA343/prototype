shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;
uniform float luma_strength : hint_range(0.0, 0.25, 0.001) = 0.08;
uniform float chroma_strength : hint_range(0.0, 0.1, 0.001) = 0.006;
uniform float grain_size : hint_range(1.0, 8.0, 0.1) = 1.5;
uniform float grain_softness : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float refresh_rate : hint_range(0.0, 60.0, 1.0) = 30.0;

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);


vec4 grain_hash(ivec2 lattice_cell, uint tick) {
	uint key = uint(lattice_cell.x) * 374761393u + uint(lattice_cell.y) * 668265263u;
	key += tick * 2246822519u;
	uvec4 bits = uvec4(key) + uvec4(0u, 1597334677u, 3812015801u, 958282571u);
	bits = (bits ^ (bits >> 16u)) * 2246822519u;
	bits = (bits ^ (bits >> 13u)) * 3266489917u;
	bits = bits ^ (bits >> 16u);
	return vec4(bits) * (2.0 / 4294967296.0) - 1.0;
}


vec4 sample_grain(vec2 fragment_position, uint tick) {
	vec2 grain_position = fragment_position / grain_size - 0.5;
	vec4 nearest_grain = grain_hash(ivec2(floor(grain_position + 0.5)), tick);
	if (grain_softness <= 0.0) {
		return nearest_grain;
	}

	ivec2 lattice_cell = ivec2(floor(grain_position));
	vec2 weights = smoothstep(vec2(0.0), vec2(1.0), fract(grain_position));
	vec4 upper_grain = mix(grain_hash(lattice_cell, tick),
		grain_hash(lattice_cell + ivec2(1, 0), tick), weights.x);
	vec4 lower_grain = mix(grain_hash(lattice_cell + ivec2(0, 1), tick),
		grain_hash(lattice_cell + ivec2(1, 1), tick), weights.x);
	return mix(nearest_grain, mix(upper_grain, lower_grain, weights.y), grain_softness);
}


vec3 rgb_to_oklab(vec3 rgb) {
	vec3 cone_response = vec3(
		dot(rgb, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
		dot(rgb, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
		dot(rgb, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
	vec3 roots = pow(max(cone_response, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		dot(roots, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
		dot(roots, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
		dot(roots, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
}


vec3 oklab_to_rgb(vec3 lab) {
	vec3 roots = vec3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	vec3 cone_response = roots * roots * roots;
	return vec3(
		dot(cone_response, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
		dot(cone_response, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
		dot(cone_response, vec3(-0.0041960863, -0.7034186147, 1.7076147010)));
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 output_rgb = screen_color.rgb;
	if (luma_strength > 0.0 || chroma_strength > 0.0) {
		uint tick = uint(floor(TIME * refresh_rate));
		vec4 grain = sample_grain(FRAGCOORD.xy, tick);
		vec3 positive_rgb = max(screen_color.rgb, vec3(0.0));
		float luminance = dot(positive_rgb, LUMA_WEIGHTS);
		// Sqrt response keeps grain visible in midtones without overwhelming HDR light.
		// The small floor also gives black areas a nonuniform noise signal.
		float response = sqrt(luminance) + 0.02;
		vec3 noisy_rgb = positive_rgb;
		if (luma_strength > 0.0) {
			float noisy_luminance = max(luminance + grain.x * luma_strength * response, 0.0);
			noisy_rgb = luminance > 0.000001
				? positive_rgb * (noisy_luminance / luminance) : vec3(noisy_luminance);
		}
		if (chroma_strength > 0.0) {
			// Balance red/green and blue/yellow variation in a perceptual color space.
			vec3 perceptual_color = rgb_to_oklab(noisy_rgb);
			perceptual_color.yz += grain.yz * chroma_strength * (perceptual_color.x + 0.02);
			noisy_rgb = oklab_to_rgb(perceptual_color);
		}
		output_rgb = max(noisy_rgb, vec3(0.0)) + min(screen_color.rgb, vec3(0.0));
	}
	COLOR = vec4(output_rgb, screen_color.a);
}
