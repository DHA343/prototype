shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Block Displacement:0,Horizontal Bands:1,Channel Dropout:2,Local Inversion:3,Compression Damage:4") = 0;
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float block_size : hint_range(4.0, 128.0, 1.0) = 32.0;
uniform float speed : hint_range(0.0, 30.0, 1.0) = 8.0;
uniform int channel : hint_enum("Red:0,Green:1,Blue:2") = 0;

vec3 effect_color(vec2 uv, vec3 c) {
	float frame = floor(TIME * speed);
	vec2 block = floor(uv / lab_pixel_size() / block_size);
	float random = lab_hash(block + frame);
	float active = step(1.0 - amount, random);
	if (mode == 0) {
		vec2 shift = vec2(lab_hash(block + frame + 5.0), lab_hash(block + frame + 11.0)) - 0.5;
		return lab_sample(uv + shift * active * amount * 0.2);
	}
	if (mode == 1) {
		float band = lab_hash(vec2(block.y, frame));
		return lab_sample(uv + vec2((band - 0.5) * step(1.0 - amount, band) * amount * 0.3, 0.0));
	}
	if (mode == 2) { c[channel] *= 1.0 - active; return c; }
	if (mode == 3) { return mix(c, 1.0 - c, active); }
	vec3 base = lab_sample((block + 0.5) * block_size * lab_pixel_size());
	float quantization = mix(32.0, 3.0, amount);
	vec3 compressed = floor(mix(c, base, amount) * quantization + 0.5) / quantization;
	float ringing = sin(fract(uv.x / lab_pixel_size().x / block_size) * TAU * 3.0) * length(lab_sobel(uv, 1.0)) * amount * 0.04;
	return compressed + ringing;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

