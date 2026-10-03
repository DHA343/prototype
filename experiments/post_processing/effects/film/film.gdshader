shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Film Grain:0,Color Noise:1,Monochrome Noise:2,Dust and Scratches:3,Flicker:4,Film Weave:5") = 0;
uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float grain_size : hint_range(1.0, 8.0, 0.5) = 1.0;
uniform float speed : hint_range(0.0, 60.0, 1.0) = 24.0;
uniform float scratch_density : hint_range(0.0, 0.2, 0.001) = 0.01;

vec3 effect_color(vec2 uv, vec3 c) {
	float frame = floor(TIME * speed);
	vec2 p = floor(uv / lab_pixel_size() / grain_size);
	float noise = lab_hash(p + frame) - 0.5;
	if (mode == 0) {
		float grain = noise + lab_hash(p.yx + frame + 17.0) - 0.5;
		return c + grain * amount * (0.3 + 0.7 * sqrt(clamp(lab_luma(c), 0.0, 1.0)));
	}
	if (mode == 1) { return c + (vec3(lab_hash(p + frame), lab_hash(p + frame + 19.0), lab_hash(p + frame + 73.0)) - 0.5) * amount; }
	if (mode == 2) { return c + noise * amount; }
	if (mode == 3) {
		vec2 cell = floor(uv * vec2(120.0, 80.0));
		float dust = step(1.0 - scratch_density, lab_hash(cell + frame)) * (1.0 - smoothstep(0.08, 0.2, length(fract(uv * vec2(120.0, 80.0)) - 0.5)));
		float scratches = step(1.0 - scratch_density * 0.15, lab_hash(vec2(floor(p.x / 2.0), frame)));
		return mix(c, vec3(0.9), max(dust, scratches) * amount);
	}
	if (mode == 4) { return c * (1.0 + amount * (lab_hash(vec2(frame, 0.0)) - 0.5)); }
	vec2 offset = vec2(lab_hash(vec2(frame, 1.0)), lab_hash(vec2(frame, 9.0))) - 0.5;
	return lab_sample(uv + offset * amount * 16.0 * lab_pixel_size());
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

