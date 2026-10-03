shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Target Outline:0,Target Glow:1,Target Distortion:2") = 0;
uniform sampler2D mask_texture : repeat_disable, filter_linear;
uniform sampler2D custom_mask : repeat_disable, filter_linear;
uniform bool has_custom_mask = false;
uniform float radius : hint_range(1.0, 24.0, 0.5) = 4.0;
uniform float amount : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform vec4 effect_tint : source_color = vec4(1.0, 0.7, 0.15, 1.0);

float mask_at(vec2 uv) {
	return has_custom_mask ? texture(custom_mask, uv).r : texture(mask_texture, uv).r;
}
vec3 effect_color(vec2 uv, vec3 c) {
	float mask = mask_at(uv);
	float dilated = mask;
	float blurred = mask * 4.0;
	vec3 light = c * mask * 4.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			if (x != 0 || y != 0) {
				vec2 p = uv + vec2(float(x), float(y)) * lab_pixel_size() * radius;
				float neighbor = mask_at(p);
				dilated = max(dilated, neighbor);
				blurred += neighbor;
				light += lab_sample(p) * neighbor;
			}
		}
	}
	if (mode == 0) { return mix(c, effect_tint.rgb, clamp(dilated - mask, 0.0, 1.0) * min(amount, 1.0)); }
	if (mode == 1) { return c + light / 12.0 * effect_tint.rgb * amount; }
	vec2 offset = vec2(sin(uv.y * 80.0 + TIME * 3.0), cos(uv.x * 80.0 + TIME * 2.0)) * lab_pixel_size() * radius;
	return mix(c, lab_sample(uv + offset * amount), mask);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

