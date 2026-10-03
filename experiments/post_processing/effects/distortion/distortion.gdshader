shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Barrel:0,Pincushion:1,Fisheye:2,Ripple:3,Waves:4,Heat Haze:5,Swirl:6,Kaleidoscope:7") = 0;
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float frequency : hint_range(1.0, 80.0, 0.5) = 20.0;
uniform float speed : hint_range(0.0, 4.0, 0.05) = 1.0;
uniform vec2 center = vec2(0.5);
uniform int segments : hint_range(2, 16, 1) = 6;

vec3 effect_color(vec2 uv, vec3 c) {
	vec2 p = uv - center;
	float r = length(p);
	if (mode == 0 || mode == 1) { p *= 1.0 + (mode == 0 ? 1.0 : -1.0) * amount * dot(p, p) * 2.0; }
	if (mode == 2) { p *= mix(1.0, atan(r * 3.0) / max(r * 2.0, 0.0001), amount); }
	if (mode == 3) { p += p / max(r, 0.001) * sin(r * frequency - TIME * speed * 6.0) * amount * 0.025; }
	if (mode == 4) { p += vec2(sin(uv.y * frequency + TIME * speed), cos(uv.x * frequency + TIME * speed)) * amount * 0.04; }
	if (mode == 5) {
		p.x += sin(uv.y * frequency + TIME * speed * 2.0) * sin(uv.x * frequency * 0.3 + TIME * speed) * amount * 0.03;
		p.y += sin(uv.x * frequency + TIME * speed * 3.0) * amount * 0.01;
	}
	if (mode == 6) { p = lab_rotate(amount * 8.0 * exp(-r * 4.0)) * p; }
	if (mode == 7) {
		float slice = TAU / float(segments);
		float angle = abs(mod(atan(p.y, p.x) + TIME * speed * 0.1, slice) - slice * 0.5);
		p = vec2(cos(angle), sin(angle)) * r;
	}
	return lab_sample(p + center);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

