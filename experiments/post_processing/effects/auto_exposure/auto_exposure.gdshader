shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Auto Exposure:0") = 0;
uniform float adapted_exposure = 1.0;
uniform float middle_gray : hint_range(0.02, 0.5, 0.01) = 0.18;
uniform float min_exposure : hint_range(0.05, 1.0, 0.01) = 0.25;
uniform float max_exposure : hint_range(1.0, 16.0, 0.1) = 4.0;
uniform float adaptation_speed : hint_range(0.1, 10.0, 0.1) = 1.5;

vec3 effect_color(vec2 uv, vec3 c) {
	return c * adapted_exposure;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

