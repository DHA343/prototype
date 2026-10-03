shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Monochrome:0,Sepia:1,Negative:2,Duotone:3,Gradient Map:4,LUT:5,Solarization:6,Selective Color:7,Thermal:8,Night Vision:9") = 0;
uniform vec4 dark_color : source_color = vec4(0.08, 0.02, 0.16, 1.0);
uniform vec4 middle_color : source_color = vec4(0.85, 0.2, 0.22, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform vec4 selected_color : source_color = vec4(0.2, 0.8, 0.3, 1.0);
uniform float threshold : hint_range(0.01, 1.0, 0.01) = 0.35;
uniform sampler2D lut_texture : source_color, repeat_disable, filter_linear;
uniform int lut_size : hint_range(2, 64, 1) = 16;
uniform float noise_amount : hint_range(0.0, 0.2, 0.001) = 0.03;

vec3 effect_color(vec2 uv, vec3 c) {
	float l = lab_luma(c);
	if (mode == 0) { return vec3(l); }
	if (mode == 1) { return vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131))); }
	if (mode == 2) { return vec3(1.0) - c; }
	if (mode == 3) { return mix(dark_color.rgb, light_color.rgb, clamp(l, 0.0, 1.0)); }
	if (mode == 4) {
		return l < 0.5 ? mix(dark_color.rgb, middle_color.rgb, clamp(l * 2.0, 0.0, 1.0)) : mix(middle_color.rgb, light_color.rgb, clamp(l * 2.0 - 1.0, 0.0, 1.0));
	}
	if (mode == 5) {
		float n = float(lut_size);
		vec3 p = clamp(c, 0.0, 1.0) * (n - 1.0);
		float slice = floor(p.b);
		vec2 a = vec2((slice * n + p.r + 0.5) / (n * n), (p.g + 0.5) / n);
		vec2 b = vec2((min(slice + 1.0, n - 1.0) * n + p.r + 0.5) / (n * n), a.y);
		return textureSize(lut_texture, 0).x >= lut_size * lut_size ? mix(texture(lut_texture, a).rgb, texture(lut_texture, b).rgb, fract(p.b)) : c;
	}
	if (mode == 6) { return mix(c, 1.0 - c, step(vec3(threshold), c)); }
	if (mode == 7) {
		vec3 a = c / max(length(c), 0.001);
		vec3 b = selected_color.rgb / max(length(selected_color.rgb), 0.001);
		return mix(vec3(l), c, 1.0 - smoothstep(threshold, threshold + 0.1, length(a - b)));
	}
	if (mode == 8) {
		float t = clamp(l, 0.0, 1.0);
		return clamp(vec3(1.5) - abs(4.0 * t - vec3(3.0, 2.0, 1.0)), 0.0, 1.0);
	}
	float noise = (lab_hash(floor(uv / lab_pixel_size()) + floor(TIME * 30.0)) - 0.5) * noise_amount;
	return vec3(0.15, 1.0, 0.25) * (sqrt(max(l, 0.0)) + noise);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

