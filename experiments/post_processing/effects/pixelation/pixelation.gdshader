shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Rectangular Mosaic:0,Hexagonal Mosaic:1,LED Dots:2,Low Resolution Nearest:3,Low Resolution Bilinear:4") = 0;
uniform float cell_size : hint_range(2.0, 64.0, 1.0) = 8.0;
uniform float cell_aspect : hint_range(0.25, 4.0, 0.05) = 1.0;
uniform int target_height : hint_range(24, 720, 1) = 180;
uniform float dot_radius : hint_range(0.1, 0.5, 0.01) = 0.4;
uniform vec4 gap_color : source_color = vec4(0.01, 0.01, 0.02, 1.0);

vec3 effect_color(vec2 uv, vec3 c) {
	vec2 size = vec2(cell_size * cell_aspect, cell_size);
	if (mode >= 3) {
		float pixel_scale = 1.0 / (lab_pixel_size().y * float(target_height));
		size = vec2(pixel_scale);
	}
	vec2 p = uv / lab_pixel_size() / size;
	vec2 cell = floor(p) + 0.5;
	if (mode == 1) {
		vec2 point = uv / lab_pixel_size();
		vec2 spacing = vec2(1.7320508, 3.0) * cell_size;
		vec2 a = (floor(point / spacing) + 0.5) * spacing;
		vec2 b = floor((point - spacing * 0.5) / spacing) * spacing + spacing;
		vec2 best = length(point - a) < length(point - b) ? a : b;
		return lab_sample(best * lab_pixel_size());
	}
	if (mode == 4) {
		vec2 f = fract(p - 0.5);
		vec2 base = floor(p - 0.5) + 0.5;
		vec3 a = mix(lab_sample(base * size * lab_pixel_size()), lab_sample((base + vec2(1.0, 0.0)) * size * lab_pixel_size()), f.x);
		vec3 b = mix(lab_sample((base + vec2(0.0, 1.0)) * size * lab_pixel_size()), lab_sample((base + vec2(1.0)) * size * lab_pixel_size()), f.x);
		return mix(a, b, f.y);
	}
	vec3 result = lab_sample(cell * size * lab_pixel_size());
	if (mode == 2) {
		float mask = 1.0 - smoothstep(dot_radius - 0.03, dot_radius + 0.03, length(fract(p) - 0.5));
		result = mix(gap_color.rgb, result, mask);
	}
	return result;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

