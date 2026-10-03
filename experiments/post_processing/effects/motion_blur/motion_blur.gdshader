shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Object Motion Blur:0") = 0;
uniform sampler2D velocity_texture : repeat_disable, filter_linear;
uniform sampler2D custom_velocity : repeat_disable, filter_linear;
uniform bool has_custom_velocity = false;
uniform float shutter : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float maximum_pixels : hint_range(1.0, 128.0, 1.0) = 64.0;

vec3 effect_color(vec2 uv, vec3 c) {
	vec3 motion = has_custom_velocity ? texture(custom_velocity, uv).rgb : texture(velocity_texture, uv).rgb;
	vec2 velocity = (motion.rg - 0.5) / 8.0 * shutter * motion.b;
	vec2 pixel_motion = velocity / lab_pixel_size();
	float pixel_length = length(pixel_motion);
	if (pixel_length > maximum_pixels) { velocity *= maximum_pixels / pixel_length; }
	vec3 result = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0 - 0.5;
		result += lab_sample(uv + velocity * t);
	}
	return result / 12.0;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

