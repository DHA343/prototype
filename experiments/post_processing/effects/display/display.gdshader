shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("CRT Glass:0,LCD Grid:1,Dot Matrix:2,Glass Reflection:3") = 0;
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float pitch : hint_range(2.0, 12.0, 0.5) = 4.0;
uniform float curvature : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform sampler2D reflection_texture : source_color, repeat_disable, filter_linear;
uniform bool has_reflection_texture = false;

vec3 effect_color(vec2 uv, vec3 c) {
	if (mode == 0) {
		vec2 p = uv * 2.0 - 1.0;
		vec2 warped = (p * (1.0 + curvature * dot(p, p) * 0.2) + 1.0) * 0.5;
		if (any(lessThan(warped, vec2(0.0))) || any(greaterThan(warped, vec2(1.0)))) { return vec3(0.0); }
		float edge = clamp(1.0 - pow(length(p) * 0.7, 2.0) * amount, 0.0, 1.0);
		return lab_sample(warped) * edge;
	}
	vec2 pixel = uv / lab_pixel_size();
	if (mode == 1) {
		float stripe = floor(mod(pixel.x, pitch) * 3.0 / pitch);
		vec3 mask = stripe < 1.0 ? vec3(1.0, 0.3, 0.3) : (stripe < 2.0 ? vec3(0.3, 1.0, 0.3) : vec3(0.3, 0.3, 1.0));
		float horizontal_gap = step(0.12, fract(pixel.y / pitch));
		return c * mix(vec3(1.0), mask * horizontal_gap * 1.7, amount);
	}
	if (mode == 2) {
		vec2 p = pixel / pitch;
		vec3 cell = lab_sample((floor(p) + 0.5) * pitch * lab_pixel_size());
		float dot_mask = 1.0 - smoothstep(0.35, 0.45, length(fract(p) - 0.5));
		return mix(c, cell * dot_mask, amount);
	}
	float band = exp(-pow((uv.x + uv.y * 0.6 - 0.55) * 8.0, 2.0));
	vec3 reflection = vec3(band * 0.3);
	if (has_reflection_texture) { reflection = texture(reflection_texture, uv).rgb; }
	return c + reflection * amount;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

