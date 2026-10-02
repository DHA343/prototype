shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_linear;

uniform vec2 rgb_red_offset = vec2(-2.0, 0.5);
uniform vec2 rgb_blue_offset = vec2(2.0, -0.5);
uniform float rgb_strength : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform vec2 ghost_offset = vec2(5.0, 1.0);
uniform float ghost_strength : hint_range(0.0, 1.0, 0.01) = 0.2;


vec3 sample_offset(vec2 screen_uv, vec2 pixel_size, vec2 offset) {
	// Positive offsets move the visible image right / down, rather than the sampling point.
	vec2 sample_uv = clamp(screen_uv - offset * pixel_size,
		pixel_size * 0.5, vec2(1.0) - pixel_size * 0.5);
	return textureLod(screen_texture, sample_uv, 0.0).rgb;
}


void fragment() {
	vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 weighted_color = screen_color.rgb;
	float total_weight = 1.0;

	if (rgb_strength > 0.0 && (rgb_red_offset != vec2(0.0) || rgb_blue_offset != vec2(0.0))) {
		vec3 separated_color = screen_color.rgb;
		if (rgb_red_offset != vec2(0.0)) {
			separated_color.r = sample_offset(SCREEN_UV, SCREEN_PIXEL_SIZE, rgb_red_offset).r;
		}
		if (rgb_blue_offset != vec2(0.0)) {
			separated_color.b = sample_offset(SCREEN_UV, SCREEN_PIXEL_SIZE, rgb_blue_offset).b;
		}
		weighted_color += separated_color * rgb_strength;
		total_weight += rgb_strength;
	}
	if (ghost_strength > 0.0 && ghost_offset != vec2(0.0)) {
		weighted_color += sample_offset(SCREEN_UV, SCREEN_PIXEL_SIZE, ghost_offset) * ghost_strength;
		total_weight += ghost_strength;
	}

	// Both secondary images share the original signal; neither ghosts the other.
	// Normalized weights preserve constant colors and HDR levels without clipping.
	COLOR = vec4(weighted_color / total_weight, screen_color.a);
}
