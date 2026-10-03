shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Halftone:0,CMYK Screens:1,Crosshatch:2,Paper:3,Misregistration:4") = 0;
uniform float cell_size : hint_range(2.0, 32.0, 0.5) = 6.0;
uniform float angle : hint_range(-180.0, 180.0, 1.0) = 15.0;
uniform float amount : hint_range(0.0, 2.0, 0.01) = 0.7;
uniform vec4 paper_color : source_color = vec4(0.95, 0.9, 0.78, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);

float ink_dots(vec2 uv, float density, float a) {
	vec2 p = lab_rotate(a) * (uv / lab_pixel_size()) / cell_size;
	float d = length(fract(p) - 0.5);
	return 1.0 - smoothstep(0.5 * sqrt(clamp(density, 0.0, 1.0)) - 0.025, 0.5 * sqrt(clamp(density, 0.0, 1.0)) + 0.025, d);
}
vec3 effect_color(vec2 uv, vec3 c) {
	float a = radians(angle);
	if (mode == 0) { return mix(paper_color.rgb, ink_color.rgb, ink_dots(uv, 1.0 - lab_luma(c), a)); }
	if (mode == 1) {
		vec3 density = 1.0 - clamp(c, 0.0, 1.0);
		float black_ink = min(density.r, min(density.g, density.b));
		density = (density - vec3(black_ink)) / max(1.0 - black_ink, 0.001);
		vec3 coverage = vec3(ink_dots(uv, density.r, a), ink_dots(uv, density.g, a + PI / 3.0), ink_dots(uv, density.b, a + 2.0 * PI / 3.0));
		float black_coverage = ink_dots(uv, black_ink, a + PI / 4.0);
		return paper_color.rgb * (1.0 - coverage) * (1.0 - black_coverage);
	}
	if (mode == 2) {
		vec2 p = lab_rotate(a) * (uv / lab_pixel_size()) / cell_size;
		float l = lab_luma(c);
		float lines = step(fract(p.x + p.y), 0.12) * (1.0 - smoothstep(0.4, 0.8, l));
		lines = max(lines, step(fract(p.x - p.y), 0.12) * (1.0 - smoothstep(0.1, 0.5, l)));
		return mix(paper_color.rgb, ink_color.rgb, lines);
	}
	if (mode == 3) {
		float fiber = lab_hash(floor(uv / lab_pixel_size())) * 0.6 + lab_hash(floor(uv / lab_pixel_size() / 6.0)) * 0.4;
		return c * mix(vec3(1.0), paper_color.rgb, amount * 0.5) + (fiber - 0.5) * amount * 0.12;
	}
	vec2 p = lab_pixel_size() * amount * 3.0;
	return vec3(lab_sample(uv + p).r, c.g, lab_sample(uv - p).b);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

