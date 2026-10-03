shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"
uniform int mode : hint_enum("FXAA:0,Morphological AA:1") = 0;
uniform float edge_threshold : hint_range(0.01, 0.5, 0.01) = 0.08;
uniform float subpixel : hint_range(0.0, 1.0, 0.01) = 0.75;
vec3 effect_color(vec2 uv, vec3 c) {
	vec2 p = lab_pixel_size();
	vec3 north = lab_sample(uv - vec2(0.0, p.y));
	vec3 south = lab_sample(uv + vec2(0.0, p.y));
	vec3 west = lab_sample(uv - vec2(p.x, 0.0));
	vec3 east = lab_sample(uv + vec2(p.x, 0.0));
	float l = lab_luma(c);
	float lo = min(l, min(min(lab_luma(north), lab_luma(south)), min(lab_luma(west), lab_luma(east))));
	float hi = max(l, max(max(lab_luma(north), lab_luma(south)), max(lab_luma(west), lab_luma(east))));
	if (hi - lo < max(edge_threshold, hi * edge_threshold)) { return c; }
	vec2 direction = vec2(-(lab_luma(north) - lab_luma(south)), lab_luma(east) - lab_luma(west));
	direction /= max(abs(direction.x), abs(direction.y)) + 0.001;
	if (mode == 0) {
		vec3 a = (lab_sample(uv + direction * p / 3.0) + lab_sample(uv - direction * p / 3.0)) * 0.5;
		vec3 b = a * 0.5 + (lab_sample(uv + direction * p) + lab_sample(uv - direction * p)) * 0.25;
		float lb = lab_luma(b);
		return mix(c, lb < lo || lb > hi ? a : b, subpixel);
	}
	// Search the local edge extent, then weight across the edge. No SMAA lookup tables.
	vec2 tangent = abs(direction.x) > abs(direction.y) ? vec2(p.x, 0.0) : vec2(0.0, p.y);
	float extent = 1.0;
	for (int i = 1; i <= 8; i++) {
		vec3 a = lab_sample(uv + tangent * float(i));
		vec3 b = lab_sample(uv - tangent * float(i));
		if (abs(lab_luma(a) - l) > edge_threshold || abs(lab_luma(b) - l) > edge_threshold) { break; }
		extent += 1.0;
	}
	vec2 across = vec2(-tangent.y, tangent.x);
	vec3 average = (lab_sample(uv + across * 0.5) + lab_sample(uv - across * 0.5)) * 0.5;
	return mix(c, average, subpixel * (0.3 + 0.7 / extent));
}
void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	COLOR = vec4(mix(screen_color.rgb, effect_color(SCREEN_UV, screen_color.rgb), strength), screen_color.a);
}
