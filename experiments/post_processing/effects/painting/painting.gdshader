shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Kuwahara:0,Bilateral:1,Color Planes:2,Comic:3") = 0;
uniform float radius : hint_range(1.0, 8.0, 0.5) = 3.0;
uniform float color_sigma : hint_range(0.02, 1.0, 0.01) = 0.18;
uniform int levels : hint_range(2, 16, 1) = 5;
uniform float edge_strength : hint_range(0.0, 4.0, 0.05) = 1.5;

vec3 bilateral(vec2 uv, vec3 c) {
	vec3 sum = vec3(0.0);
	float weights = 0.0;
	for (int y = -3; y <= 3; y++) {
		for (int x = -3; x <= 3; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec3 sample_color = lab_sample(uv + offset * lab_pixel_size() * radius / 3.0);
			vec3 difference = sample_color - c;
			float w = exp(-dot(offset, offset) / 8.0 - dot(difference, difference) / (2.0 * color_sigma * color_sigma));
			sum += sample_color * w;
			weights += w;
		}
	}
	return sum / max(weights, 0.0001);
}
vec3 effect_color(vec2 uv, vec3 c) {
	if (mode == 0) {
		vec3 best = c;
		float variance_min = 1e10;
		for (int quadrant = 0; quadrant < 4; quadrant++) {
			vec2 signs = vec2((quadrant % 2) == 0 ? -1.0 : 1.0, quadrant < 2 ? -1.0 : 1.0);
			vec3 sum = vec3(0.0);
			vec3 square_sum = vec3(0.0);
			for (int y = 0; y <= 4; y++) {
				for (int x = 0; x <= 4; x++) {
					vec3 s = lab_sample(uv + signs * vec2(float(x), float(y)) * lab_pixel_size() * radius / 4.0);
					sum += s;
					square_sum += s * s;
				}
			}
			vec3 mean = sum / 25.0;
			float variance = lab_luma(abs(square_sum / 25.0 - mean * mean));
			if (variance < variance_min) { variance_min = variance; best = mean; }
		}
		return best;
	}
	vec3 filtered = bilateral(uv, c);
	if (mode == 1) { return filtered; }
	vec3 planes = floor(filtered * float(levels - 1) + 0.5) / float(levels - 1);
	if (mode == 2) { return planes; }
	float edge = smoothstep(0.1, 0.4, length(lab_sobel(uv, 1.0)) * edge_strength);
	return planes * (1.0 - edge);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

