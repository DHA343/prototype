shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("VHS Composite:0,Color Bleed:1,Tape Tearing:2,Tracking Noise:3,Interlace:4,Vertical Roll:5") = 0;
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float radius : hint_range(1.0, 16.0, 0.5) = 4.0;
uniform float speed : hint_range(0.0, 4.0, 0.05) = 1.0;

vec3 yiq(vec3 c) { return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312))); }
vec3 rgb(vec3 c) { return vec3(c.x + 0.956 * c.y + 0.621 * c.z, c.x - 0.272 * c.y - 0.647 * c.z, c.x - 1.106 * c.y + 1.703 * c.z); }
vec3 bleed(vec2 uv) {
	vec3 signal = yiq(lab_sample(uv));
	vec2 chroma = vec2(0.0);
	for (int i = -4; i <= 4; i++) { chroma += yiq(lab_sample(uv + vec2(float(i) * radius * lab_pixel_size().x, 0.0))).yz; }
	return rgb(vec3(signal.x, chroma / 9.0));
}
vec3 effect_color(vec2 uv, vec3 c) {
	float row = floor(uv.y / lab_pixel_size().y);
	float frame = floor(TIME * speed * 30.0);
	if (mode == 1) { return mix(c, bleed(uv), amount); }
	if (mode == 2) {
		float tear = step(0.95, lab_hash(vec2(floor(row / 12.0), frame)));
		uv.x += tear * (lab_hash(vec2(row, frame)) - 0.5) * amount * 0.2;
		return lab_sample(uv);
	}
	if (mode == 3) {
		float band = smoothstep(0.8, 0.97, fract(uv.y + TIME * speed * 0.1));
		return mix(c, vec3(lab_hash(vec2(row, uv.x + frame))), band * amount);
	}
	if (mode == 4) { return c * (1.0 - amount * mod(row + mod(frame, 2.0), 2.0)); }
	if (mode == 5) { return lab_sample(vec2(uv.x, fract(uv.y + TIME * speed * 0.12))); }
	float jitter = (lab_hash(vec2(row, frame)) - 0.5) * amount * lab_pixel_size().x * 8.0;
	uv.x += jitter + sin(row * 0.03 + TIME * speed) * amount * lab_pixel_size().x * 3.0;
	vec3 result = bleed(uv);
	result += (lab_hash(floor(uv / lab_pixel_size()) + frame) - 0.5) * amount * 0.06;
	result *= 1.0 - amount * mod(row, 2.0) * 0.15;
	return result;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

