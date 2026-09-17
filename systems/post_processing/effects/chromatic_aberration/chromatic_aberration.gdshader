shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture
	: hint_screen_texture, source_color, repeat_disable, filter_nearest;

uniform int direction
	: hint_enum("Horizontal", "Vertical", "Radial") = 0;
uniform float amount : hint_range(0.0, 32.0, 0.5) = 2.0;


vec2 get_aberration_direction(vec2 uv) {
	if (direction == 0) {
		return vec2(1.0, 0.0);
	}

	if (direction == 1) {
		return vec2(0.0, 1.0);
	}

	vec2 radial_direction = uv - vec2(0.5);
	float radial_length = length(radial_direction);

	return radial_length > 0.0 ? radial_direction / radial_length : vec2(0.0);
}


void fragment() {
	vec4 center_color = texture(screen_texture, SCREEN_UV);
	vec2 offset = get_aberration_direction(SCREEN_UV) * amount * SCREEN_PIXEL_SIZE;
	vec2 red_uv = clamp(SCREEN_UV + offset, vec2(0.0), vec2(1.0));
	vec2 blue_uv = clamp(SCREEN_UV - offset, vec2(0.0), vec2(1.0));
	vec3 color = vec3(
		texture(screen_texture, red_uv).r,
		center_color.g,
		texture(screen_texture, blue_uv).b
	);

	COLOR = vec4(color, center_color.a);
}
