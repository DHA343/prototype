shader_type canvas_item;
render_mode unshaded;
#include "../_shared/common.gdshaderinc"

uniform int mode : hint_enum("Multi-scale Bloom:0,Soft Focus:1,Halation:2,Anamorphic Streak:3,Starburst:4,Lens Ghosts:5,Lens Dirt:6") = 0;
uniform float amount : hint_range(0.0, 3.0, 0.01) = 0.6;
uniform float radius : hint_range(1.0, 32.0, 0.5) = 8.0;
uniform float threshold : hint_range(0.0, 4.0, 0.05) = 0.8;
uniform int rays : hint_range(2, 8, 1) = 4;
uniform sampler2D pyramid_texture : repeat_disable, filter_linear;
uniform sampler2D dirt_texture : source_color, repeat_disable, filter_linear;
uniform bool has_dirt_texture = false;
uniform vec4 halo_color : source_color = vec4(1.0, 0.25, 0.08, 1.0);

vec3 bright(vec2 uv) {
	vec3 c = lab_sample(uv);
	return c * max(lab_luma(c) - threshold, 0.0) / max(lab_luma(c), 0.0001);
}
vec3 effect_color(vec2 uv, vec3 c) {
	if (mode == 0) { return c + texture(pyramid_texture, uv).rgb * amount; }
	vec3 soft = lab_blur(uv, radius);
	if (mode == 1) { return mix(c, soft, amount * 0.5) + soft * amount * 0.12; }
	if (mode == 2) { return c + max(soft - c, 0.0) * halo_color.rgb * amount; }
	vec3 light = vec3(0.0);
	if (mode == 3 || mode == 4) {
		int count = mode == 3 ? 1 : rays;
		for (int ray = 0; ray < 8; ray++) {
			if (ray < count) {
				float a = float(ray) * PI / float(count);
				vec2 axis = vec2(cos(a), sin(a));
				for (int i = -8; i <= 8; i++) {
					float t = float(i) / 8.0;
					light += bright(uv + axis * t * radius * lab_pixel_size() * 6.0) * (1.0 - abs(t) * 0.75) / (10.25 * float(count));
				}
			}
		}
		return c + light * amount;
	}
	if (mode == 5) {
		for (int i = 1; i <= 5; i++) {
			float factor = -float(i) * 0.45;
			vec2 sample_uv = vec2(0.5) + (uv - 0.5) * factor;
			float fade = 1.0 - smoothstep(0.2, 0.7, length(sample_uv - 0.5));
			light += bright(sample_uv) * fade * vec3(1.0, 0.65 + 0.07 * float(i), 0.5 + 0.1 * float(i));
		}
		return c + light * amount * 0.25;
	}
	float dirt = smoothstep(0.6, 0.9, lab_hash(floor(uv * 60.0)));
	if (has_dirt_texture) { dirt = texture(dirt_texture, uv).r; }
	return c + max(soft - threshold, 0.0) * dirt * amount;
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec3 result = effect_color(SCREEN_UV, screen_color.rgb);
	COLOR = vec4(max(mix(screen_color.rgb, result, strength), vec3(0.0)), screen_color.a);
}

