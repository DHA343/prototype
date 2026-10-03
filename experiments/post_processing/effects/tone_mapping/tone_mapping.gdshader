shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"
uniform int mode : hint_enum("Linear Clamp:0,Reinhard:1,Extended Reinhard:2,ACES Approximation:3,Hable:4,Filmic:5,Logarithmic:6") = 3;
uniform float exposure : hint_range(-6.0, 6.0, 0.05) = 0.0;
uniform float white_point : hint_range(1.0, 16.0, 0.1) = 4.0;
vec3 hable(vec3 x) {
	return ((x * (0.15 * x + 0.05) + 0.004) / (x * (0.15 * x + 0.5) + 0.06)) - 0.0666667;
}
vec3 effect_color(vec3 c) {
	vec3 x = max(c * exp2(exposure), vec3(0.0));
	if (mode == 0) { return clamp(x, 0.0, 1.0); }
	if (mode == 1) { return x / (1.0 + x); }
	if (mode == 2) { return x * (1.0 + x / (white_point * white_point)) / (1.0 + x); }
	if (mode == 3) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
	if (mode == 4) { return clamp(hable(x * 2.0) / hable(vec3(white_point)), 0.0, 1.0); }
	if (mode == 5) {
		x = max(vec3(0.0), x - 0.004);
		return (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
	}
	return log(vec3(1.0) + x) / log(1.0 + white_point);
}
void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	COLOR = vec4(mix(screen_color.rgb, effect_color(screen_color.rgb), strength), screen_color.a);
}
