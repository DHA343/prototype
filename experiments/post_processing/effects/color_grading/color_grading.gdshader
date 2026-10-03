shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Exposure:0,Temperature:1,Tint:2,Vibrance:3,Shadows / Midtones / Highlights:4,Channel Mixer:5,Brightness:6,Contrast:7,Saturation:8,Hue:9,Gamma:10") = 0;
uniform float amount : hint_range(-2.0, 2.0, 0.01) = 0.35;
uniform vec4 shadows : source_color = vec4(0.12, 0.08, 0.18, 1.0);
uniform vec4 midtones : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 highlights : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform vec3 red_mix = vec3(1.1, 0.0, 0.0);
uniform vec3 green_mix = vec3(0.0, 1.0, 0.0);
uniform vec3 blue_mix = vec3(0.0, 0.0, 0.9);

vec3 effect_color(vec2 uv, vec3 c) {
	float l = lab_luma(c);
	if (mode == 0) { return c * exp2(amount); }
	if (mode == 1) { return c * exp2(amount * vec3(0.35, 0.0, -0.35)); }
	if (mode == 2) { return c * exp2(amount * vec3(0.2, -0.35, 0.2)); }
	if (mode == 3) {
		float saturation = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		return mix(vec3(l), c, 1.0 + amount * (1.0 - clamp(saturation, 0.0, 1.0)));
	}
	if (mode == 4) {
		float s = 1.0 - smoothstep(0.0, 0.5, l);
		float h = smoothstep(0.5, 1.0, l);
		return c + (shadows.rgb * s + midtones.rgb * (1.0 - s - h) + highlights.rgb * h - vec3(0.5)) * amount;
	}
	if (mode == 5) { return vec3(dot(c, red_mix), dot(c, green_mix), dot(c, blue_mix)); }
	if (mode == 6) { return c + amount; }
	if (mode == 7) { return (c - 0.5) * exp2(amount) + 0.5; }
	if (mode == 8) { return mix(vec3(l), c, max(0.0, 1.0 + amount)); }
	if (mode == 9) {
		vec3 axis = vec3(0.5773502692);
		float a = amount * PI;
		return c * cos(a) + cross(axis, c) * sin(a) + axis * dot(axis, c) * (1.0 - cos(a));
	}
	return pow(max(c, vec3(0.0)), vec3(exp2(-amount)));
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

