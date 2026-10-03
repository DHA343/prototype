shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Posterize:0,Palette:1,Bayer:2,Random:3,Blue Noise:4") = 0;
uniform int levels : hint_range(2, 32, 1) = 5;
uniform float scale : hint_range(1.0, 16.0, 1.0) = 1.0;
uniform vec4 palette_a : source_color = vec4(0.03, 0.08, 0.09, 1.0);
uniform vec4 palette_b : source_color = vec4(0.15, 0.35, 0.25, 1.0);
uniform vec4 palette_c : source_color = vec4(0.5, 0.65, 0.3, 1.0);
uniform vec4 palette_d : source_color = vec4(0.9, 0.95, 0.6, 1.0);
uniform sampler2D blue_noise : repeat_enable, filter_nearest;

float bayer(vec2 pixel) {
	ivec2 p = ivec2(mod(pixel, 4.0));
	int values[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
	return (float(values[p.y * 4 + p.x]) + 0.5) / 16.0;
}
vec3 effect_color(vec2 uv, vec3 c) {
	float n = float(levels - 1);
	vec2 p = floor(uv / lab_pixel_size() / scale);
	float noise = mode == 2 ? bayer(p) : lab_hash(p);
	if (mode == 4) { noise = texture(blue_noise, (p + 0.5) / vec2(textureSize(blue_noise, 0))).r; }
	if (mode == 1) {
		vec3 options[4] = {palette_a.rgb, palette_b.rgb, palette_c.rgb, palette_d.rgb};
		vec3 result = options[0];
		float best = 1e10;
		for (int i = 0; i < 4; i++) {
			float distance = dot(c - options[i], c - options[i]);
			if (distance < best) { best = distance; result = options[i]; }
		}
		return result;
	}
	return floor(clamp(c, 0.0, 1.0) * n + (mode == 0 ? 0.5 : noise)) / n;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

