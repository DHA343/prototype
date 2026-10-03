shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Flash:0,Colored Edge:1,Letterbox:2,Circular Mask:3,Wipe:4,Dissolve:5") = 0;
uniform vec4 overlay_color : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float progress : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float size : hint_range(0.01, 0.5, 0.01) = 0.12;
uniform float softness : hint_range(0.001, 0.2, 0.001) = 0.04;
uniform float angle : hint_range(-180.0, 180.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5);

vec3 effect_color(vec2 uv, vec3 c) {
	if (mode == 0) { return mix(c, overlay_color.rgb, progress); }
	if (mode == 1) {
		float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		return mix(c, overlay_color.rgb, (1.0 - smoothstep(size, size + softness, d)) * progress);
	}
	if (mode == 2) { return c * smoothstep(size, size + softness, min(uv.y, 1.0 - uv.y)); }
	if (mode == 3) {
		vec2 p = (uv - center) * vec2(lab_pixel_size().y / lab_pixel_size().x, 1.0);
		return c * (1.0 - smoothstep(progress, progress + softness, length(p)));
	}
	if (mode == 4) {
		vec2 p = lab_rotate(radians(angle)) * (uv - 0.5);
		float mask = smoothstep(progress - 0.5, progress - 0.5 + softness, p.x);
		return mix(overlay_color.rgb, c, mask);
	}
	float mask = smoothstep(progress, progress + softness, lab_hash(floor(uv / lab_pixel_size() / 4.0)));
	return mix(overlay_color.rgb, c, mask);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

