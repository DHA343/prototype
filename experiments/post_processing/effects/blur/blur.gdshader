shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Gaussian:0,Dual Kawase:1,Directional:2,Radial:3,Zoom:4,Tilt Shift:5") = 0;
uniform float radius : hint_range(0.0, 32.0, 0.5) = 5.0;
uniform float angle : hint_range(-180.0, 180.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5);
uniform float focus_width : hint_range(0.01, 0.5, 0.01) = 0.15;
uniform sampler2D pyramid_texture : repeat_disable, filter_linear;

vec3 effect_color(vec2 uv, vec3 c) {
	if (radius <= 0.0) { return c; }
	if (mode == 1) { return texture(pyramid_texture, uv).rgb; }
	vec3 sum = vec3(0.0);
	float weights = 0.0;
	if (mode == 0 || mode == 5) {
		float amount = radius;
		if (mode == 5) {
			vec2 p = lab_rotate(radians(angle)) * (uv - center);
			amount *= smoothstep(focus_width, focus_width + 0.2, abs(p.y));
		}
		for (int y = -3; y <= 3; y++) {
			for (int x = -3; x <= 3; x++) {
				vec2 p = vec2(float(x), float(y));
				float w = exp(-dot(p, p) / 4.5);
				sum += lab_sample(uv + p * amount * lab_pixel_size() / 3.0) * w;
				weights += w;
			}
		}
		return sum / weights;
	}
	vec2 direction = vec2(cos(radians(angle)), sin(radians(angle)));
	for (int i = -8; i <= 8; i++) {
		float t = float(i) / 8.0;
		vec2 sample_uv = uv;
		if (mode == 2) { sample_uv += direction * t * radius * lab_pixel_size(); }
		if (mode == 3) { sample_uv = center + lab_rotate(t * radius * 0.002) * (uv - center); }
		if (mode == 4) { sample_uv = center + (uv - center) * (1.0 + t * radius * 0.004); }
		sum += lab_sample(sample_uv);
	}
	return sum / 17.0;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

