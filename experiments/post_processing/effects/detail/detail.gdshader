shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Sharpen:0,Unsharp Mask:1,Sobel:2,Outline:3,Emboss:4") = 0;
uniform float amount : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float radius : hint_range(0.5, 8.0, 0.1) = 1.0;
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform vec4 line_color : source_color = vec4(0.02, 0.02, 0.04, 1.0);

vec3 effect_color(vec2 uv, vec3 c) {
	if (mode == 0) {
		vec2 p = lab_pixel_size() * radius;
		vec3 neighbors = lab_sample(uv + vec2(p.x, 0.0)) + lab_sample(uv - vec2(p.x, 0.0)) + lab_sample(uv + vec2(0.0, p.y)) + lab_sample(uv - vec2(0.0, p.y));
		return c + amount * (4.0 * c - neighbors);
	}
	if (mode == 1) {
		vec3 detail = c - lab_blur(uv, radius);
		return c + amount * detail * smoothstep(threshold, threshold + 0.02, abs(detail));
	}
	float edge = clamp(length(lab_sobel(uv, radius)) * amount, 0.0, 1.0);
	if (mode == 2) { return vec3(edge); }
	if (mode == 3) { return mix(c, line_color.rgb, smoothstep(threshold, threshold + 0.1, edge)); }
	return vec3(0.5) + (lab_sample(uv + lab_pixel_size() * radius) - lab_sample(uv - lab_pixel_size() * radius)) * amount;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

